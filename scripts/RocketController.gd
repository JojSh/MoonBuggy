extends Node

var controlling_player: Node = null
var rocket_body: RigidBody3D = null
var takeover_camera: Camera3D = null
var is_active: bool = false
var roll_leveling_enabled: bool = false
var boost_level: float = 1.0  # Current boost multiplier (1.0 = normal, 5.0 = max boost)

const STEERING_TORQUE: float = 50.0  # Torque strength for steering (increased for responsiveness)
const FORWARD_THRUST: float = 800.0  # Continuous forward thrust to make rocket travel in facing direction
const VELOCITY_DAMPING: float = 0.85  # Reduces old momentum (0.0 = no damping, 1.0 = full stop)
const ANGULAR_DAMPING: float = 0.95  # Angular damping when no input (only applied when not steering)
const MAX_ANGULAR_VELOCITY: float = 5.0  # Maximum turning speed (radians per second)
const ROLL_LEVELING_STRENGTH: float = 10.0  # Strength of auto-leveling for roll axis
const MANUAL_ALIGNMENT_STRENGTH: float = 50.0  # Strength of manual alignment when button pressed
const MAX_BOOST_MULTIPLIER: float = 5.0  # Maximum boost speed multiplier
const BOOST_RAMP_TIME: float = 1.0  # Time to reach max boost in seconds
const CAMERA_DISTANCE: float = 5.0  # (8.0) How far behind the rocket the camera follows
const CAMERA_HEIGHT: float = 0.0  # (2.0) How high above the rocket the camera is positioned
const EXPLOSION_CAMERA_DELAY: float = 3.0  # Seconds to keep camera on explosion site

var explosion_position: Vector3
var is_showing_explosion: bool = false
@onready var rocket_mesh: MeshInstance3D = get_parent().get_node("RocketProjectileMesh")
@onready var dark_shaft_material: Material = load("res://resources/rocket_shaft_material_dark_3d.tres")

signal control_ended(controller: Node)

func _ready():
	rocket_body = get_parent()
	if not rocket_body is RigidBody3D:
		return

func _process(delta):
	# Handle camera updates even during explosion viewing
	if takeover_camera and (is_active or is_showing_explosion):
		update_chase_camera()
	
	# Only process control logic if actively controlling
	if not is_active or not controlling_player:
		return
	
	# Control continues until rocket is destroyed (no time limit)
	
	# Apply velocity damping to reduce momentum carryover for better steering
	apply_velocity_damping()
	
	# Update boost level based on fire button input
	update_boost_level()
	
	# Apply continuous forward thrust so rocket travels in facing direction
	apply_forward_thrust()
	
	# Apply gentle roll leveling to keep rocket upright (if enabled for this rocket)
	if roll_leveling_enabled:
		apply_roll_leveling()
	
	# Process player input for rocket steering
	handle_steering_input()

func assign_player_control(player: Node, enable_roll_leveling: bool = false):
	if controlling_player:
		return
	
	controlling_player = player
	is_active = true
	roll_leveling_enabled = enable_roll_leveling
	
	# Create and setup third-person chase camera
	setup_chase_camera()
	
	# Apply visual feedback - swap only the shaft material (surface 0)
	rocket_mesh.set_surface_override_material(0, dark_shaft_material)
	

func setup_chase_camera():
	if not controlling_player:
		return
	
	# Create rocket chase camera
	takeover_camera = Camera3D.new()
	takeover_camera.name = "RocketChaseCamera"
	
	# Find the appropriate viewport to add the camera to
	var viewport = controlling_player.get_viewport()
	if viewport:
		viewport.add_child(takeover_camera)
		
		# Position camera behind and above the rocket
		update_chase_camera()
		
		# Make this camera active
		takeover_camera.current = true
		

