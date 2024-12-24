extends VehicleBody3D

const STEER_SPEED = 1.5
const STEER_LIMIT = 0.4
const BRAKE_STRENGTH = 2.0

var previous_speed := linear_velocity.length()
var _steer_target := 0.0
var _closest_gravity_point: Vector3
var _initial_gravity_point: Vector3
var debug_gravitational_direction: bool = true

@onready var desired_engine_pitch: float = $EngineSound.pitch_scale

@export var player_number : int
@export var player_colour : StandardMaterial3D
@export var engine_force_value := 40.0
@export var move_speed := 80.0
## Strength of the impulse applied upwards for the player's jump.
@export var jump_initial_impulse := 20.0
## How fast the player can turn around to match a new direction.
@export var rotation_speed := 8.0
@export var spawn_point : Vector3

var _move_direction := Vector3.ZERO
var _last_strong_direction := Vector3.FORWARD
var local_gravity := Vector3.DOWN
var _should_reset := false

var is_boost_sound_playing := false
var boost_timer := 0.0
var can_boost := true
const MAX_BOOST_DURATION := 0.5

var _orientation_in_progress := false
var _orientation_duration := 0.0
const MAX_ORIENTATION_TIME := 1.0  # Maximum time to attempt orientation

var _handling_inversion := false
var _inversion_attempt_timer := 0.0
const MAX_INVERSION_RETRY_TIME := 1.0

var is_dead := false
var death_camera: Camera3D
const RESPAWN_TIME := 3.0
const SEPARATION_FORCE := 6.0
var was_active_player := false  # Add this as a class variable
var death_collision_shapes := {}  # Dictionary to store shapes for each part

@onready var _start_position := global_transform.origin
@onready var rocket_launcher = $RocketLauncher
@onready var original_parts: Array[Node3D] = [$Body, $Wheel1, $Wheel2, $Wheel3, $Wheel4, $RocketLauncher]

func _ready ():
	connect("body_entered", Callable(self, "_on_body_entered"))

	if player_colour != null and $Body.get_node_or_null("MeshInstance3D") is MeshInstance3D:
		$Body.get_node("MeshInstance3D").set_surface_override_material(0, player_colour)

	genenerate_collision_shapes_for_desctructible_parts()

func genenerate_collision_shapes_for_desctructible_parts ():
	for part in original_parts:
		if part and part.get_node_or_null("MeshInstance3D") is MeshInstance3D:
			var mesh_instance = part.get_node("MeshInstance3D")
			var mesh = mesh_instance.mesh
			if mesh:
				var collision_shape = CollisionShape3D.new()
				
				# Create simplified convex shapes for all parts
				# Parameters: (clean=true, simplify=true)
				collision_shape.shape = mesh.create_convex_shape(true, true)
				
				# Combine the part and mesh instance transforms
				collision_shape.transform = part.transform * mesh_instance.transform
				# Disable the collision shape until death
				collision_shape.disabled = true
				
				death_collision_shapes[part.name] = collision_shape

func update_new_center_of_gravity_point (point):
	# If this is the first gravity point we've received, store it as initial
	if _closest_gravity_point == Vector3.ZERO:
		_initial_gravity_point = point
	_closest_gravity_point = point

func switch_on_orientation ():
	_orientation_in_progress = true
	_orientation_duration = 0.0

func _orient_buggy_to_direction (delta: float) -> bool:
	var desired_up = (global_transform.origin - _closest_gravity_point).normalized()
	var current_up = global_transform.basis.y
	
	var alignment = current_up.dot(desired_up)
	# alignment will be:
	#  1 when perfectly aligned
	#  0 when perpendicular
	# -1 when completely inverted	

	if alignment > 0.99:  # Almost aligned
		_handling_inversion = false
		_inversion_attempt_timer = 0.0
		return true

	if alignment < -0.99:  # Almost completely inverted
		if _handling_inversion:
			_inversion_attempt_timer += delta
			if _inversion_attempt_timer >= MAX_INVERSION_RETRY_TIME:
				_handling_inversion = false
		elif not _handling_inversion:
			_handling_inversion = true
			var right = global_transform.basis.x
			global_transform = global_transform * Transform3D().rotated(right, PI/2)
		return false

	var rotation_axis = current_up.cross(desired_up).normalized()
	var rotation_angle = current_up.angle_to(desired_up)
	var smoothing_speed = 5.0 * delta
	var smoothed_angle = rotation_angle * smoothing_speed
	
	var rotation = Transform3D().rotated(rotation_axis, smoothed_angle)
	global_transform = global_transform * rotation
	
	return false

