extends Node3D
const RocketProjectile = preload("res://rocket_projectile.tscn")
var can_fire: bool = true
@export var launch_power := 300
const STARTING_COOLDOWN_TIME = 5.0
@onready var current_cooldown_time := STARTING_COOLDOWN_TIME
@onready var diarrhea_active := false
@onready var cooldown_time_before_diarrhea := STARTING_COOLDOWN_TIME
var rocket_count: int = 0  # Track rockets fired by this launcher

func fire_rocket():
	if !can_fire: return
	hide_rocket()
	var rocket_projectile = RocketProjectile.instantiate()
	get_tree().get_root().add_child(rocket_projectile)
	rocket_projectile.global_transform = $MeshInstance3D.global_transform
	
	# Register rocket with SpectatorManager for eliminated player control
	# In debug mode: register all rockets
	# In normal mode: only register every 3rd rocket
	rocket_count += 1
	var spectator_manager = get_node_or_null("/root/RootNode/SpectatorManager")
	if spectator_manager:
		var rocket_inner = rocket_projectile.get_node("RocketProjectileInner")
		var should_register = GameSettings.debug_mode_on or (rocket_count % 3 == 0)
		if should_register:
			spectator_manager.register_rocket(rocket_inner)
	
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
	var launch_impulse = -rocket_projectile_inner.global_transform.basis.x * launch_power
	rocket_projectile_inner.apply_central_impulse(launch_impulse)
	
	can_fire = false
	var timer = get_tree().create_timer(current_cooldown_time)
	await timer.timeout
	show_rocket()
	if diarrhea_active:
		can_fire = true  # Set can_fire to true before recursive call
		fire_rocket()
	else:
		can_fire = true

func reduce_cooldown_time (current_reload_level):
	show_rocket()
	if current_reload_level < 5:
		current_cooldown_time = STARTING_COOLDOWN_TIME - current_reload_level
	elif current_reload_level == 5:
		current_cooldown_time = (STARTING_COOLDOWN_TIME - current_reload_level) + 0.5
	else:
		return

func activate_diarrhea():
	diarrhea_active = true
	cooldown_time_before_diarrhea = current_cooldown_time
	current_cooldown_time = 0.2
	if can_fire:
		fire_rocket()

func deactivate_diarrhea():
	diarrhea_active = false
	current_cooldown_time = cooldown_time_before_diarrhea

func hide_rocket ():
	$MeshInstance3D.set_visible(false)

func show_rocket ():
	$MeshInstance3D.set_visible(true)
