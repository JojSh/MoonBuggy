extends CanvasLayer

# On-screen touch buttons for mobile controls

@onready var steering_indicator = $Control/SteeringIndicator if has_node("Control/SteeringIndicator") else null
@onready var accel_bar_bg: Panel = $Control/AccelBarBG if has_node("Control/AccelBarBG") else null
@onready var accel_bar_fill: Panel = $Control/AccelBarBG/AccelBarFill if has_node("Control/AccelBarBG/AccelBarFill") else null

var mobile_controls_enabled := false
var smoothed_accel_value: float = 0.0
var accel_bar_material: ShaderMaterial

func _ready():
	# Setup gradient shader for acceleration bar
	_setup_accel_bar_shader()
	# Hide all buttons except Enable Mobile Control
	$Control/FireButton.visible = false
	$Control/BoostButton.visible = false
	$Control/CameraButton.visible = false
	$Control/MenuButton.visible = false

	# Hide accel bar initially
	if accel_bar_bg:
		accel_bar_bg.visible = false

	# Connect to shake detection for menu (if enabled in MobileInputManager)
	if MobileInputManager and MobileInputManager.has_signal("shake_detected"):
		if not MobileInputManager.shake_detected.is_connected(_on_shake_detected):
			MobileInputManager.shake_detected.connect(_on_shake_detected)

func _process(delta):
	# Update accelerometer bar
	if accel_bar_fill and mobile_controls_enabled and MobileInputManager:
		var accel_value = MobileInputManager.get_accel_display_value()

		# Smooth the acceleration value to reduce jitter
		var smoothing_speed = 8.0  # Lower = smoother but slower response
		smoothed_accel_value = lerp(smoothed_accel_value, accel_value, smoothing_speed * delta)

		# Use absolute value for fill height (0 to 1)
		var fill_percent = abs(smoothed_accel_value)

		# Update fill bar height (grows from bottom)
		var bar_height = accel_bar_bg.size.y - 4  # Account for margins
		accel_bar_fill.offset_top = -fill_percent * bar_height

		# Update shader for forward/reverse mode
		if accel_bar_material:
			accel_bar_material.set_shader_parameter("is_reverse", smoothed_accel_value < 0.0)

func _on_fire_button_button_down():
	if MobileInputManager:
		MobileInputManager.set_fire_button_down()

func _on_fire_button_button_up():
	if MobileInputManager:
		MobileInputManager.set_fire_button_up()

func _on_boost_button_button_down():
	if MobileInputManager:
		MobileInputManager.set_boost_pressed(true)

func _on_boost_button_button_up():
	if MobileInputManager:
		MobileInputManager.set_boost_pressed(false)

func _on_shake_detected():
	get_tree().paused = not get_tree().paused

func _on_enable_sensors_button_pressed():
	mobile_controls_enabled = not mobile_controls_enabled

	if mobile_controls_enabled:
		# Enable mobile controls
		if MobileInputManager:
			MobileInputManager._request_motion_permission()
			MobileInputManager.set_mobile_controls_enabled(true)

		# Show all the mobile control buttons
		$Control/FireButton.visible = true
		$Control/BoostButton.visible = true
		$Control/CameraButton.visible = true
		$Control/MenuButton.visible = true
		if accel_bar_bg:
			accel_bar_bg.visible = true

		# Update button text
		$Control/EnableSensorsButton.text = "Disable Mobile Control"
	else:
		# Disable mobile controls
		if MobileInputManager:
			MobileInputManager.set_mobile_controls_enabled(false)
		# Hide all the mobile control buttons
		$Control/FireButton.visible = false
		$Control/BoostButton.visible = false
		$Control/CameraButton.visible = false
		$Control/MenuButton.visible = false
		if accel_bar_bg:
			accel_bar_bg.visible = false

		# Update button text
		$Control/EnableSensorsButton.text = "Enable Mobile Control"

func _on_camera_button_pressed():
	if MobileInputManager:
		MobileInputManager.set_camera_pressed()

func _on_menu_button_pressed():
	var root_node = get_tree().root.get_node_or_null("RootNode")
	if root_node and root_node.has_method("toggle_pause_menu"):
		root_node.toggle_pause_menu()

func _on_flip_button_pressed():
	if MobileInputManager:
		MobileInputManager.set_flip_requested()
	var flip_button = $Control.get_node_or_null("FlipButton")
	if flip_button:
		flip_button.visible = false

func show_flip_button():
	var flip_button = $Control.get_node_or_null("FlipButton")
	if flip_button and mobile_controls_enabled:
		flip_button.visible = true

func hide_flip_button():
	var flip_button = $Control.get_node_or_null("FlipButton")
	if flip_button:
		flip_button.visible = false

func are_mobile_controls_enabled() -> bool:
	return mobile_controls_enabled

func _setup_accel_bar_shader():
	if not accel_bar_fill:
		return

	var shader = load("res://shaders/accel_bar_gradient.gdshader")
	if shader:
		accel_bar_material = ShaderMaterial.new()
		accel_bar_material.shader = shader
		accel_bar_fill.material = accel_bar_material
