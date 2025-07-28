extends VehicleBody3D

const STEER_SPEED = 2.5
const STEER_LIMIT = 0.4
const BRAKE_STRENGTH = 2.0
const STARTING_BOOST_LEVEL : float = 0.0 # 1.5  # each boost level = +0.5s extra boost duration
const STARTING_RELOAD_LEVEL := 1
const MAX_UPSIDE_DOWN_TIME := 3.0
const RESPAWN_TIME := 3.0
const SEPARATION_FORCE := 6.0
const BOOST_COOLDOWN := 3.0  # Time in seconds before boost can be used again

var previous_speed := linear_velocity.length()
var _steer_target := 0.0
var _closest_gravity_point: Vector3
var _initial_gravity_point: Vector3
var _should_reset := false
var is_boost_sound_playing := false
var boost_timer := 0.0
var can_boost := true
var is_dead := false
var time_upside_down := 0.0
var death_camera: Camera3D
var death_collision_shapes := {}  # Dictionary to store shapes for each part
var inputs_paused := false
var is_invincible := false
var is_reorienting := false  # Track if we're currently in a gradual reorientation
var spawn_point : Vector3
var spawn_rotation : Vector3
var playing_obstacle_course_mode := false
var current_boost_level: float
var current_reload_level: int
var current_camera_index: int = 0

# Variables for gradual reorientation
const REORIENTATION_COOLDOWN_DURATION := 3.0  # 3.0 second cooldown
var reorientation_timer := 0.0
var reorientation_duration := 0.5
var reorientation_initial_basis: Basis
var reorientation_target_basis: Basis
var reorientation_initial_origin: Vector3
var reorientation_target_origin: Vector3
var reorientation_cooldown := 1.0  # Tracks the cooldown time remaining
var desired_up: Vector3

# Add timer for orientation checking
var orientation_check_timer := 0.0
const ORIENTATION_CHECK_INTERVAL := 1.0  # Check once per second

var gravity_validation_timer := 0.0
const GRAVITY_VALIDATION_INTERVAL := 10.0 # Validate every 10 seconds

# Vehicle orientation state (for camera and other systems to access)
var is_upside_down := false
var is_stuck_on_nose := false
var is_stuck_on_tail := false

# surface type variables
enum SurfaceType { OUTER, INNER, FLAT }
var current_surface_type: SurfaceType = SurfaceType.OUTER  # Default to OUTER instead of NONE
var is_on_corner_ramp := false  # Add this to track corner ramp contact

@export var player_number : int
@export var current_lives : int
@export var player_colour : StandardMaterial3D
@export var engine_force_value := 40.0
@export var jump_initial_impulse := 20.0
@export var is_eliminated := false  # Add this near other @export variables

var _start_position: Vector3
@onready var rocket_launcher = $RocketLauncher
@onready var original_parts: Array[Node3D] = [$Body, $Wheel1, $Wheel2, $Wheel3, $Wheel4, $RocketLauncher]
@onready var debris_manager = get_node("/root/DebrisManager")
@onready var desired_engine_pitch: float = $EngineSound.pitch_scale
@onready var targeting_laser = $TargetingLaser

signal player_eliminated(player_number)
signal player_lost_a_life(player_number)
signal hide_crosshair()
signal show_crosshair()

func _ready ():
	_start_position = global_transform.origin
	global_position = spawn_point

	# Reset camera pivot position to its intended relative position after moving to spawn
	# This prevents rubber banding from position mismatches in the scene file
	$ChaseCamPivot.position = Vector3.ZERO  # Reset position to be relative to vehicle center

	set_player_colour_from_exported_variable()
	genenerate_collision_shapes_for_desctructible_parts()
	
	_update_lives_display()
	_update_boost_display()

