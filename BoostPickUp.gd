extends RigidBody3D

func _on_body_entered(body):
	if body is VehicleBody3D:
		body.increment_boost_level()
		queue_free()
