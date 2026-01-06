extends Node

# Mobile input detection for tilt steering, touch controls, and shake to menu
# AutoLoad singleton

signal boost_button_pressed
signal boost_button_released
signal shake_detected

# Tilt sensitivity
@export var tilt_sensitivity: float = 2.0
@export var tilt_deadzone: float = 0.1
@export var accel_tilt_deadzone: float = 0.5

# Current tilt steering value (-1 to 1)
var steering_input: float = 0.0
# Current tilt acceleration value (-1 to 1, negative = reverse, positive = forward)
var accel_input: float = 0.0

# Touch button states
var is_fire_button_held := false
var is_fire_just_released := false
var is_boost_pressed := false
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

func _process(_delta):
	if not _is_mobile_cache:
		return

	# Reset just-pressed flags each frame
	is_fire_just_released = false
	is_camera_just_pressed = false
	is_shake_just_detected = false

	var tilt = _read_tilt_values()
	steering_input = _calculate_steering(tilt.x)
	accel_input = _calculate_accel_from_tilt(tilt.z)

func _read_tilt_values() -> Vector3:
	var accel = Input.get_accelerometer()
	var gravity = Input.get_gravity()

	if accel == Vector3.ZERO and gravity != Vector3.ZERO:
		accel = gravity

	if accel == Vector3.ZERO and gravity == Vector3.ZERO and OS.has_feature("web"):
		var js_x = JavaScriptBridge.eval("window.mobileTiltX || 0")
		var js_z = JavaScriptBridge.eval("window.mobileTiltZ || 0")
		return Vector3(
			float(js_x) if js_x != null else 0.0,
			0.0,
			float(js_z) if js_z != null else 0.0
		)

	return accel

func _calculate_steering(tilt_x: float) -> float:
	if abs(tilt_x) < tilt_deadzone:
		return 0.0
	return clamp(-tilt_x * tilt_sensitivity, -1.0, 1.0)

func _calculate_accel_from_tilt(tilt_z: float) -> float:
	# Z axis mapping: upright (Z=0) = reverse, tilted away (Z=-4) = neutral, more tilt (Z=-5.5) = forward
	const NEUTRAL_Z = -4.0
	const MAX_FORWARD_Z = 1.5
	const MAX_REVERSE_Z = 4.0

	var z_offset = tilt_z - NEUTRAL_Z

	if abs(z_offset) < accel_tilt_deadzone:
		return 0.0

	var active_z = z_offset - sign(z_offset) * accel_tilt_deadzone

	if active_z < 0:
		return clamp(-active_z / MAX_FORWARD_Z, 0.0, 1.0)
	else:
		return clamp(-active_z / MAX_REVERSE_Z, -1.0, 0.0)

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
