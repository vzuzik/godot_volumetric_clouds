@tool
extends DirectionalLight3D

@export var worldEnvironment:NodePath
@export var animateTime = true:
	set(value):
		animateTime = value
		set_process(animateTime)

var _sky:CloudSky

func _ready():
	var wenv = get_node(worldEnvironment)
	if wenv is WorldEnvironment and wenv.environment is Environment and wenv.environment.sky is CloudSky:
		_sky = wenv.environment.sky
		_sky.sunLight = self
	else:
		push_warning("DirectionalLight3D: Sky should be CloudSky type")

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(_sky):
			_sky.sunLight = null

func _process(delta:float):
	if is_instance_valid(_sky):
		_sky.timeOffset += delta * 0.01
