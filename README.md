Volumetric Clouds and Sun

This package based on this demo https://github.com/clayjohn/godot-volumetric-cloud-demo-v2 with some changes
This package requires Godot 4.3 or later.

Features:
Physically accurate atmosphere for much more realistic sky and lighting
Renders the hemisphere to a texture over 64 frames
Interpolates between two copies of that texture to hide changes
Can only run on the Forward+ or Mobile rendering backends

# How to use
## INSTALL
Put package files to any location in your godot project.
Create new Scene 3D
Add WorldEnvironment to your scene and create empty Environment

## CASE 1
In your Environment create new CloudSky to the "Sky" property. Then tweak the exposed properties as you see fit.
You can control sun orientation by changind the "sunAngles" property

## CASE 2
Add DirectionLight3D to your scene, attach the "sun_light.gd" script, reload project and now you sun will be controller by DirectionalLight3D
Direction, energy, and color from the DirectionalLight3D will be automatically applied to the sun

## CASE 3
By script get node WorldEnvironment then get the 'Environment' property
set the 'sky' property as CloudSky.new()
Start your project by pressing F5
