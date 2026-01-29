extends Node

# Manages multiplayer rocket spawning and synchronization
# This replaces the local rocket spawning logic for networked games

const RocketProjectile = preload("res://scenes/rocket_projectile.tscn")

# Called by RocketLauncher when a player fires a rocket
@rpc("any_peer", "call_local", "reliable")
func spawn_multiplayer_rocket(launcher_transform: Transform3D, firing_peer_id: int, player_number: int, rocket_count: int, launch_power: float):
	# Instantiate the rocket on ALL clients
	var rocket_projectile = RocketProjectile.instantiate()

	# Give the rocket a stable, unique name to avoid @Node3D@XX path issues
	var rocket_name = "Rocket_%d_%d" % [firing_peer_id, rocket_count]
	rocket_projectile.name = rocket_name

	# Add custom network data to track ownership BEFORE adding to tree
	var rocket_inner = rocket_projectile.get_node("RocketProjectileInner")
	var network_id = str(firing_peer_id) + "_" + str(rocket_count)
	rocket_inner.set_meta("network_rocket_id", network_id)
	rocket_inner.set_meta("firing_player_number", player_number)
	rocket_inner.set_meta("firing_peer_id", firing_peer_id)

	# Set transform and add to tree FIRST (before setting authority)
	rocket_projectile.global_transform = launcher_transform
	add_child(rocket_projectile)  # Add under MultiplayerRocketManager for stable paths

	# THEN set up multiplayer authority after node is in tree
	# This ensures the MultiplayerSynchronizer properly registers with the correct authority
	rocket_projectile.set_multiplayer_authority(firing_peer_id)
	rocket_inner.set_multiplayer_authority(firing_peer_id)

	# Also set authority on the NetworkSync node itself
	var network_sync = rocket_projectile.get_node_or_null("NetworkSync")
	if network_sync:
		network_sync.set_multiplayer_authority(firing_peer_id)

	# Re-run network authority setup now that authority is properly set
	# (The initial setup in _ready() ran before authority was assigned)
	if rocket_inner.has_method("setup_network_authority"):
		rocket_inner.setup_network_authority()

	# Setup rocket on this client
	setup_rocket_local(rocket_inner, player_number, rocket_count, launch_power)

func setup_rocket_local(rocket_inner: RigidBody3D, player_number: int, rocket_count: int, launch_power: float):
	# Register with SpectatorManager (only on server)
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
	
	# Fire the thruster
	rocket_inner.fire_thruster()
	
	# Scale animation
	var projectile_mesh = rocket_inner.get_node("RocketProjectileMesh")
	var collision_shape = rocket_inner.get_node("CollisionShape3D")
	
	var mesh_initial_scale = projectile_mesh.scale
	var collision_initial_scale = collision_shape.scale
	var tween = create_tween()
	tween.parallel().tween_property(collision_shape, "scale", collision_initial_scale * 2.5, 0.2)

	# Only the authority (firing player) should apply physics forces
	if rocket_inner.is_multiplayer_authority():
		# Apply launch force
		var launch_impulse = -rocket_inner.global_transform.basis.x * launch_power
		rocket_inner.apply_central_impulse(launch_impulse)
