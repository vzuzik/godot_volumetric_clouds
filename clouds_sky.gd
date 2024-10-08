@tool
extends Sky
class_name CloudSky

@export_group("Cloud Settings")
@export var windDirection = Vector2(1.0, 0.0)
@export var windSpeed = 1.0
@export var density = 0.05
@export var cloudCoverage = 0.25
@export var timeOffset = 0.0

@export_group("Sky Settings")
@export var sunColor = Color.WHITE
@export var sunEnergy = 1.0
@export var sunAngles = Vector2(10.0, 0.0):
	set(newAngles):
		sunAngles = newAngles
		sky_material.set_shader_parameter("sunDirection", getDirection(sunAngles))
@export var sunDiskSize = 1.0:
	set(size):
		sunDiskSize = size
		sky_material.set_shader_parameter("sunDiskSize", sunDiskSize)
@export var groundColor = Color.DARK_SLATE_GRAY
@export var groundRadius = 6000000.0
@export var skyStartRadius = 6001500.0
@export var skyEndRadius = 6004000.0

var sunLight:Light3D:
	set(light):
		sunLight = light
		if is_instance_valid(sunLight):
			sunAngles = Vector2()
			sky_material.set_shader_parameter("sunDirection", Vector2())
		else:
			sunAngles = Vector2(10.0, 0.0)

# Everything in the compute shader must be cached here so that it only updates
# after swapping to a new texture.
class FrameData:
	var windDirection = Vector2(1.0, 0.0)
	var windSpeed = 1.0
	var density = 0.05
	var cloudCoverage = 0.25
	var timeOffset = 0.0
	var groundColor = Color(1.0, 1.0, 1.0)
	var groundRadius = 6000000.0
	var skyStartRadius = 6001500.0
	var skyEndRadius = 6004000.0
	var sunDirection = Vector3(0.0, -1.0, 0.0)
	var sunEnergy = 1.0
	var sunColor = Color(1.0, 1.0, 1.0)

var frame_data = FrameData.new()
var update_position = Vector2i(0, 0)
var frames_to_update = 16 # needs to always be a power of two value
var update_region_size:int
var num_workgroups:int

var textures = []
var texture_to_update = 0
var texture_to_blend_from = 1
var texture_to_blend_to = 2

var sky_lut = SkyLUT.new()
var transmittance_lut = TransmittanceLUT.new()
var textureSize = 768 # Needs to be divisble by sqrt(frames_to_update)
var frame = 0
var reset_sky = true

func _init():
	process_mode = Sky.PROCESS_MODE_INCREMENTAL
	radiance_size = Sky.RADIANCE_SIZE_64
	
	var frames_sqrt = int(sqrt(frames_to_update))
	update_region_size = textureSize / frames_sqrt
	num_workgroups = update_region_size / 8

	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("shaders/clouds.gdshader")
	sky_material.set_shader_parameter("sunDirection", getDirection(sunAngles))
	sky_material.set_shader_parameter("sunDiskSize", sunDiskSize)
	sky_material.set_shader_parameter("source_transmittance", transmittance_lut)
	
	RenderingServer.call_on_render_thread.call_deferred(_initialize_compute_code.bind(textureSize))

func reset():
	reset_sky = true

func init():
	_update_per_frame_data()
	for i in range(frames_to_update * 2):
		_update_sky()

func getDirection(angles:Vector2) -> Vector3:
	var basis = Basis.from_euler(Vector3(deg_to_rad(-angles.x), deg_to_rad(-angles.y), 0.0))
	return (basis * Vector3(0.0, 0.0, 1.0)).normalized()

