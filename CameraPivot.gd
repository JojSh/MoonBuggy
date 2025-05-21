extends Node3D

var direction = Vector3.FORWARD
@export_range (1,10) var smooth_speed = 2.5
@onready var desired_up = Vector3.UP

func _physics_process(delta):
	var current_velocity = get_parent().get_linear_velocity()
	if current_velocity.length_squared() > 1:
		direction = lerp(direction, current_velocity.normalized(), smooth_speed * delta)
	global_transform.basis = get_rotation_from_direction(direction)

func get_rotation_from_direction(look_direction: Vector3) -> Basis:
	look_direction = look_direction.normalized()
	var x_axis = look_direction.cross(desired_up)
	var y_axis = look_direction.cross(x_axis)
	return Basis(x_axis, desired_up, -look_direction)
