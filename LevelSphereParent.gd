extends StaticBody3D

func _on_area_3d_body_entered(body):
	if body is VehicleBody3D:
		body.update_new_center_of_gravity_point($GravityArea3D.global_position)
	