func _update_sky():
	if reset_sky:
		reset_sky = false
		init()

	if frame >= frames_to_update:
		# Increase our next texture index
		texture_to_update = (texture_to_update + 1) % 3
		texture_to_blend_from = (texture_to_blend_from + 1) % 3
		texture_to_blend_to = (texture_to_blend_to + 1) % 3
		_update_per_frame_data() # Only call once per update otherwise quads get out of sync

		sky_material.set_shader_parameter("blend_from_texture", textures[texture_to_blend_from])
		sky_material.set_shader_parameter("blend_to_texture", textures[texture_to_blend_to])
		
		sky_material.set_shader_parameter("sky_blend_from_texture", sky_lut.back_texture[0])
		sky_material.set_shader_parameter("sky_blend_to_texture", sky_lut.back_texture[1])

		frame = 0

	sky_material.set_shader_parameter("blend_amount", float(frame) / float(frames_to_update))

	RenderingServer.call_on_render_thread(_render_process.bind(texture_to_update))
	
	update_position.x += update_region_size
	if update_position.x >= textureSize:
		update_position.x = 0
		update_position.y += update_region_size
	if update_position.y >= textureSize:
		update_position = Vector2i(0, 0)
		
	frame += 1

func _update_per_frame_data():
	frame_data.windDirection = windDirection
	frame_data.windSpeed = windSpeed
	frame_data.density = density
	frame_data.cloudCoverage = cloudCoverage
	frame_data.timeOffset = timeOffset
	frame_data.groundColor = groundColor
	frame_data.groundRadius = groundRadius
	frame_data.skyStartRadius = skyStartRadius
	frame_data.skyEndRadius = skyEndRadius
	
	if is_instance_valid(sunLight):
		frame_data.sunDirection = (sunLight.transform.basis * Vector3(0.0, 0.0, 1.0)).normalized()
		frame_data.sunEnergy = sunLight.light_energy
		frame_data.sunColor = sunLight.light_color.srgb_to_linear()
	else:
		frame_data.sunDirection = getDirection(sunAngles)
		frame_data.sunEnergy = sunEnergy
		frame_data.sunColor = sunColor
	
	sky_lut.update_lut(frame_data.sunDirection)

func _validate_property(property):
	match property.name:
		"sky_material", "process_mode", "radiance_size":
			property.usage &= ~PROPERTY_USAGE_EDITOR

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		for texId in texture_rd:
			if texId.is_valid():
				rd.free_rid(texId)
		if shader_rd:
			rd.free_rid(shader_rd)
		if noise_sampler:
			rd.free_rid(noise_sampler)
		if sky_sampler:
			rd.free_rid(sky_sampler)


###############################################################################
const SKY_CONSTANT_SIZE = 24 # 24 floats per FrameData in clouds.glsl

var rd:RenderingDevice
var shader_rd:RID
var pipeline:RID

# We use 3 textures:
# - One to render into
# - One that contains the last frame rendered
# - One for the frame before that
var texture_rd = [ RID(), RID(), RID() ]
var texture_set = [ RID(), RID(), RID() ]
var noise_uniform_set = RID()
var sky_uniform_set = [ RID(), RID(), RID() ]
var sky_uniforms = [ PackedFloat32Array(SKY_CONSTANT_SIZE), PackedFloat32Array(SKY_CONSTANT_SIZE), PackedFloat32Array(SKY_CONSTANT_SIZE) ]
var noise_sampler
var sky_sampler

func _render_process(textureIndex):
	textures[textureIndex].texture_rd_rid = texture_rd[textureIndex]
	_fill_push_constant(textureIndex)
	
	# Run our compute shader.
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, sky_uniform_set[(sky_lut.current_texture + 2) % 3], 2)
	rd.compute_list_bind_uniform_set(compute_list, noise_uniform_set, 1)
	rd.compute_list_bind_uniform_set(compute_list, texture_set[textureIndex], 0)

	rd.compute_list_set_push_constant(compute_list, sky_uniforms[textureIndex].to_byte_array(), sky_uniforms[textureIndex].size() * 4)
	rd.compute_list_dispatch(compute_list, num_workgroups, num_workgroups, 1)
	rd.compute_list_end()

	
