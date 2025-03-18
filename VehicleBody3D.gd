extends VehicleBody3D

const STEER_SPEED = 2.5
const STEER_LIMIT = 0.4
const BRAKE_STRENGTH = 2.0
const STARTING_BOOST_LEVEL := 1.0 # each boost level = +0.5s extra boost duration
const STARTING_RELOAD_LEVEL := 1
const MAX_UPSIDE_DOWN_TIME := 3.0
const RESPAWN_TIME := 3.0
const SEPARATION_FORCE := 6.0

var previous_speed := linear_velocity.length()
var _steer_target := 0.0
var _closest_gravity_point: Vector3
var _initial_gravity_point: Vector3
var local_gravity := Vector3.DOWN
var _should_reset := false
var is_boost_sound_playing := false
var boost_timer := 0.0
var can_boost := true
var time_upside_down := 0.0
var is_dead := false
var death_camera: Camera3D
var was_active_player := false  # Add this as a class variable
var death_collision_shapes := {}  # Dictionary to store shapes for each part
var inputs_paused := false
var is_invincible := false

@export var player_number : int
@export var current_lives : int
@export var player_colour : StandardMaterial3D
@export var engine_force_value := 40.0
@export var jump_initial_impulse := 20.0
@export var spawn_point : Vector3
@export var is_eliminated := false  # Add this near other @export variables

@onready var _start_position := global_transform.origin
@onready var rocket_launcher = $RocketLauncher
@onready var original_parts: Array[Node3D] = [$Body, $Wheel1, $Wheel2, $Wheel3, $Wheel4, $RocketLauncher]
@onready var debris_manager = get_node("/root/DebrisManager")
@onready var current_boost_level := STARTING_BOOST_LEVEL
@onready var current_reload_level := STARTING_RELOAD_LEVEL
@onready var desired_engine_pitch: float = $EngineSound.pitch_scale

signal player_eliminated(player_number)

func _ready ():
	connect("body_entered", Callable(self, "_on_body_entered"))
	set_player_colour_from_exported_variable()
	genenerate_collision_shapes_for_desctructible_parts()
	_update_lives_display()
	_update_boost_display()

func _physics_process(delta: float):
	if is_dead: return

	if inputs_paused:
		stop_boost()
		return

	if global_position.y <= -100: # fallen off level
		die()
		$ImpactSound.play()
		return
		# need some extra code to remove death parts ?

	if (GameSettings.debug_mode_on):
		DebugDraw.draw_line(global_transform.origin, _closest_gravity_point, Color.GREEN)

	if Input.is_action_just_pressed(str("p", player_number, "_flip")):
		reorient_vehicle()

	handle_cycle_through_cameras_input()
	handle_return_to_start_position_input()

	handle_boost_input(delta)
	handle_steering_input(delta)
	handle_acceleration_input()
	handle_reverse_input()
	handle_fire_input()

	handle_engine_sound()
	handle_sudden_impact_feedback()

	auto_reorient_vehicle_if_upside_down_too_long(delta)

func set_player_colour_from_exported_variable ():
	if player_colour != null and $Body.get_node_or_null("MeshInstance3D") is MeshInstance3D:
		$Body.get_node("MeshInstance3D").set_surface_override_material(0, player_colour)

func genenerate_collision_shapes_for_desctructible_parts ():
	for part in original_parts:
		var mesh_instance = part.get_node("MeshInstance3D")
		var mesh = mesh_instance.mesh
		var collision_shape = CollisionShape3D.new()

		# Create simplified convex shapes for all parts
		# Parameters: (clean=true, simplify=true)
		collision_shape.shape = mesh.create_convex_shape(true, true)
		
		# Combine the part and mesh instance transforms
		collision_shape.transform = part.transform * mesh_instance.transform
		# Disable the collision shape until death
		collision_shape.disabled = true
		death_collision_shapes[part.name] = collision_shape

func update_new_center_of_gravity_point(point):
	if _closest_gravity_point == Vector3.ZERO:
		_initial_gravity_point = point
	_closest_gravity_point = point

