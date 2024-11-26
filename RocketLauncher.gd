extends Node3D
const RocketProjectile = preload("res://rocket_projectile.tscn") 


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_just_pressed("p1_fire"): # move this up to player and trigger a signal down here
		#print("pressed fire")
		$RocketMesh.set_visible(false)
		var rocket_projectile = RocketProjectile.instantiate()
		get_parent().add_child(rocket_projectile)
		rocket_projectile.global_transform = $RocketMesh.global_transform
		# Get references to the child nodes
		var projectile_mesh = rocket_projectile.get_node("RocketProjectileMesh")
		var collision_shape = rocket_projectile.get_node("CollisionShape3D")
		
		#rocket_projectile.get_node("Beam/BeamTrigger").play("Beam Start")
		rocket_projectile.fire_thruster()
		
		# Create tween for scaling animation using current scales
		var mesh_initial_scale = projectile_mesh.scale
		var collision_initial_scale = collision_shape.scale
		var tween = create_tween()
		# Scale the mesh to 3x its current scale
		tween.tween_property(projectile_mesh, "scale", mesh_initial_scale * 3, 0.2)
		# Scale the collision shape to 3x its current scale
		tween.parallel().tween_property(collision_shape, "scale", collision_initial_scale * 2.5, 0.2)
		
		#rocket_projectile.global_position.y = rocket_projectile.global_position.y + 1
		# Calculate launch force in the rocket's forward direction
		var launch_impulse = -rocket_projectile.global_transform.basis.x * 100 # 000
		rocket_projectile.apply_central_impulse(launch_impulse)