func _physics_process(delta: float):
	if is_dead: return

	if inputs_paused:
		stop_boost()
		return

	if global_position.y <= -300: # fallen off level
		die()
		$ImpactSound.play()
		return
		# need some extra code to remove death parts ?

	if reorientation_cooldown > 0:
		reorientation_cooldown -= delta

	validate_gravity_point_on_interval(delta)

	if (GameSettings.debug_mode_on):
		DebugDraw.draw_line(global_transform.origin, _closest_gravity_point, Color.GREEN)
		
		# Add debug visualization for the reorientation process
		if is_reorienting:
			draw_debug_reorientation()

	# Handle gradual reorientation in physics_process
	if is_reorienting:
		process_reorientation(delta)

	if Input.is_action_just_pressed(str("p", player_number, "_flip")):
		# Player explicitly requested a flip
		reorient_vehicle()

	if (player_number == 1): #temporary until assigned for players 2-4
		if Input.is_action_pressed(str("p", player_number, "_hold_to_aim")):
			if ($ChaseCamPivot/ChaseCam.current or $SideCam.current):
				targeting_laser.show_laser()
				update_targeting_laser()
			else:
				emit_signal("show_crosshair")
		elif Input.is_action_just_released(str("p", player_number, "_hold_to_aim")):
			if ($ChaseCamPivot/ChaseCam.current or $SideCam.current):
				targeting_laser.hide_laser()
			else:
				emit_signal("hide_crosshair")

	handle_cycle_through_cameras_input()
	handle_return_to_start_position_input()

	handle_boost_input(delta)
	handle_steering_input(delta)
	handle_acceleration_input()
	handle_reverse_input()
	handle_fire_input()
	
	if (player_number == 1 && Input.is_action_just_pressed("p1_debug_test_functionality_trigger")):
		print("testing debug input")

	handle_engine_sound()
	handle_sudden_impact_feedback()

	# Update camera with current state information
	if _closest_gravity_point != Vector3.ZERO:
		var orientation_data = calculate_orientation_data()

	auto_reorient_vehicle_if_stuck_too_long(delta)

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

# Update the orientation data calculation
func calculate_orientation_data() -> Dictionary:
	# Don't update camera if gravity point isn't properly initialized
	if _closest_gravity_point == Vector3.ZERO:
		return {
			"desired_up": Vector3.UP,  # Default safe value
			"is_flat_surface": true,
			"is_on_inner_surface": false,
			"gravity_dir": Vector3.UP
		}
	
	var to_gravity_point = global_transform.origin - _closest_gravity_point
	var gravity_dir = to_gravity_point.normalized()
	
	# Calculate desired up direction based on surface type
	match current_surface_type:
		SurfaceType.FLAT:
			desired_up = Vector3.UP
		SurfaceType.INNER:
			#desired_up = -gravity_dir
			pass
		SurfaceType.OUTER:
			desired_up = gravity_dir

	update_camera_state(desired_up)

	return {
		"desired_up": desired_up,
		"is_flat_surface": current_surface_type == SurfaceType.FLAT,
		"is_on_inner_surface": current_surface_type == SurfaceType.INNER,
		"gravity_dir": gravity_dir
	}

# Helper function to perform reorientation
func perform_reorientation(orientation_data: Dictionary, gradual: bool = false, duration: float = 0.5):
	if reorientation_cooldown > 0:
		return
		
	reorientation_cooldown = REORIENTATION_COOLDOWN_DURATION
	
	if gradual:
		start_reorientation(duration, orientation_data)
		calculate_target_transform(orientation_data)
	else:
		# Immediate reorientation
		var current_forward = -global_transform.basis.z
		var right = current_forward.cross(orientation_data.desired_up).normalized()
		var new_forward = orientation_data.desired_up.cross(right).normalized()
		
		var new_basis = Basis()
		new_basis.x = right
		new_basis.y = orientation_data.desired_up
		new_basis.z = -new_forward
		
		global_transform.basis = new_basis
		angular_velocity = Vector3.ZERO
		global_transform.origin += orientation_data.desired_up * 0.5

func reorient_vehicle(on_delay: bool = false):
	# Cancel any in-progress gradual reorientation
	is_reorienting = false
	
	# Don't start if we're in the cooldown period
	if reorientation_cooldown > 0:
		#print("Manual reorientation on cooldown: " + str(reorientation_cooldown) + "s remaining")
		return
	
	if on_delay:
		var reorient_timer = get_tree().create_timer(0.2)
		await reorient_timer.timeout
		
	var orientation_data = calculate_orientation_data()
	perform_reorientation(orientation_data, false)

func _integrate_forces(state: PhysicsDirectBodyState3D):
	if _should_reset:
		state.transform.origin = _start_position
		_should_reset = false

# Update the body entered function to read the surface type
func _on_body_entered(body):
	if (body.name.begins_with("Level")):
		can_boost = true
		update_new_center_of_gravity_point(body.global_position)

		# Find the gravity area child and read its surface_type property
		var gravity_area = body.get_node("GravityArea3D")
		if gravity_area:
			current_surface_type = gravity_area.surface_type
		else:
			# Default to outer surface if not found
			current_surface_type = SurfaceType.OUTER

func set_on_corner_ramp_true():
	is_on_corner_ramp = true