func reorient_vehicle():
	# 1. Calculate the desired up direction (opposite to gravity)
	var desired_up: Vector3

	# Check if we're on a flat surface (box collider gravity area)
	var to_gravity_point = global_transform.origin - _closest_gravity_point
	var roughly_on_horizontal_plane = abs(to_gravity_point.y) < 1.0

	if roughly_on_horizontal_plane:
		desired_up = Vector3.UP
	else:
		desired_up = to_gravity_point.normalized() # Use direction away from gravity point for spherical surfaces

	# 2. Calculate the desired forward direction
	# Use the current forward direction projected onto the plane perpendicular to desired_up
	var current_forward = -global_transform.basis.z
	var right = current_forward.cross(desired_up).normalized()
	var new_forward = desired_up.cross(right).normalized()
	
	# 3. Construct the new basis
	var new_basis = Basis()
	new_basis.x = right
	new_basis.y = desired_up
	new_basis.z = -new_forward  # Negative because Godot uses -Z as forward
	
	# 4. Apply the new orientation
	global_transform.basis = new_basis
	
	# 5. Zero out angular velocity to prevent rolling
	angular_velocity = Vector3.ZERO
	#linear_velocity = Vector3.ZERO # prevents the car from sliding but I think I like the slide after re orient
	
	# 6. Lift the vehicle slightly to prevent immediate collision
	global_transform.origin += desired_up * 0.5

func _integrate_forces(state: PhysicsDirectBodyState3D):
	if _should_reset:
		state.transform.origin = _start_position
		_should_reset = false

	local_gravity = state.total_gravity.normalized()

func _on_body_entered(body):
	if (body.name.begins_with("Level")):
		can_boost = true
		update_new_center_of_gravity_point(body.global_position)

func start_boost ():
	var up_direction = global_transform.basis.y
	apply_central_impulse(up_direction * jump_initial_impulse)
	$Beams.visible = true
	$Beams/Beam/BeamTrigger.play("Beam Start")
	$Beams/Beam2/BeamTrigger.play("Beam Start")

	if not is_boost_sound_playing:
		$BoostSound.play()
		is_boost_sound_playing = true

func stop_boost ():
	if is_boost_sound_playing:
		$BoostSound.stop()
		# Try to force the animation to its end
		$Beams/Beam/BeamTrigger.play("RESET")
		$Beams/Beam2/BeamTrigger.play("RESET")
		$Beams.visible = false
		
		is_boost_sound_playing = false
	boost_timer = 0.0
	can_boost = false

func die ():
	if is_invincible: return
	if is_dead: return
	is_dead = true
	
	# Store death position and velocity before disabling physics
	var death_position = global_position
	var death_velocity = linear_velocity  # Capture the vehicle's velocity
	
	#collision_layer = 0
	#collision_mask = 0 
	set_physics_process(false)
	set_process_input(false)
	
	$EngineSound.stop()
	#cant remember why we wanted this?: maybe for single-player?
	## Camera handling...
	## Store if this was the active player
	#was_active_player = ($Camera1.current or $Camera2.current or $Camera3.current)
	#
	## Only create death camera if this is the active player
	#if was_active_player:
		#death_camera = Camera3D.new()
		#get_tree().root.add_child(death_camera)
		#death_camera.global_transform = $Camera1.global_transform
		#death_camera.current = true

	for original_part in original_parts:
		generate_and_separate_clone_of_part(original_part, death_velocity, death_position)

	current_lives -= 1
	if (current_lives == 0):
		is_eliminated = true
		emit_signal("player_eliminated", player_number)
		return

	# Start respawn timer
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)

func handle_return_to_start_position_input ():
	if Input.is_action_just_pressed(str("p", player_number, "_reset_to_start_pos")):
		self.position = spawn_point
		self.rotation = Vector3(0, 0, 0)
		linear_velocity = Vector3(0, 0, 0)
		update_new_center_of_gravity_point(_initial_gravity_point)

func handle_cycle_through_cameras_input ():
	if Input.is_action_just_pressed(str("p", player_number, "_toggle_camera")):
		if $Camera1.current:
			$Camera2.current = true
		elif $Camera2.current:
			$Camera3.current = true
		else:
			$Camera1.current = true

