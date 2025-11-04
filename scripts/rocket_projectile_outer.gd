extends Node3D

func play_explosion_sfx_then_remove (explosion_pos):
	$ExplodeOnImpact.global_position = explosion_pos
	$ExplodeOnImpact.play()
	var timer = get_tree().create_timer(1.5)
	await timer.timeout
	queue_free()

func _on_rocket_projectile_inner_rocket_exploded(explosion_pos):
	# Disable network sync before destruction to prevent errors
	var network_sync = get_node_or_null("NetworkSync")
	if network_sync:
		network_sync.set_process(false)
	play_explosion_sfx_then_remove(explosion_pos)

func _on_rocket_projectile_inner_rocket_out_of_bounds():
	# Disable network sync before destruction
	var network_sync = get_node_or_null("NetworkSync")
	if network_sync:
		network_sync.set_process(false)
	queue_free()
