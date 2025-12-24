extends Camera3D

# called from Rootnode programmatically
func connect_crosshair_control_signals ():
	var p1_vehicle = get_children().filter(func(child):
		return child.name.begins_with("PlayerBuggy")
	)[0]

	if p1_vehicle:
		p1_vehicle.connect("hide_crosshair", hide_crosshair)
		p1_vehicle.connect("show_crosshair", show_crosshair)
		p1_vehicle.connect("needs_realignment", show_realignment_prompt)
		p1_vehicle.connect("realignment_resolved", hide_realignment_prompt)
		p1_vehicle.connect("show_controls_help", show_controls_help)
		p1_vehicle.connect("hide_controls_help", hide_controls_help)

func hide_crosshair ():
	$AimingReticle.visible = false

func show_crosshair ():
	$AimingReticle.visible = true

func _get_realignment_prompt_node():
	# Try to find RealignmentPrompt under camera first (offline single player)
	var realignment_prompt = get_node_or_null("UI/RealignmentPrompt")

	# If not found, try RootNode/SinglePlayerUI (network mode)
	if not realignment_prompt:
		var root_node = get_tree().root.get_node_or_null("RootNode")
		if root_node:
			realignment_prompt = root_node.get_node_or_null("SinglePlayerUI/RealignmentPrompt")

	return realignment_prompt

func show_realignment_prompt():
	# Check if mobile controls are enabled - show flip button instead of text
	var mobile_ui = get_tree().root.get_node_or_null("RootNode/MobileTouchUI")
	if mobile_ui and mobile_ui.has_method("are_mobile_controls_enabled") and mobile_ui.are_mobile_controls_enabled():
		if mobile_ui.has_method("show_flip_button"):
			mobile_ui.show_flip_button()
		return

	# Fallback: Show text prompt
	var realignment_prompt = _get_realignment_prompt_node()
	if realignment_prompt:
		var label = realignment_prompt.get_node_or_null("Label")
		if label:
			label.text = "[LB] / [E] to realign"
		realignment_prompt.visible = true

func hide_realignment_prompt():
	# Hide both the flip button and text prompt
	var mobile_ui = get_tree().root.get_node_or_null("RootNode/MobileTouchUI")
	if mobile_ui and mobile_ui.has_method("hide_flip_button"):
		mobile_ui.hide_flip_button()

	var realignment_prompt = _get_realignment_prompt_node()
	if realignment_prompt:
		realignment_prompt.visible = false

func show_controls_help():
	$UI/ControlsHelp.visible = true

func hide_controls_help():
	$UI/ControlsHelp.visible = false