func handle_boost_input (delta):
	if Input.is_action_pressed(str("p", player_number, "_boost_jump")) and can_boost:
		var current_max_boost_duration = current_boost_level / 2 # each 1 level = 0.5s extra boost duration

		if boost_timer < current_max_boost_duration:
			start_boost()
			boost_timer += delta
		elif boost_timer >= current_max_boost_duration:
			stop_boost()
	elif Input.is_action_just_released(str("p", player_number, "_boost_jump")):
		stop_boost()

func handle_steering_input (delta):
	_steer_target = Input.get_axis(str("p", player_number, "_turn_right"), str("p", player_number, "_turn_left"))
	_steer_target *= STEER_LIMIT
	steering = move_toward(steering, _steer_target, STEER_SPEED * delta)

func handle_engine_sound ():
	# Engine sound simulation (not realistic, as this car script has no notion of gear or engine RPM).
	desired_engine_pitch = 0.5 + linear_velocity.length() / (engine_force_value * 0.5)
	# Change pitch smoothly to avoid abrupt change on collision.
	$EngineSound.pitch_scale = lerpf($EngineSound.pitch_scale, desired_engine_pitch, 0.2)

func handle_sudden_impact_feedback ():
	if abs(linear_velocity.length() - previous_speed) > 1.0:
		# Sudden velocity change, likely due to a collision. Play an impact sound to give audible feedback,
		# and vibrate for haptic feedback.
		$ImpactSound.play()
		Input.vibrate_handheld(100)
		for joypad in Input.get_connected_joypads():
			Input.start_joy_vibration(joypad, 0.0, 0.5, 0.1)
	
	# Store current speed for next frame's impact detection
	previous_speed = linear_velocity.length()

func handle_acceleration_input ():
	if Input.is_action_pressed(str("p", player_number, "_accelerate")):
		var speed := linear_velocity.length()
		# Special handling for low speeds to help overcome initial inertia
		if speed < 5.0 and not is_zero_approx(speed):
			# At low speeds, apply extra force (inverse to speed)
			# Example: at speed 1.0 -> force = 40 * 5 / 1 = 200, clamped to 100
			# Example: at speed 4.0 -> force = 40 * 5 / 4 = 50
			engine_force = clampf(engine_force_value * 5.0 / speed, 0.0, 100.0) # 0.0 is the min, 100.0 is the max
		else:
			# At non-low speeds, use regular engine force (40.0)
			engine_force = engine_force_value
	else:
		engine_force = 0.0

func handle_reverse_input ():
	if Input.is_action_pressed(str("p", player_number, "_reverse")):
		var speed := linear_velocity.length()
		# Special handling for low speeds (see handle_acceleration_input comments for more details)
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = -clampf(engine_force_value * BRAKE_STRENGTH * 5.0 / speed, 0.0, 100.0) # 0.0 is the min, 100.0 is the max
		else:
			engine_force = -engine_force_value * BRAKE_STRENGTH
			# Apply analog brake factor for more subtle braking if not fully holding down the trigger.
			engine_force *= Input.get_action_strength(str("p", player_number, "_reverse"))

func handle_fire_input ():
	if Input.is_action_just_pressed(str("p", player_number, "_fire")):
		rocket_launcher.fire_rocket()

func auto_reorient_vehicle_if_upside_down_too_long (delta):
	var up = global_transform.basis.y
	var desired_up = (global_transform.origin - _closest_gravity_point).normalized()
	if up.dot(desired_up) < -0.5:  # More than 120 degrees from desired up
		time_upside_down += delta
		if time_upside_down > MAX_UPSIDE_DOWN_TIME:
			reorient_vehicle()
			time_upside_down = 0.0
	else:
		time_upside_down = 0.0

