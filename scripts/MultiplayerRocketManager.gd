extends Node

# Manages multiplayer rocket spawning and synchronization
# This replaces the local rocket spawning logic for networked games

const RocketProjectile = preload("res://scenes/rocket_projectile.tscn")

# Called by RocketLauncher when a player fires a rocket
@rpc("any_peer", "call_local", "reliable")
func spawn_multiplayer_rocket(launcher_transform: Transform3D, firing_peer_id: int, player_number: int, rocket_count: int, launch_power: float):
	# Instantiate the rocket
	var rocket_projectile = RocketProjectile.instantiate()
	
	# Set up multiplayer authority - the firing player's client controls this rocket
	var rocket_inner = rocket_projectile.get_node("RocketProjectileInner")
	rocket_inner.set_multiplayer_authority(firing_peer_id)
	rocket_projectile.set_multiplayer_authority(firing_peer_id)
	
	# Add custom network data to track ownership
	# Use a unique network ID that will be the same across all clients
	var network_id = str(firing_peer_id) + "_" + str(rocket_count)
	rocket_inner.set_meta("network_rocket_id", network_id)
	rocket_inner.set_meta("firing_player_number", player_number)
	rocket_inner.set_meta("firing_peer_id", firing_peer_id)
	
	# Add to scene tree
	get_tree().get_root().add_child(rocket_projectile)
	rocket_projectile.global_transform = launcher_transform
	
	# Register with SpectatorManager (only needs to happen once, on server/host)
	if multiplayer.is_server():
		var spectator_manager = get_node_or_null("/root/RootNode/SpectatorManager")
		if spectator_manager:
			var should_register = GameSettings.debug_mode_on or (rocket_count % 3 == 0)
			if should_register:
				spectator_manager.register_rocket(rocket_inner)
	
	# Register for audio (each client handles their own audio)
	var root_node = get_node_or_null("/root/RootNode")
	if root_node:
		root_node.register_rocket_for_audio(rocket_inner)
	
	# Fire the thruster and apply launch force
	rocket_inner.fire_thruster()
	
	# Scale animation happens on all clients for visual consistency
	var projectile_mesh = rocket_inner.get_node("RocketProjectileMesh")
	var collision_shape = rocket_inner.get_node("CollisionShape3D")
	
	var mesh_initial_scale = projectile_mesh.scale
	var collision_initial_scale = collision_shape.scale
	var tween = create_tween()
	
	# we used to need this but don't seem to since stopping setting
	# freeze = true on the puppet rockets
	# Keep it here for now just as a reminder / in case we need to bring it back.

	#if rocket_inner.is_multiplayer_authority():
		## Scale the mesh to 3x its current scale
		#tween.tween_property(projectile_mesh, "scale", mesh_initial_scale * 3, 0.2)
	#else:
		## Scale the mesh to 15x its current scale (seems to be necessary for the puppet's mesh)
		#tween.tween_property(projectile_mesh, "scale", mesh_initial_scale * 15, 0.05)
	## Scale the collision shape to 2.5x  its current scale
	tween.parallel().tween_property(collision_shape, "scale", collision_initial_scale * 2.5, 0.2)

	# Only the authority (firing player) should apply physics forces
	if rocket_inner.is_multiplayer_authority():
		# Apply launch force
		var launch_impulse = -rocket_inner.global_transform.basis.x * launch_power
		rocket_inner.apply_central_impulse(launch_impulse)
