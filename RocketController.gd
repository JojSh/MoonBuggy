extends Node

var controlling_player: Node = null
var rocket_body: RigidBody3D = null
var takeover_camera: Camera3D = null
var is_active: bool = false

const STEERING_TORQUE: float = 50.0  # Torque strength for steering (increased for responsiveness)
const FORWARD_THRUST: float = 800.0  # Continuous forward thrust to make rocket travel in facing direction
const VELOCITY_DAMPING: float = 0.85  # Reduces old momentum (0.0 = no damping, 1.0 = full stop)
const ANGULAR_DAMPING: float = 0.95  # Angular damping when no input (only applied when not steering)
const CAMERA_DISTANCE: float = 5.0  # (8.0) How far behind the rocket the camera follows
const CAMERA_HEIGHT: float = 0.0  # (2.0) How high above the rocket the camera is positioned
const EXPLOSION_CAMERA_DELAY: float = 3.0  # Seconds to keep camera on explosion site

var explosion_position: Vector3
var is_showing_explosion: bool = false
@onready var rocket_mesh: MeshInstance3D = get_parent().get_node("RocketProjectileMesh")
@onready var dark_shaft_material: Material = load("res://rocket_shaft_material_dark_3d.tres")

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
	
	# Apply continuous forward thrust so rocket travels in facing direction
	apply_forward_thrust()
	
	# Process player input for rocket steering
	handle_steering_input()

func assign_player_control(player: Node):
	if controlling_player:
		return
	
	controlling_player = player
	is_active = true
	
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
		var yaw_torque = rocket_up * steer_input * STEERING_TORQUE      # Yaw left/right (changes direction)
		var pitch_torque = rocket_right * pitch_input * STEERING_TORQUE # Pitch up/down
		
		# Apply the torque to rotate the rocket
		rocket_body.apply_torque(yaw_torque + pitch_torque)
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
	var thrust_force = rocket_forward * FORWARD_THRUST
	rocket_body.apply_central_force(thrust_force)

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
		explosion_timer.timeout.connect(end_control)

func get_controlling_player_number() -> int:
	return controlling_player.player_number if controlling_player else -1
