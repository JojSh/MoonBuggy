@tool
extends StaticBody3D

@export var colour: Color
@export var gravity_direction: Vector3 = Vector3.DOWN

func _ready():
	var material = $MeshInstance3D.get_surface_override_material(0).duplicate()
	material.albedo_color = colour
	$MeshInstance3D.set_surface_override_material(0, material)
	$GravityArea3D.gravity_direction = gravity_direction

func _on_area_3d_body_entered(body):
	if body is VehicleBody3D:
		# Set the vehicle's surface type to match this gravity area
		body.set_surface_type($GravityArea3D.surface_type)

		print('CURRENT SURFACE NAME:', name) #not being set to LevelCube2 !?
		body.update_side_surface_gravity_direction(-$GravityArea3D.gravity_direction)

		$GravityArea3D.priority = 2

		# Create timer to reset priority
		var timer = get_tree().create_timer(1.0)

		timer.timeout.connect(func(): $GravityArea3D.priority = 0)
		body.update_new_center_of_gravity_point($GravityArea3D.global_position)
		
		# Use the gradual reorientation for gravity changes with a small delay
		# The reorient_vehicle_over_time function will check cooldown internally
		await get_tree().create_timer(0.1).timeout
		body.reorient_vehicle_over_time(0.25)
