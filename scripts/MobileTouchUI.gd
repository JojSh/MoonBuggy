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

func _process(_delta):
	pass

func _on_fire_button_button_down():
	print("FIRE BUTTON DOWN - showing laser")
	if MobileInputManager:
		MobileInputManager.set_fire_button_down()

func _on_fire_button_button_up():
	print("FIRE BUTTON UP - firing rocket")
	if MobileInputManager:
		MobileInputManager.set_fire_button_up()

func _on_boost_button_button_down():
	print("BOOST PRESSED")
	if MobileInputManager:
		MobileInputManager.set_boost_pressed(true)
		print("Boost state set to true")

func _on_boost_button_button_up():
	print("BOOST RELEASED")
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
	print("CAMERA BUTTON PRESSED")
	if MobileInputManager:
		MobileInputManager.set_camera_pressed()

func _on_menu_button_pressed():
	print("MENU BUTTON PRESSED")
	get_tree().paused = not get_tree().paused
