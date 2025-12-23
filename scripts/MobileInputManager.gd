extends Node

# Mobile input detection for tilt steering, touch controls, and shake to menu
# AutoLoad singleton

signal fire_button_pressed
signal fire_button_released
signal boost_button_pressed
signal boost_button_released
signal accelerate_button_pressed
signal accelerate_button_released
signal shake_detected

# Tilt steering sensitivity
@export var tilt_sensitivity: float = 2.0
@export var tilt_deadzone: float = 0.1
@export var accel_tilt_sensitivity: float = 0.3
@export var accel_tilt_deadzone: float = 0.5

# Shake detection
@export var shake_threshold: float = 25.0
var previous_accel := Vector3.ZERO
var shake_cooldown := 0.0

# Current tilt steering value (-1 to 1)
var steering_input: float = 0.0
# Current tilt acceleration value (-1 to 1, negative = reverse, positive = forward)
var accel_input: float = 0.0

# Touch button states
var is_fire_button_held := false
var is_fire_just_released := false
var is_boost_pressed := false
var is_accelerate_pressed := false
var is_camera_just_pressed := false
var is_shake_just_detected := false
var is_flip_just_requested := false

var _is_mobile_cache: bool = false
var _mobile_check_done: bool = false

func _ready():
	# Delay mobile check to allow sensors to initialize
	call_deferred("_check_mobile_platform")

func _check_mobile_platform():
	_is_mobile_cache = _detect_mobile()
	_mobile_check_done = true
	if not _is_mobile_cache:
		set_process(false)
	else:
		_request_motion_permission()

func _detect_mobile() -> bool:
	# Check for native mobile
	if OS.has_feature("mobile"):
		return true

	# For web builds, check if touch/accelerometer is available
	if OS.has_feature("web"):
		var accel = Input.get_accelerometer()
		if accel != Vector3.ZERO:
			return true
		var gravity = Input.get_gravity()
		if gravity.length() > 0.1:
			return true

		# Check if we have JavaScript sensor data (for iOS Safari)
		var js_tilt = JavaScriptBridge.eval("window.mobileTiltX")
		if js_tilt != null:
			return true

	return false

func is_mobile_platform() -> bool:
	if _mobile_check_done:
		return _is_mobile_cache
	return _detect_mobile()

var _js_tilt_value: float = 0.0

func _process(delta):
	if not _is_mobile_cache:
		return

	# Reset just-pressed flags each frame
	is_fire_just_released = false
	is_camera_just_pressed = false
	is_shake_just_detected = false
	# Don't auto-reset flip - it's consumed when read

	if shake_cooldown > 0:
		shake_cooldown -= delta

	# Get accelerometer data
	var accel = Input.get_accelerometer()
	var gravity = Input.get_gravity()

	# Use gravity for tilt if accelerometer is zero
	if accel == Vector3.ZERO and gravity != Vector3.ZERO:
		accel = gravity

	# Tilt steering (use X axis for portrait mode)
	var tilt_x = accel.x
	var tilt_y = accel.y

	# If Godot's built-in sensors aren't working, try JavaScript values
	if accel == Vector3.ZERO and gravity == Vector3.ZERO and OS.has_feature("web"):
		var js_tilt_x = JavaScriptBridge.eval("window.mobileTiltX || 0")
		var js_tilt_y = JavaScriptBridge.eval("window.mobileTiltY || 0")
		if js_tilt_x != null:
			tilt_x = float(js_tilt_x)
		if js_tilt_y != null:
			tilt_y = float(js_tilt_y)

	# Calculate steering from X axis (inverted so tilt left = steer left)
	if abs(tilt_x) < tilt_deadzone:
		steering_input = 0.0
	else:
		steering_input = clamp(-tilt_x * tilt_sensitivity, -1.0, 1.0)

	# Calculate acceleration from Y axis
	# Y is around -8.4 when phone is held upright in portrait
	# Tilt away (forward): Y becomes MORE negative (e.g., -10, -11)
	# Tilt toward (backward): Y becomes LESS negative (e.g., -6, -7)

	# Use -8.4 as neutral
	var neutral_y = -8.4
	var y_offset = tilt_y - neutral_y

	if abs(y_offset) < accel_tilt_deadzone:
		accel_input = 0.0
	else:
		# y_offset < 0 means Y became more negative = tilt away = forward (positive)
		# y_offset > 0 means Y became less negative = tilt toward = reverse (negative)
		var normalized_tilt = y_offset - sign(y_offset) * accel_tilt_deadzone
		accel_input = clamp(normalized_tilt * accel_tilt_sensitivity, -1.0, 1.0)

	# Shake detection (disabled for web/mobile - using UI button instead)
	# if shake_cooldown <= 0 and previous_accel != Vector3.ZERO:
	# 	var accel_delta = (accel - previous_accel).length()
	# 	if accel_delta > shake_threshold:
	# 		print("SHAKE DETECTED! Delta: ", accel_delta, " Threshold: ", shake_threshold)
	# 		emit_signal("shake_detected")
	# 		is_shake_just_detected = true
	# 		shake_cooldown = 1.0

	previous_accel = accel

