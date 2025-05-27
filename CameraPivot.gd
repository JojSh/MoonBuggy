extends Node3D

var direction = Vector3.FORWARD
@export_range (0.5, 10) var base_direction_speed = 5.0
@export_range (0.5, 10) var base_up_speed = 2.0
@export var enable_teleport_detection: bool = true

var is_airborne := false
var is_boosting := false
var is_gravity_transitioning := false

# Timer to pause/slow smoothing during startup and after teleportation
var pause_smoothing_timer := 1.0

# Teleportation detection
var last_parent_position := Vector3.ZERO

@onready var desired_up = Vector3.UP
@onready var current_up = Vector3.UP
@onready var parent_node: Node3D

func _ready():
	parent_node = get_parent()
	direction = parent_node.global_transform.basis.z
	last_parent_position = parent_node.global_transform.origin

func _physics_process(delta):
	if !parent_node:
		return

	pause_smoothing_timer -= delta
	
	# Check for teleportation and reset camera immediately if detected
	var current_parent_position = parent_node.global_transform.origin
	var teleport_distance = last_parent_position.distance_to(current_parent_position)

	if enable_teleport_detection and teleport_distance > 10.0:
		direction = parent_node.global_transform.basis.z
		current_up = desired_up
		global_transform.basis = get_rotation_from_direction(direction)
		pause_smoothing_timer = 2.0  # Pause smoothing for 2 seconds after teleport
		last_parent_position = current_parent_position
		return

	var current_velocity = parent_node.get_linear_velocity()
	var velocity_length = current_velocity.length_squared()

	# Calculate state-based speeds and determine target direction
	var speeds = update_smoothing_speeds()
	var target_direction: Vector3

	if pause_smoothing_timer > 0.0:
		# During startup or post-teleport, always use parent direction and slow smoothing
		target_direction = parent_node.global_transform.basis.z
		speeds.direction *= 0.1
		speeds.up *= 0.1
	elif velocity_length <= 4.0:
		# Low velocity - follow parent orientation
		target_direction = parent_node.global_transform.basis.z
	else:
		# High velocity - follow movement direction
		target_direction = current_velocity.normalized()

	# Apply smoothing
	direction = lerp(direction, target_direction, speeds.direction * delta)
	current_up = lerp(current_up, desired_up, speeds.up * delta)
	global_transform.basis = get_rotation_from_direction(direction)
	
	last_parent_position = current_parent_position

func get_rotation_from_direction(look_direction: Vector3) -> Basis:
	look_direction = look_direction.normalized()
	var x_axis = look_direction.cross(current_up)
	var y_axis = look_direction.cross(x_axis)
	return Basis(x_axis, current_up, -look_direction)

func update_smoothing_speeds() -> Dictionary:
	var dir_speed = base_direction_speed
	var up_speed = base_up_speed

	if is_boosting:
		up_speed *= 0.4
	elif is_airborne:
		dir_speed *= 0.6
		up_speed *= 0.2
	elif is_gravity_transitioning:
		up_speed *= 0.15

	return {"direction": dir_speed, "up": up_speed}

func set_camera_state(airborne: bool, boosting: bool, gravity_transitioning: bool = false):
	is_airborne = airborne
	is_boosting = boosting
	is_gravity_transitioning = gravity_transitioning

func set_desired_up(new_desired_up: Vector3):
	desired_up = new_desired_up