func _fill_push_constant(index:int):
	var uniforms = sky_uniforms[index]
	
	# match order in clouds.glsl, including padding
	uniforms[0] = textureSize
	uniforms[1] = textureSize
	uniforms[2] = update_position.x
	uniforms[3] = update_position.y

	uniforms[4] = frame_data.windDirection.x
	uniforms[5] = frame_data.windDirection.y
	uniforms[6] = frame_data.windSpeed
	uniforms[7] = frame_data.density
	
	uniforms[8] = frame_data.groundColor.r
	uniforms[9] = frame_data.groundColor.g
	uniforms[10] = frame_data.groundColor.b
	uniforms[11] = frame_data.groundRadius
	
	uniforms[12] = frame_data.sunDirection.x
	uniforms[13] = frame_data.sunDirection.y
	uniforms[14] = frame_data.sunDirection.z
	uniforms[15] = frame_data.sunEnergy
	
	uniforms[16] = frame_data.sunColor.r
	uniforms[17] = frame_data.sunColor.g
	uniforms[18] = frame_data.sunColor.b
	uniforms[19] = Time.get_ticks_msec() * 0.001
	
	uniforms[20] = frame_data.skyStartRadius
	uniforms[21] = frame_data.skyEndRadius
	uniforms[22] = frame_data.cloudCoverage
	uniforms[23] = frame_data.timeOffset

func _create_uniform_set(p_texture_rd:RID) -> RID:
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(p_texture_rd)
	return rd.uniform_set_create([uniform], shader_rd, 0)

func _create_noise_uniform_set() -> RID:
	var uniforms = []
	
	var sampler_state = RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	
	noise_sampler = rd.sampler_create(sampler_state)
	
	var large_scale_noise = preload("textures/perlworlnoise.png")
	var LSN_rd = RenderingServer.texture_get_rd_texture(large_scale_noise.get_rid())
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 0
	uniform.add_id(noise_sampler)
	uniform.add_id(LSN_rd)
	uniforms.push_back(uniform)
	
	var small_scale_noise = preload("textures/worlnoise.png")
	var SSN_rd = RenderingServer.texture_get_rd_texture(small_scale_noise.get_rid())
	
	uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 1
	uniform.add_id(noise_sampler)
	uniform.add_id(SSN_rd)
	uniforms.push_back(uniform)
	
	var weather_noise = preload("textures/weather.png")
	var W_rd = RenderingServer.texture_get_rd_texture(weather_noise.get_rid())
	
	uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 2
	uniform.add_id(noise_sampler)
	uniform.add_id(W_rd)
	uniforms.push_back(uniform)

	return rd.uniform_set_create(uniforms, shader_rd, 1)
	
func _create_sky_uniform_set(tex_id : int) -> RID:
	var uniforms = []
		
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.binding = 0
	uniform.add_id(sky_sampler)
	uniform.add_id(sky_lut.texture_rd[tex_id])
	uniforms.push_back(uniform)
	
	return rd.uniform_set_create(uniforms, shader_rd, 2)

func _initialize_compute_code(p_textureSize):
	rd = RenderingServer.get_rendering_device()
	
	# Create our shader
	var shader_file = preload("res://cloud_sky/shaders/compute/clouds.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_rd = rd.shader_create_from_spirv(shader_spirv)
	if not shader_rd.is_valid():
		return
	
	pipeline = rd.compute_pipeline_create(shader_rd)

	# Create our textures to manage our wave
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = p_textureSize
	tf.height = p_textureSize
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT + RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	if Engine.is_editor_hint():
		tf.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	noise_uniform_set = _create_noise_uniform_set()

	var sampler_state = RDSamplerState.new()
	sampler_state = RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	
	sky_sampler = rd.sampler_create(sampler_state)

	sky_uniform_set[0] = _create_sky_uniform_set(0)
	sky_uniform_set[1] = _create_sky_uniform_set(1)
	sky_uniform_set[2] = _create_sky_uniform_set(2)

	# Create our textures
	for i in texture_rd.size():
		texture_rd[i] = rd.texture_create(tf, RDTextureView.new(), [])

		# Make sure our textures are cleared
		rd.texture_clear(texture_rd[i], Color(float(i==0), float(i==1), float(i==2), 0), 0, 1, 0, 1)

		# Now create our uniform set so we can use these textures in our shader
		texture_set[i] = _create_uniform_set(texture_rd[i])
		textures.push_back(Texture2DRD.new())

	RenderingServer.connect("frame_pre_draw", _update_sky)