func set_on_corner_ramp_false():
	is_on_corner_ramp = false

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

	# Create a timer to reset can_boost after BOOST_COOLDOWN seconds
	var boost_cooldown = get_tree().create_timer(BOOST_COOLDOWN)
	boost_cooldown.timeout.connect(func(): can_boost = true)

func die ():
	if is_invincible: return
	if is_dead: return
	is_dead = true

	# Store death position and velocity before disabling physics
	var death_position = global_position
	var death_velocity = linear_velocity  # Capture the vehicle's velocity

	set_physics_process(false)
	set_process_input(false)
	$EngineSound.stop()

	# Find the current camera
	var current_camera = [$ChaseCamPivot/ChaseCam, $SideCam, $FirstPersonCam, $ThirdPersonCam, $ChaseCamLocked].filter(func(camera): 
		return camera.current == true
	)[0]

	# Create death camera
	death_camera = Camera3D.new()
	
	# Find the SubViewport that contains this player
	var viewport = get_viewport()
	if viewport is SubViewport:
		# In split-screen mode, add to the SubViewport
		viewport.add_child(death_camera)
	else:
		# In single-player mode, add to root
		get_tree().root.add_child(death_camera)

	death_camera.global_transform = current_camera.global_transform
	death_camera.current = true

	for original_part in original_parts:
		generate_and_separate_clone_of_part(original_part, death_velocity, death_position)

	current_lives -= 1
	if (current_lives == 0):
		is_eliminated = true
		emit_signal("player_eliminated", player_number)
		return
	else:
		emit_signal("player_lost_a_life", player_number)
	# Start respawn timer
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(_respawn)

func handle_return_to_start_position_input ():
	if (Input.is_action_just_pressed(str("p", player_number, "_reset_to_start_pos")) and GameSettings.debug_mode_on):
		reorientation_cooldown = 1.0
		self.position = spawn_point
		self.rotation = spawn_rotation
		linear_velocity = Vector3(0, 0, 0)
		update_new_center_of_gravity_point(_initial_gravity_point)

func handle_cycle_through_cameras_input ():
	if Input.is_action_just_pressed(str("p", player_number, "_toggle_camera")):
		var camera_configs = [
			{"camera": $ChaseCamPivot/ChaseCam, "show_crosshair": false},
			{"camera": $ChaseCamLocked, "show_crosshair": true},
			{"camera": $SideCam, "show_crosshair": false},
			{"camera": $FirstPersonCam, "show_crosshair": true},
			{"camera": $ThirdPersonCam, "show_crosshair": true}
		]
		
		if not GameSettings.debug_mode_on:
			camera_configs = camera_configs.slice(0, 2)
			# Clamp camera index to valid range for non-debug mode
			current_camera_index = current_camera_index % camera_configs.size()
		
		# Cycle to next camera
		current_camera_index = (current_camera_index + 1) % camera_configs.size()
		var next_config = camera_configs[current_camera_index]
		
		next_config.camera.current = true
		
		if next_config.show_crosshair:
			emit_signal("show_crosshair")
		else:
			emit_signal("hide_crosshair")

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
	if current_reload_level > 0 && Input.is_action_just_pressed(str("p", player_number, "_fire")):
		rocket_launcher.fire_rocket()

func auto_reorient_vehicle_if_stuck_too_long(delta):
	# Skip this check if we're already in a reorientation process
	if is_reorienting:
		return
	
	# Update the orientation check timer
	orientation_check_timer += delta
	
	# Only perform expensive checks once per second
	if orientation_check_timer >= ORIENTATION_CHECK_INTERVAL:
		orientation_check_timer = 0.0
		
		var orientation_data = calculate_orientation_data()
		
		# Check for problematic orientations and store state
		is_upside_down = global_transform.basis.y.dot(orientation_data.desired_up) < -0.5  # More than 120 degrees from desired up
		is_stuck_on_nose = (-global_transform.basis.z).dot(orientation_data.desired_up) < -0.5  # Forward vector pointing down
		is_stuck_on_tail = (-global_transform.basis.z).dot(orientation_data.desired_up) > 0.5  # Forward vector pointing up
		
		# Notify camera of stuck state
		var is_stuck = is_upside_down or is_stuck_on_nose or is_stuck_on_tail
		$ChaseCamPivot.set_stuck_off_wheels(is_stuck)
		
		if is_stuck:
			time_upside_down += ORIENTATION_CHECK_INTERVAL  # Add the full interval since we checked
			if time_upside_down > MAX_UPSIDE_DOWN_TIME:
				# For safety feature, reset cooldown and call regular reorient
				reorientation_cooldown = 0.0  # Ensure we can reorient
				perform_reorientation(orientation_data, false)
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

