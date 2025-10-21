extends RigidBody3D

signal rocket_exploded(position)
signal rocket_out_of_bounds

@onready var rocket_controller: Node = null

# Network synchronization variables
var is_network_authority: bool = false
var last_sync_position: Vector3 = Vector3.ZERO
var last_sync_rotation: Vector3 = Vector3.ZERO
var sync_interpolation_speed: float = 10.0

func _ready():
	# Find the RocketController child node
	rocket_controller = get_node_or_null("RocketController")
	if rocket_controller:
		# Connect controller signals
		rocket_controller.control_ended.connect(_on_rocket_control_ended)
	
	# Setup network authority
	setup_network_authority()

func _process(delta):
	# Handle network physics synchronization for non-authority clients
	if not is_network_authority and NetworkManager.is_multiplayer_active():
		handle_network_interpolation(delta)
	
	# Only authority client checks bounds to avoid duplicate signals
	if is_network_authority or not NetworkManager.is_multiplayer_active():
		# Check bounds every 10 frames to improve performance
		if Engine.get_process_frames() % 10 == 0:
			if is_out_of_bounds():
				rocket_out_of_bounds.emit()

func _on_body_entered(body):
	# Only process collisions on the authority client to prevent duplicate explosions
	if not is_network_authority and NetworkManager.is_multiplayer_active():
		return
	
	# Get the current position before we queue_free
	var collision_position = global_position
	
	# Sync explosion across all clients
	if NetworkManager.is_multiplayer_active():
		# Authority client triggers explosion on all clients
		# Use call_deferred to avoid timing issues
		call_deferred("_trigger_explosion_safely", collision_position)
	else:
		# Single player - trigger directly
		process_explosion(collision_position)

func fire_thruster ():
	$RocketThruster/RocketTrigger.play("Rocket Thrust")
	var launch_force = -global_transform.basis.x * 2500
	apply_central_force(launch_force)
	_set_up_collision_detection()

func _set_up_collision_detection ():
	body_entered.connect(_on_body_entered)
	contact_monitor = true
	max_contacts_reported = 4

func _apply_explosive_force (collision_position):
	# Apply explosion force
	var explosion_radius = 6.5  # Adjust radius as needed
	var explosion_force = 750.0  # Adjust force as needed
	
	if GameSettings.debug_mode_on:
		_create_debug_sphere(collision_position, explosion_radius)
	
	# Get all bodies in explosion radius
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = explosion_radius
	query.shape = sphere_shape
	query.transform = Transform3D(Basis(), collision_position)

	var results = space_state.intersect_shape(query)

	# Apply impulse to each physics body
	for result in results:
		var hit_body = result["collider"]
		if hit_body is VehicleBody3D:
			hit_body.die()
		if hit_body is RigidBody3D and hit_body != self:  # Skip the rocket itself
			var direction = (hit_body.global_position - collision_position).normalized()
			var distance = hit_body.global_position.distance_to(collision_position)
			var force = direction * explosion_force * (1.0 - distance / explosion_radius)
			hit_body.apply_central_impulse(force)
		
func _create_debug_sphere (position: Vector3, radius: float, duration: float = 1.0):
	# Visualize explosion radius
	var debug_mesh = SphereMesh.new()
	debug_mesh.radius = radius
	debug_mesh.height = radius * 2
	var debug_node = MeshInstance3D.new()
	debug_node.mesh = debug_mesh
	debug_node.position = position
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0, 0, 0.3)  # Semi-transparent red
	debug_mesh.surface_set_material(0, material)
	get_tree().root.add_child(debug_node)
	
	# Remove the debug visualization after the specified duration
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func(): debug_node.queue_free())

func is_out_of_bounds():
	# maybe this should be read from the map?
	#const MIN_Z = -550
	#const MAX_Z = 250
	#const MIN_X = -200
	#const MAX_X = 200
	#const MIN_Y = -150
	#const MAX_Y = 150
	const MIN_Z = -550
	const MAX_Z = 350
	const MIN_X = -300
	const MAX_X = 500
	const MIN_Y = -300
	const MAX_Y = 200

	return (
		global_position.z < MIN_Z or global_position.z > MAX_Z or
		global_position.x < MIN_X or global_position.x > MAX_X or
		global_position.y < MIN_Y or global_position.y > MAX_Y
	)

func _on_rocket_control_ended(controller: Node):
	pass

func assign_player_control(player: Node, enable_roll_leveling: bool = false):
	if rocket_controller:
		rocket_controller.assign_player_control(player, enable_roll_leveling)

func is_under_player_control() -> bool:
	return rocket_controller != null and rocket_controller.is_active

func setup_network_authority():
	# Determine if this client has authority over this rocket
	if NetworkManager.is_multiplayer_active():
		is_network_authority = is_multiplayer_authority()
		if not is_network_authority:
			# Non-authority clients don't simulate physics
			freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			freeze = true
			gravity_scale = 0.0
	else:
		# Single player mode - this client has authority
		is_network_authority = true

func handle_network_interpolation(delta: float):
	# Smoothly interpolate to the synchronized position and rotation from authority client
	if last_sync_position != Vector3.ZERO:
		global_position = global_position.lerp(last_sync_position, sync_interpolation_speed * delta)
	
	if last_sync_rotation != Vector3.ZERO:
		rotation = rotation.lerp(last_sync_rotation, sync_interpolation_speed * delta)

# Called by MultiplayerSynchronizer when position is updated from authority
func _on_position_changed(new_position: Vector3):
	if not is_network_authority:
		last_sync_position = new_position

# Called by MultiplayerSynchronizer when rotation is updated from authority  
func _on_rotation_changed(new_rotation: Vector3):
	if not is_network_authority:
		last_sync_rotation = new_rotation

# Called by MultiplayerSynchronizer when synchronized
func _on_network_synchronized():
	pass
	#print("Rocket network synchronized, authority: ", is_network_authority)

# Safe explosion triggering with error handling
func _trigger_explosion_safely(explosion_position: Vector3):
	if is_inside_tree() and not is_queued_for_deletion():
		trigger_networked_explosion.rpc(explosion_position)

func _trigger_explosion_locally(explosion_position: Vector3):
	if is_inside_tree() and not is_queued_for_deletion():
		process_explosion(explosion_position)

# RPC function to synchronize explosions across all clients
@rpc("any_peer", "call_local", "reliable")
func trigger_networked_explosion(explosion_position: Vector3):
	# Safety check to prevent crashes
	if is_inside_tree() and not is_queued_for_deletion():
		process_explosion(explosion_position)


func process_explosion(collision_position: Vector3):
	# Instance the explosion particle effect prefab
	var explosion_scene = preload("res://scenes/ExplosionPrefab.tscn")
	var explosion_particle_effect = explosion_scene.instantiate()
	get_tree().root.add_child(explosion_particle_effect)
	explosion_particle_effect.global_position = collision_position
	explosion_particle_effect.get_node("Explosion/AnimationPlayer").play("PlayExplosion")
	
	# Apply explosive force on ALL clients
	# Both player deaths and physics forces should happen everywhere for consistent gameplay
	_apply_explosive_force(collision_position)
	
	# Notify controller about destruction
	if rocket_controller:
		rocket_controller._on_rocket_destroyed()
	
	# Emit signal to parent before destroying the rocket
	rocket_exploded.emit(collision_position)
	
	# Apply secondary explosive force to affect debris (only on authority)
	if is_network_authority or not NetworkManager.is_multiplayer_active():
		await get_tree().create_timer(0.01).timeout
		_apply_explosive_force(collision_position)
	
	# Remove the rocket
	queue_free()
