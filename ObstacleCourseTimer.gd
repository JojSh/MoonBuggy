extends CanvasLayer

@onready var timer_label = $TimerLabel
var start_time: float
var elapsed_time: float = 0.0
var is_running: bool = false
var is_complete: bool = false

func _ready():
	# Initially hide the timer
	visible = false

func _process(delta):
	if is_running and not is_complete:
		elapsed_time += delta
		update_timer_display()

func start_timer():
	elapsed_time = 0.0
	is_running = true
	is_complete = false
	visible = true

func stop_timer():
	is_running = false
	is_complete = true

func get_completion_time() -> String:
	return format_time(elapsed_time)

func update_timer_display():
	timer_label.text = "" + format_time(elapsed_time)

func format_time(seconds: float) -> String:
	var minutes = int(seconds) / 60
	var remaining_seconds = int(seconds) % 60
	var milliseconds = int((seconds - int(seconds)) * 100)
	return "%02d:%02d.%02d" % [minutes, remaining_seconds, milliseconds]
