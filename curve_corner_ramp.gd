extends StaticBody3D

func _on_area_3d_body_entered(body):
	if body is VehicleBody3D:
		# Set the vehicle's surface type to match this gravity area
		body.set_on_corner_ramp_true()
		#body.set_surface_type($GravityArea3D.surface_type)
#
		#$GravityArea3D.priority = 2
#
		## Create timer to reset priority
		#var timer = get_tree().create_timer(1.0)
#
		#timer.timeout.connect(func(): $GravityArea3D.priority = 0)
		#body.update_new_center_of_gravity_point($GravityArea3D.global_position)
		#
		## Use the gradual reorientation for gravity changes with a small delay
		## The reorient_vehicle_over_time function will check cooldown internally
		#await get_tree().create_timer(0.1).timeout
		#body.reorient_vehicle_over_time(0.25)


func _on_area_3d_body_exited(body):
	if body is VehicleBody3D:
		body.set_on_corner_ramp_false()