func get_steering() -> float:
	if not is_mobile_platform():
		return 0.0
	return steering_input

func get_accel_input() -> float:
	if not is_mobile_platform():
		return 0.0
	return accel_input

func is_mobile_active() -> bool:
	return is_mobile_platform()

# Called by touch UI buttons
func set_fire_button_down():
	is_fire_button_held = true

func set_fire_button_up():
	is_fire_button_held = false
	is_fire_just_released = true

func get_fire_button_held() -> bool:
	return is_fire_button_held

func get_fire_just_released() -> bool:
	return is_fire_just_released

func set_boost_pressed(pressed: bool):
	if pressed and not is_boost_pressed:
		emit_signal("boost_button_pressed")
	elif not pressed and is_boost_pressed:
		emit_signal("boost_button_released")
	is_boost_pressed = pressed

func get_boost_pressed() -> bool:
	return is_boost_pressed

func set_accelerate_pressed(pressed: bool):
	if pressed and not is_accelerate_pressed:
		emit_signal("accelerate_button_pressed")
	elif not pressed and is_accelerate_pressed:
		emit_signal("accelerate_button_released")
	is_accelerate_pressed = pressed

func get_accelerate_pressed() -> bool:
	return is_accelerate_pressed

func set_camera_pressed():
	is_camera_just_pressed = true

func get_camera_just_pressed() -> bool:
	return is_camera_just_pressed

func get_shake_just_detected() -> bool:
	return is_shake_just_detected

func set_flip_requested():
	is_flip_just_requested = true

func get_flip_just_requested() -> bool:
	var result = is_flip_just_requested
	is_flip_just_requested = false  # Consume the flag when read
	return result

func _request_motion_permission():
	# iOS 13+ Safari requires permission for motion sensors
	if OS.has_feature("web"):
		var js_code = """
		if (typeof DeviceMotionEvent !== 'undefined' && typeof DeviceMotionEvent.requestPermission === 'function') {
			DeviceMotionEvent.requestPermission()
				.then(response => {
					if (response === 'granted') {
						console.log('Motion permission granted');
						window.addEventListener('devicemotion', (event) => {
							if (event.accelerationIncludingGravity) {
								// Store X tilt for steering, Y tilt for acceleration, Z for shake detection (portrait mode)
								window.mobileTiltX = event.accelerationIncludingGravity.x || 0;
								window.mobileTiltY = event.accelerationIncludingGravity.y || 0;
								window.mobileTiltZ = event.accelerationIncludingGravity.z || 0;
							}
						});
					}
				})
				.catch(console.error);
		} else {
			// Non-iOS or doesn't need permission, just add listener
			window.addEventListener('devicemotion', (event) => {
				if (event.accelerationIncludingGravity) {
					window.mobileTiltX = event.accelerationIncludingGravity.x || 0;
					window.mobileTiltY = event.accelerationIncludingGravity.y || 0;
					window.mobileTiltZ = event.accelerationIncludingGravity.z || 0;
				}
			});
		}
		if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
			DeviceOrientationEvent.requestPermission()
				.then(response => {
					if (response === 'granted') {
						console.log('Orientation permission granted');
					}
				})
				.catch(console.error);
		}
		"""
		JavaScriptBridge.eval(js_code)

		# Force mobile detection to true since we now have sensor access
		_is_mobile_cache = true
		_mobile_check_done = true

		# Start polling the JavaScript value
		set_process(true)