func handle_steering_input():
	if not controlling_player or not rocket_body:
		return
	
	var player_num = controlling_player.player_number
	
	# Check for manual alignment input
	if Input.is_action_pressed(str("p", player_num, "_flip")):
		apply_manual_alignment()
		return  # Skip normal steering when aligning
	
	# Get steering input (using the same input actions as the player's car)
	var steer_input = Input.get_axis(str("p", player_num, "_turn_right"), str("p", player_num, "_turn_left"))
	var pitch_input = Input.get_axis(str("p", player_num, "_reverse"), str("p", player_num, "_accelerate"))
	
	if abs(steer_input) > 0.1 or abs(pitch_input) > 0.1:
		# Apply rotational torque to steer the rocket (rotate it) instead of pushing it sideways
		# Rocket forward is -X, up is -Z, right is +Y
		var rocket_up = -rocket_body.global_transform.basis.z      # Up direction
		var rocket_right = rocket_body.global_transform.basis.y    # Right direction
		
		# Calculate torque vectors for steering:
		# - Left/Right input rotates around the rocket's up axis (yaw) - this changes direction!
		# - Up/Down input rotates around the rocket's right axis (pitch)
		# Reduce steering power when boosting (harder to steer at high speed)
		var steering_multiplier = 1.0 - (boost_level - 1.0) * 0.8 / (MAX_BOOST_MULTIPLIER - 1.0)
		var yaw_torque = rocket_up * steer_input * STEERING_TORQUE * steering_multiplier      # Yaw left/right (changes direction)
		var pitch_torque = rocket_right * pitch_input * STEERING_TORQUE * steering_multiplier # Pitch up/down
		
		# Apply the torque to rotate the rocket
		rocket_body.apply_torque(yaw_torque + pitch_torque)

		if rocket_body.angular_velocity.length() > MAX_ANGULAR_VELOCITY:
			rocket_body.angular_velocity = rocket_body.angular_velocity.normalized() * MAX_ANGULAR_VELOCITY
	else:
		# No input - apply angular damping to gradually slow rotation
		rocket_body.angular_velocity *= ANGULAR_DAMPING

func apply_velocity_damping():
	if not rocket_body:
		return
	
	# Reduce existing velocity to make steering more responsive
	# This counteracts momentum carryover from the original trajectory
	rocket_body.linear_velocity *= VELOCITY_DAMPING

func apply_forward_thrust():
	if not rocket_body:
		return
	
	# Apply continuous thrust in the direction the rocket is facing
	var rocket_forward = -rocket_body.global_transform.basis.x  # Rocket's forward direction
	var thrust_force = rocket_forward * FORWARD_THRUST * boost_level
	rocket_body.apply_central_force(thrust_force)

func update_boost_level():
	if not controlling_player:
		return
	
	var player_num = controlling_player.player_number
	var is_boosting = Input.is_action_pressed(str("p", player_num, "_fire"))
	
	if is_boosting:
		# Gradually increase boost level over BOOST_RAMP_TIME seconds
		var boost_increase = (MAX_BOOST_MULTIPLIER - 1.0) / BOOST_RAMP_TIME * get_process_delta_time()
		boost_level = min(boost_level + boost_increase, MAX_BOOST_MULTIPLIER)
	else:
		# Gradually decrease boost level back to normal over same time period
		var boost_decrease = (MAX_BOOST_MULTIPLIER - 1.0) / BOOST_RAMP_TIME * get_process_delta_time()
		boost_level = max(boost_level - boost_decrease, 1.0)

func apply_roll_leveling():
	if not rocket_body:
		return
	
	# Get the rocket's current orientation
	var rocket_forward = -rocket_body.global_transform.basis.x  # Rocket's forward direction
	var rocket_up = -rocket_body.global_transform.basis.z       # Rocket's current up direction
	
	# Calculate desired up direction (world up projected onto rocket's right plane)
	var world_up = Vector3.UP
	var rocket_right = rocket_body.global_transform.basis.y
	var desired_up = world_up - world_up.dot(rocket_forward) * rocket_forward
	desired_up = desired_up.normalized()
	
	# Calculate roll correction needed
	var roll_error = rocket_up.cross(desired_up)
	var roll_correction_strength = roll_error.dot(rocket_forward) * ROLL_LEVELING_STRENGTH
	
	# Apply gentle roll correction torque
	if abs(roll_correction_strength) > 0.01:  # Only apply if there's significant roll
		var roll_torque = rocket_forward * roll_correction_strength
		rocket_body.apply_torque(roll_torque)

