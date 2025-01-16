extends StaticBody3D

func _on_area_3d_body_entered(body):
	if body is VehicleBody3D:
		# Temporarily increase priority
		$GravityArea3D.priority = 2
		print("Priority increased to 2 on: ", name)
		
		# Create timer to reset priority
		var timer = get_tree().create_timer(1.0)
		
		timer.timeout.connect(func(): $GravityArea3D.priority = 0)
		body.update_new_center_of_gravity_point($GravityArea3D.global_position)
