extends RigidBody3D

func _on_body_entered(body):
	if body is VehicleBody3D:
		body.reduce_rocket_reload_speed()
		queue_free()