func apply_manual_alignment():
	if not rocket_body:
		return
	
	# Get the rocket's current orientation
	var rocket_forward = -rocket_body.global_transform.basis.x  # Rocket's forward direction
	var rocket_up = -rocket_body.global_transform.basis.z       # Rocket's current up direction
	
	# Calculate desired up direction (world up projected onto rocket's right plane) 
	var world_up = Vector3.UP
	var desired_up = world_up - world_up.dot(rocket_forward) * rocket_forward
	desired_up = desired_up.normalized()
	
	# Calculate the angle between current up and desired up
	var angle = rocket_up.angle_to(desired_up)
	
	# If there's significant misalignment, set angular velocity to achieve alignment in 0.5 seconds
	if angle > 0.01:  # Only align if there's meaningful roll
		# Cross product gives us the rotation axis
		var rotation_axis = rocket_up.cross(desired_up).normalized()
		
		# Set angular velocity to complete the rotation in 0.5 seconds (faster than target)
		# This compensates for damping and other forces fighting the alignment
		rocket_body.angular_velocity = rotation_axis * (angle / 0.5)

func update_chase_camera():
	if not takeover_camera:
		return
	
	if is_showing_explosion:
		# Camera stays focused on explosion site
		var world_up = Vector3.UP
		var camera_offset = Vector3(0, CAMERA_HEIGHT, CAMERA_DISTANCE)
		takeover_camera.global_transform.origin = explosion_position + camera_offset
		takeover_camera.look_at(explosion_position, world_up)
		return
	
	if not rocket_body:
		return
	
	# Normal rocket following behavior
	# Rocket's forward direction is -X axis (based on launch_force in rocket_projectile_inner.gd)
	var rocket_forward = -rocket_body.global_transform.basis.x  # Rocket's actual forward direction
	# Use -Z axis as up vector (camera was upside down with +Z)
	var rocket_up = -rocket_body.global_transform.basis.z       # Use -Z as rocket's up direction
	
	# Position camera behind the rocket (opposite to forward direction)
	var camera_offset = -rocket_forward * CAMERA_DISTANCE + rocket_up * CAMERA_HEIGHT
	takeover_camera.global_transform.origin = rocket_body.global_transform.origin + camera_offset
	
	# Use rocket's up vector to maintain proper orientation relative to rocket's perspective
	takeover_camera.look_at(rocket_body.global_transform.origin, rocket_up)

func end_control():
	# This can be called during explosion viewing too, so don't check is_active
	
	# Restore original rocket appearance - restore only surface 0 (shaft)
	var normal_shaft_material = load("res://rocket_shaft_material_3d.tres")
	rocket_mesh.set_surface_override_material(0, normal_shaft_material)
	
	# Reset all states
	is_active = false
	is_showing_explosion = false
	boost_level = 1.0  # Reset boost level
	
	# Clean up takeover camera
	if takeover_camera:
		takeover_camera.queue_free()
		takeover_camera = null
	
	# Emit signal and clear references
	emit_signal("control_ended", self)
	controlling_player = null

func _on_rocket_destroyed():
	# Called when the rocket explodes or goes out of bounds
	if is_active:
		# Store explosion position for camera
		explosion_position = rocket_body.global_position if rocket_body else Vector3.ZERO
		is_showing_explosion = true
		
		# Stop control but keep camera active for explosion viewing
		is_active = false
		
		# Delay the actual control end to keep camera on explosion
		var explosion_timer = get_tree().create_timer(EXPLOSION_CAMERA_DELAY)
		explosion_timer.timeout.connect(