func _integrate_forces(state: PhysicsDirectBodyState3D):
	# This clause handles if a player falls off a planet, resetting their position if they hit the safety net.
	if _should_reset:
		state.transform.origin = _start_position
		_should_reset = false

	local_gravity = state.total_gravity.normalized()
	# get the diretion/distance as a vector3 from the buggy to the central point
	#var direction_to_central_point = central_point_marker.transform.origin - global_transform.origin
	# report any bodies the buggy is colliding with

func _on_body_entered(body):
	can_boost = true
	update_new_center_of_gravity_point(body.global_position)

func _physics_process(delta: float):
	if is_dead: # maybe this should only block controller inputs and allow other things to continue?
		return
	if global_position.y <= -100:
		die()
		$ImpactSound.play()
		return
		# need some extra code to remove death parts

	if (debug_gravitational_direction == true):
		DebugDraw.draw_line(global_transform.origin, _closest_gravity_point, Color.GREEN)

	if Input.is_action_just_pressed(str("p", player_number, "_reset_to_start_pos")):
		self.position = spawn_point
		self.rotation = Vector3(0, 0, 0)
		linear_velocity = Vector3(0, 0, 0)
		update_new_center_of_gravity_point(_initial_gravity_point)

	if Input.is_action_just_pressed(str("p", player_number, "_flip")):
		var desired_up = (global_transform.origin - _closest_gravity_point).normalized()
		global_transform.origin += desired_up * 1
		switch_on_orientation()

	if _orientation_in_progress:
		_tick_orientation_timer(delta)
		_orient_buggy_to_direction(delta)

	if Input.is_action_just_pressed(str("p", player_number, "_toggle_camera")):
		if $Camera1.current:
			$Camera2.current = true
		elif $Camera2.current:
			$Camera3.current = true
		else:
			$Camera1.current = true

	if Input.is_action_pressed(str("p", player_number, "_boost_jump")) and can_boost:
		if boost_timer < MAX_BOOST_DURATION:
			var up_direction = global_transform.basis.y
			apply_central_impulse(up_direction * jump_initial_impulse)
			$Beam/BeamTrigger.play("Beam Start")
			$Beam2/BeamTrigger.play("Beam Start")
			if not is_boost_sound_playing:
				$BoostSound.play()
				is_boost_sound_playing = true
			
			boost_timer += delta
		elif boost_timer >= MAX_BOOST_DURATION:
			stop_boost()
	elif Input.is_action_just_released(str("p", player_number, "_boost_jump")):
		stop_boost()

	var fwd_mps := (linear_velocity * transform.basis).x

	_steer_target = Input.get_axis(str("p", player_number, "_turn_right"), str("p", player_number, "_turn_left"))
	_steer_target *= STEER_LIMIT

	# Engine sound simulation (not realistic, as this car script has no notion of gear or engine RPM).
	desired_engine_pitch = 0.5 + linear_velocity.length() / (engine_force_value * 0.5)
	# Change pitch smoothly to avoid abrupt change on collision.
	$EngineSound.pitch_scale = lerpf($EngineSound.pitch_scale, desired_engine_pitch, 0.2)

	if abs(linear_velocity.length() - previous_speed) > 1.0:
		# Sudden velocity change, likely due to a collision. Play an impact sound to give audible feedback,
		# and vibrate for haptic feedback.
		$ImpactSound.play()
		Input.vibrate_handheld(100)
		for joypad in Input.get_connected_joypads():
			Input.start_joy_vibration(joypad, 0.0, 0.5, 0.1)

	# Automatically accelerate when using touch controls (reversing overrides acceleration).
	if DisplayServer.is_touchscreen_available() or Input.is_action_pressed(str("p", player_number, "_accelerate")):
		# Increase engine force at low speeds to make the initial acceleration faster.
		var speed := linear_velocity.length()
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = clampf(engine_force_value * 5.0 / speed, 0.0, 100.0)
		else:
			engine_force = engine_force_value

		if not DisplayServer.is_touchscreen_available():
			# Apply analog throttle factor for more subtle acceleration if not fully holding down the trigger.
			engine_force *= Input.get_action_strength(str("p", player_number, "_accelerate"))
	else:
		engine_force = 0.0

	if Input.is_action_pressed(str("p", player_number, "_reverse")):
		# Increase engine force at low speeds to make the initial reversing faster.
		var speed := linear_velocity.length()
		if speed < 5.0 and not is_zero_approx(speed):
			engine_force = -clampf(engine_force_value * BRAKE_STRENGTH * 5.0 / speed, 0.0, 100.0)
		else:
			engine_force = -engine_force_value * BRAKE_STRENGTH

		# Apply analog brake factor for more subtle braking if not fully holding down the trigger.
		engine_force *= Input.get_action_strength(str("p", player_number, "_reverse"))

	steering = move_toward(steering, _steer_target, STEER_SPEED * delta)

	previous_speed = linear_velocity.length()

	if Input.is_action_just_pressed(str("p", player_number, "_fire")):
		rocket_launcher.fire_rocket()