func _respawn ():
	reorientation_cooldown = 1.0
	# Reset position and rotation
	global_position = spawn_point
	rotation = spawn_rotation
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	if (not playing_obstacle_course_mode):
		current_boost_level = STARTING_BOOST_LEVEL
		current_reload_level = STARTING_RELOAD_LEVEL

	_update_lives_display()
	_update_boost_display()
	
	# Show original parts
	for part in original_parts:
		if part:
			part.visible = true
	
	# Re-enable physics and collision
	set_physics_process(true)
	set_process_input(true)
	
	$EngineSound.play()
	
	# Switch camera back
	death_camera.queue_free()
	$ChaseCamPivot/ChaseCam.current = true
	notify_chase_cam_of_teleportation()

	is_dead = false
	
	if (GameSettings.debug_mode_on):
		current_boost_level = 5.5
		_update_boost_display()

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
	collision_layer = 1 # poptential issue?
	
	var invincibility_buffer_timer = get_tree().create_timer(0.5)
	await invincibility_buffer_timer.timeout
	is_invincible = false

func apply_invincibility_shader ():
	var invincibility_shader = preload("res://invincibility_shader.tres")
	var shader_material = ShaderMaterial.new()
	# can we make the shader glow more?
	shader_material.shader = invincibility_shader
	$Body/MeshInstance3D.material_override = shader_material

func set_new_spawn_point (point):
	spawn_point = point.position
	spawn_rotation = point.rotation

func move_to_spawn_point ():
	global_position = spawn_point
	global_rotation = spawn_rotation

	if (GameSettings.debug_mode_on):
		current_boost_level = 5.5
		_update_boost_display()

func reorient_vehicle_over_time(duration: float = 0.5):
	if is_on_corner_ramp:
		return
	var orientation_data = calculate_orientation_data()
	perform_reorientation(orientation_data, true, duration)

func start_reorientation(duration: float, orientation_data: Dictionary):
	is_reorienting = true # this tells physics process to run the reorientation code each frame
	reorientation_timer = 0.0
	reorientation_duration = duration
	
	# Start the cooldown timer
	reorientation_cooldown = REORIENTATION_COOLDOWN_DURATION
	
	# Store initial state
	reorientation_initial_basis = global_transform.basis
	reorientation_initial_origin = global_transform.origin

# Calculates the target transform for reorientation
func calculate_target_transform(orientation_data: Dictionary):
	var current_forward = -reorientation_initial_basis.z
	
	if orientation_data.is_flat_surface:
		calculate_flat_surface_transform(current_forward, orientation_data.desired_up)
	else:
		calculate_spherical_surface_transform(current_forward, orientation_data.desired_up)
	
	# Calculate the target position with the lift
	reorientation_target_origin = reorientation_initial_origin + orientation_data.desired_up * 0.5

# Calculates the target transform for flat surfaces
func calculate_flat_surface_transform(current_forward: Vector3, desired_up: Vector3):
	# Project current_forward onto the horizontal plane
	var horizontal_forward = current_forward
	horizontal_forward.y = 0  # Remove vertical component
	
	if horizontal_forward.length_squared() > 0.001:
		horizontal_forward = horizontal_forward.normalized()
	else:
		# If the forward vector is mostly vertical, use the world forward as fallback
		horizontal_forward = -Vector3.FORWARD
	
	# Construct target basis from horizontal forward and up directions
	construct_target_basis(horizontal_forward, desired_up)

# Calculates the target transform for spherical surfaces
func calculate_spherical_surface_transform(current_forward: Vector3, desired_up: Vector3):
	# For spherical surfaces, use the approach from original code
	construct_target_basis(current_forward, desired_up)

# Constructs the target basis from forward and up directions
func construct_target_basis(forward: Vector3, up: Vector3):
	var right = forward.cross(up).normalized()
	var new_forward = up.cross(right).normalized()

	# Construct the target basis
	reorientation_target_basis = Basis()
	reorientation_target_basis.x = right
	reorientation_target_basis.y = up
	reorientation_target_basis.z = -new_forward  # Negative because Godot uses -Z as forward

