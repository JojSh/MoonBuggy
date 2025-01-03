extends StaticBody3D

func _on_area_3d_body_entered(body):
	if body is VehicleBody3D:
		print("Updating vehicle's new center of gravity to: ", $GravityArea3D.global_position)
		body.update_new_center_of_gravity_point($GravityArea3D.global_position)
		body.switch_on_orientation()
	# if a vehiclebody3d -> send it the center of gravity information
	# That VB3d can then update its internal gravity_point (and orient itself to be upright vs this point)
