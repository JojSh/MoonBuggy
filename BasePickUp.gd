extends RigidBody3D

signal collected
signal moved_off_position

var initial_position = Vector3.ZERO
var check_position_timer = null
@export var position_threshold = 3.0  # Distance threshold to consider the pickup moved
@export var effect_method = ""  # The method to call on the vehicle body

func _ready():
	# Wait a short time to ensure the position is set by the spawner
	var init_timer = get_tree().create_timer(0.3)
	await init_timer.timeout
	save_initial_position()
	check_for_moved_off_spawn_pos()

func save_initial_position():
	initial_position = global_position

func _on_body_entered(body):
	if body is VehicleBody3D:
		emit_signal("collected")
		# Call the method specified in the export variable
		if body.has_method(effect_method):
			body.call(effect_method)
		queue_free()

func check_for_moved_off_spawn_pos():
	# Create a timer that repeats every few seconds
	if check_position_timer != null:
		check_position_timer.queue_free()

	check_position_timer = Timer.new()
	check_position_timer.wait_time = 10.0
	check_position_timer.timeout.connect(check_current_position_vs_initial)
	add_child(check_position_timer)
	check_position_timer.start()

func check_current_position_vs_initial():
	var distance = global_position.distance_to(initial_position)

	if distance > position_threshold:
		emit_signal("moved_off_position")
		queue_free()
