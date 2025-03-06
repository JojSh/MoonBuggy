extends Node3D

func play_explosion_sfx_then_remove ():
	$ExplodeOnImpact.play()
	var timer = get_tree().create_timer(1.5)
	await timer.timeout
	queue_free()

func _on_rocket_projectile_inner_rocket_exploded():
	play_explosion_sfx_then_remove()

func _on_rocket_projectile_inner_rocket_out_of_bounds():
	queue_free()
