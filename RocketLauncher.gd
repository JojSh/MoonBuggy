extends Node3D
const RocketProjectile = preload("res://rocket_projectile.tscn")
var can_fire: bool = true

func fire_rocket():
	if !can_fire: return
	$MeshInstance3D.set_visible(false)
	var rocket_projectile = RocketProjectile.instantiate()
	get_parent().add_child(rocket_projectile)
	rocket_projectile.global_transform = $MeshInstance3D.global_transform
	
	# Get references to the inner container and its children
	var rocket_projectile_inner = rocket_projectile.get_node("RocketProjectileInner")
	var projectile_mesh = rocket_projectile_inner.get_node("RocketProjectileMesh")
	var collision_shape = rocket_projectile_inner.get_node("CollisionShape3D")
	
	rocket_projectile_inner.fire_thruster()
	
	# Create tween for scaling animation using current scales
	var mesh_initial_scale = projectile_mesh.scale
	var collision_initial_scale = collision_shape.scale
	var tween = create_tween()
	# Scale the mesh to 3x its current scale
	tween.tween_property(projectile_mesh, "scale", mesh_initial_scale * 3, 0.2)
	# Scale the collision shape to 3x its current scale
	tween.parallel().tween_property(collision_shape, "scale", collision_initial_scale * 2.5, 0.2)
	
	# Calculate launch force in the rocket's forward direction
	var launch_impulse = -rocket_projectile_inner.global_transform.basis.x * 100
	rocket_projectile_inner.apply_central_impulse(launch_impulse)
	
	can_fire = false
	var timer = get_tree().create_timer(2)
	await timer.timeout
	$MeshInstance3D.set_visible(true)
	can_fire = true