func process_reorientation(delta: float):
	reorientation_timer += delta
	var t = min(reorientation_timer / reorientation_duration, 1.0)
	
	# Use smoothstep for nicer easing
	var weight = smoothstep(0.0, 1.0, t)
	
	# Interpolate the basis
	global_transform.basis = reorientation_initial_basis.slerp(reorientation_target_basis, weight)
	
	# Interpolate the position
	global_transform.origin = reorientation_initial_origin.lerp(reorientation_target_origin, weight)
	
	# Gradually reduce angular velocity
	angular_velocity = angular_velocity * (1.0 - weight)
	
	# Check if we're done
	if t >= 1.0:
		# Make sure we set exactly to the target values at the end
		global_transform.basis = reorientation_target_basis
		global_transform.origin = reorientation_target_origin
		angular_velocity = Vector3.ZERO
		is_reorienting = false

func draw_debug_reorientation():
	# Draw a line showing the desired up direction
	var to_gravity_point = global_transform.origin - _closest_gravity_point
	var desired_up = to_gravity_point.normalized()
	
	# Draw the current up vector in blue
	DebugDraw.draw_line(
		global_transform.origin, 
		global_transform.origin + global_transform.basis.y * 3.0, 
		Color.BLUE
	)

	# Draw the target up vector in yellow
	DebugDraw.draw_line(
		global_transform.origin, 
		global_transform.origin + reorientation_target_basis.y * 3.0, 
		Color.YELLOW
	)

func set_surface_type(new_surface_type: SurfaceType):
	current_surface_type = new_surface_type

func update_side_surface_gravity_direction(direction):
	desired_up = direction
	update_camera_state(desired_up)

func update_camera_state(new_desired_up: Vector3):
	# Detect current states
	var airborne = !can_boost
	var boosting = is_boost_sound_playing
	var gravity_transitioning = is_reorienting  # Vehicle reorientation often indicates gravity transition

	# Update camera with both direction and state
	$ChaseCamPivot.set_desired_up(new_desired_up)
	$ChaseCamPivot.set_camera_state(airborne, boosting, gravity_transitioning)

func notify_chase_cam_of_teleportation ():
	if $ChaseCamPivot/ChaseCam.current == true:
		# Reset the chase cam direction for when we switch back to it
		$ChaseCamPivot.on_teleportation()

		# Switch to locked camera during teleportation
		$ChaseCamLocked.current = true

		# Create timer to switch back to normal chase cam after 2 seconds
		var teleport_timer = get_tree().create_timer(2)
		teleport_timer.timeout.connect(func(): $ChaseCamPivot/ChaseCam.current = true)

func validate_gravity_point_on_interval(delta: float):
	gravity_validation_timer += delta
	
	if gravity_validation_timer >= GRAVITY_VALIDATION_INTERVAL:
		gravity_validation_timer = 0.0
		
		var contacted_surface = find_contacted_gravity_source()
		if contacted_surface and contacted_surface.global_position != _closest_gravity_point:
			update_new_center_of_gravity_point(contacted_surface.global_position)

func find_contacted_gravity_source():
	var space_state = get_world_3d().direct_space_state
	
	# Try raycast first
	var query = PhysicsRayQueryParameters3D.create(global_transform.origin, global_transform.origin + Vector3(0, -2.0, 0))
	query.collision_mask = 1
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if result and result.collider.name.begins_with("Level"):
		return result.collider
	
	# Fallback to sphere cast
	var shape = SphereShape3D.new()
	shape.radius = 3.0
	
	var shape_query = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = shape
	shape_query.transform.origin = global_transform.origin
	shape_query.collision_mask = 1
	shape_query.exclude = [self]
	
	var shape_results = space_state.intersect_shape(shape_query)
	for contact in shape_results:
		if contact.collider.name.begins_with("Level"):
			return contact.collider
	
	return null

func update_targeting_laser():
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_transform.origin,
		global_transform.origin + -global_transform.basis.z * 10000.0  # Increased to 10000 units
	)
	query.collision_mask = 1
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	if result:
		var distance = global_transform.origin.distance_to(result.position)
		targeting_laser.update_laser_length(distance)
	else:
		targeting_laser.update_laser_length(10000.0)  # Increased to match raycast distance

func switch_on_obstacle_course_mode ():
	playing_obstacle_course_mode = true
	current_boost_level = 0.0
	current_reload_level = 0
	$RocketLauncher.hide_rocket()

func switch_off_obstacle_course_mode ():
	playing_obstacle_course_mode = false
	current_boost_level = STARTING_BOOST_LEVEL
	current_reload_level = STARTING_RELOAD_LEVEL
	$RocketLauncher.show_rocket()