func _tick_orientation_timer (delta: float):
	_orientation_duration += delta
	if _orientation_duration >= MAX_ORIENTATION_TIME:
		_orientation_in_progress = false
		_orientation_duration = 0.0

func stop_boost ():
	if is_boost_sound_playing:
		$BoostSound.stop()
		is_boost_sound_playing = false
	boost_timer = 0.0
	can_boost = false

func die():
	if is_dead: return
	is_dead = true
	
	# Store death position and velocity before disabling physics
	var death_position = global_position
	var death_velocity = linear_velocity  # Capture the vehicle's velocity
	
	#collision_layer = 0
	#collision_mask = 0 
	set_physics_process(false)
	set_process_input(false)
	
	# Camera handling...
	# Store if this was the active player
	was_active_player = ($Camera1.current or $Camera2.current or $Camera3.current)
	
	# Only create death camera if this is the active player
	if was_active_player:
		death_camera = Camera3D.new()
		get_tree().root.add_child(death_camera)
		death_camera.global_transform = $Camera1.global_transform
		death_camera.current = true

	for original_part in original_parts:
		generate_and_separate_clone_of_part (original_part, death_velocity, death_position)

	# Start respawn timer
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)

func generate_and_separate_clone_of_part (og_part, death_velocity, death_position):
		og_part.visible = false
		var original_global_transform = og_part.global_transform

		var duplicate_part_rgdbdy = RigidBody3D.new()
		duplicate_part_rgdbdy.mass = 5.0
		duplicate_part_rgdbdy.gravity_scale = 1.0
		duplicate_part_rgdbdy.continuous_cd = true
		duplicate_part_rgdbdy.max_contacts_reported = 4
		duplicate_part_rgdbdy.contact_monitor = true
		duplicate_part_rgdbdy.can_sleep = false # TODO: review whether this is needed later
		# Make sure collision is enabled BEFORE adding the shape
		duplicate_part_rgdbdy.collision_layer = 1
		duplicate_part_rgdbdy.collision_mask = 1

		get_tree().root.add_child(duplicate_part_rgdbdy)

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
	
	# Show original parts
	for part in original_parts:
		if part:
			part.visible = true
	
	# Re-enable physics and collision
	collision_layer = 1  # Set to original layer
	collision_mask = 1   # Set to original mask
	set_physics_process(true)
	set_process_input(true)
	
	# Switch camera back
	if death_camera and was_active_player:
		death_camera.queue_free()
		$Camera1.current = true

	was_active_player = false
	is_dead = false

func _input(event):
	if is_dead:
		return
	# Normal input processing here