func generate_and_separate_clone_of_part (og_part, death_velocity, death_position):
	og_part.visible = false
	var original_global_transform = og_part.global_transform
	const DuplicatePartRigidBody3D = preload("res://DuplicatePartRigidBody3D.tscn")
	var duplicate_part_rgdbdy = DuplicatePartRigidBody3D.instantiate()

	# Instead of adding to root, add to debris manager
	debris_manager.add_debris(duplicate_part_rgdbdy)

	var duplicate_part_node3d = og_part.duplicate()

	duplicate_part_node3d.visible = true
	duplicate_part_rgdbdy.add_child(duplicate_part_node3d)

	# Add collision shape with explicit checks
	if death_collision_shapes.has(og_part.name):
		var collision_shape = death_collision_shapes[og_part.name].duplicate()
		collision_shape.disabled = false
		# Preserve the transform when adding to rigid body
		var shape_transform = collision_shape.transform
		duplicate_part_rgdbdy.add_child(collision_shape)
		# In case reparenting to the duplicate_part_rgdbdy changes its transform to something we don't want
		collision_shape.transform = shape_transform

	duplicate_part_rgdbdy.global_transform = original_global_transform

	# Set the initial velocity of the part to match the vehicle's velocity
	duplicate_part_rgdbdy.linear_velocity = death_velocity

	# Add separation force on top of existing velocity
	var direction = (duplicate_part_rgdbdy.global_position - death_position).normalized()
	direction += Vector3(randf_range(-0.2, 0.2), 1.0, randf_range(-0.2, 0.2))  # More upward bias
	direction = direction.normalized()
	duplicate_part_rgdbdy.apply_impulse(direction * SEPARATION_FORCE)

func _respawn():
	# Reset position and rotation
	global_position = spawn_point
	rotation = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	current_boost_level = STARTING_BOOST_LEVEL

	_update_lives_display()
	_update_boost_display()
	
	# Show original parts
	for part in original_parts:
		if part:
			part.visible = true
	
	# Re-enable physics and collision
	collision_layer = 1  # Set to original layer
	collision_mask = 1   # Set to original mask
	set_physics_process(true)
	set_process_input(true)
	
	$EngineSound.play()
	
	# Switch camera back
	if death_camera and was_active_player:
		death_camera.queue_free()
		$Camera1.current = true

	was_active_player = false
	is_dead = false

func _input(event):
	if is_dead or inputs_paused:
		return
	# Normal input processing here

func _update_lives_display ():
	var lives_container = $Body/Lives
	var life_wheels = lives_container.get_children()

	for i in life_wheels.size():
		var currentNum  = i + 1
		var life_wheel = life_wheels[i]
		if life_wheel:
			life_wheel.visible = currentNum <= current_lives

func _update_boost_display ():
	var boost_display_container = $Body/BoostDisplay
	var boost_bulbs = boost_display_container.get_children()

	for i in boost_bulbs.size():
		var currentNum  = i + 1
		var boost_bulb = boost_bulbs[i]
		if boost_bulb:
			boost_bulb.visible = currentNum <= current_boost_level

func increment_boost_level ():
	var boost_limit = 6
	if current_boost_level < boost_limit:
		$PickupSound.play()
		current_boost_level += 1
		_update_boost_display()

func increment_lives ():
	var life_limit = 5
	if current_lives < life_limit:
		$PickupSound.play()
		current_lives += 1
		_update_lives_display()

func reduce_rocket_reload_speed ():
	var reload_level_limit = 5
	if current_reload_level < reload_level_limit:
		$PickupSound.play()
		current_reload_level += 1
		$RocketLauncher.reduce_cooldown_time(current_reload_level)

func pause_inputs ():
	inputs_paused = true
	engine_force = 0.0  # Stop the vehicle
	steering = 0.0
	# Freeze all movement
	freeze = true  # This is a built-in property of PhysicsBody3D that completely stops physics simulation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func activate_rocket_diarrhea ():
	$PickupSound.play()
	$RocketLauncher.activate_diarrhea()
	is_invincible = true
	collision_layer = 0
	apply_invincibility_shader()
	# start special invincibility music?

	var diarrhea_timer = get_tree().create_timer(10)
	await diarrhea_timer.timeout

	$RocketLauncher.deactivate_diarrhea()
	$Body/MeshInstance3D.material_override = null # remove the shader
	collision_layer = 1
	
	var invincibility_buffer_timer = get_tree().create_timer(0.5)
	await invincibility_buffer_timer.timeout
	is_invincible = false

func apply_invincibility_shader ():
	var invincibility_shader = preload("res://invincibility_shader.tres")
	var shader_material = ShaderMaterial.new()
	# can we make the shader glow more?
	shader_material.shader = invincibility_shader
	$Body/MeshInstance3D.material_override = shader_material
