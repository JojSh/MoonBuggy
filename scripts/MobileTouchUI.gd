extends CanvasLayer

# On-screen touch buttons for mobile controls

@onready var steering_indicator = $Control/SteeringIndicator

var mobile_controls_enabled := false

func _ready():
	# Hide all buttons except Enable Mobile Control
	$Control/FireButton.visible = false
	$Control/BoostButton.visible = false
	$Control/CameraButton.visible = false
	$Control/MenuButton.visible = false

	# Connect to shake detection for menu (if enabled in MobileInputManager)
	if MobileInputManager and MobileInputManager.has_signal("shake_detected"):
		if not MobileInputManager.shake_detected.is_connected(_on_shake_detected):
			MobileInputManager.shake_detected.connect(_on_shake_detected)

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
	# Open pause menu on shake
	get_tree().paused = not get_tree().paused

func _on_accelerate_button_pressed():
	if MobileInputManager:
		MobileInputManager.set_accelerate_pressed(true)

func _on_accelerate_button_released():
	if MobileInputManager:
		MobileInputManager.set_accelerate_pressed(false)

func _on_enable_sensors_button_pressed():
	mobile_controls_enabled = not mobile_controls_enabled

	if mobile_controls_enabled:
		# Enable mobile controls
		if MobileInputManager:
			MobileInputManager._request_motion_permission()

		# Show all the mobile control buttons
		$Control/FireButton.visible = true
		$Control/BoostButton.visible = true
		$Control/CameraButton.visible = true
		$Control/MenuButton.visible = true

		# Update button text
		$Control/EnableSensorsButton.text = "Disable Mobile Control"
	else:
		# Disable mobile controls
		# Hide all the mobile control buttons
		$Control/FireButton.visible = false
		$Control/BoostButton.visible = false
		$Control/CameraButton.visible = false
		$Control/MenuButton.visible = false

		# Update button text
		$Control/EnableSensorsButton.text = "Enable Mobile Control"

func _on_camera_button_pressed():
	if MobileInputManager:
		MobileInputManager.set_camera_pressed()

func _on_menu_button_pressed():
	get_tree().paused = not get_tree().paused

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
