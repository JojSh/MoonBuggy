extends RigidBody3D

# Called when the node enters the scene tree for the first time.
func _ready():
	#body_entered.connect(_on_body_entered)
	#contact_monitor = true
	#max_contacts_reported = 4
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _on_body_entered(body):
	# Get the current position before we queue_free
	var collision_position = global_position
	
	# Instance the explosion particle effect prefab
	var explosion_scene = preload("res://ExplosionPrefab.tscn")
	var explosion_particle_effect = explosion_scene.instantiate()
	get_tree().root.add_child(explosion_particle_effect)
	explosion_particle_effect.global_position = collision_position
	explosion_particle_effect.get_node("Explosion/AnimationPlayer").play("PlayExplosion")

	_apply_explosive_force(collision_position)
	# Remove the rocket
	queue_free()

func fire_thruster ():
	$RocketThruster/RocketTrigger.play("Rocket Thrust")

	var timer = get_tree().create_timer(0.25)
	await timer.timeout

	var launch_force = -global_transform.basis.x * 2500
	apply_central_force(launch_force)

	_set_up_collision_detection()

func _set_up_collision_detection ():
	body_entered.connect(_on_body_entered)
	contact_monitor = true
	max_contacts_reported = 4

func _apply_explosive_force (collision_position):
		# Apply explosion force
	var explosion_radius = 7.5  # Adjust radius as needed
	var explosion_force = 500.0  # Adjust force as needed
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
		if hit_body is RigidBody3D and hit_body != self:  # Skip the rocket itself
			var direction = (hit_body.global_position - collision_position).normalized()
			var distance = hit_body.global_position.distance_to(collision_position)
			var force = direction * explosion_force * (1.0 - distance / explosion_radius)
			hit_body.apply_central_impulse(force)
	
	
