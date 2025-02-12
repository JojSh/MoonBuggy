extends CanvasLayer

@onready var fps_display : Label = get_node("FPSDisplay")

func _ready():
	if (GameSettings.debug_mode_on):
		self.visible = true

func _process (_delta):
	if (GameSettings.debug_mode_on):
		update_fps_counter()

func update_fps_counter ():
	var fps = str(Engine.get_frames_per_second())
	fps_display.text = "FPS: " + str(fps)
