# Volumetric Clouds and Sun

This package based on this demo https://github.com/clayjohn/godot-volumetric-cloud-demo-v2 with some changes
This package requires Godot 4.3 or later.

Features:
Physically accurate atmosphere for much more realistic sky and lighting.
Renders the hemisphere to a texture over 64 frames.
Interpolates between two copies of that texture to hide changes.
Can only run on the Forward+ or Mobile rendering backends.

## How to use
### INSTALL
Put package files to any location in your godot project.
Create new Scene 3D.
Add WorldEnvironment to your scene and create empty Environment.

### CASE 1
In your Environment create new CloudSky to the "Sky" property. 
Then tweak the exposed properties as you see fit.
You can control sun orientation by changind the "sunAngles" property.

### CASE 2
In your Environment create new CloudSky to the "Sky" property. Then tweak the exposed properties as you see fit.
Add DirectionLight3D to your scene, attach the "sun_light.gd" script and assign the 'World Environment' property to WorldEnvironment node.
Reload project and now you sun will be controller by DirectionalLight3D.
Direction, energy, and color from the DirectionalLight3D will be automatically applied to the sun.

### CASE 3
By script get node WorldEnvironment then get the 'Environment' property.
set the 'sky' property as CloudSky.new().
Start your project by pressing F5.

### Screenshots
![image](https://github.com/user-attachments/assets/a6bb8142-6abe-42b1-9197-123b10310048)
![image](https://github.com/user-attachments/assets/d3681002-e4ce-4916-b7c8-da23f3a1aba9)
![image](https://github.com/user-attachments/assets/c77f6b43-1c6d-40ff-b32a-4c12bff422cd)
![image](https://github.com/user-attachments/assets/5810270a-719b-4df5-b256-432a872c06b3)
![image](https://github.com/user-attachments/assets/ca6a1d95-e9fe-49a7-a871-dffc7fef9817)




