extends SubViewport

# called from Rootnode programmatically
func connect_crosshair_control_signals ():
	var vehicle = get_children().filter(func(child):
		return child.name.begins_with("PlayerBuggy")
	)[0]

	if vehicle:
		vehicle.connect("hide_crosshair", hide_crosshair)
		vehicle.connect("show_crosshair", show_crosshair)
		vehicle.connect("needs_realignment", show_realignment_prompt)
		vehicle.connect("realignment_resolved", hide_realignment_prompt)
		vehicle.connect("show_controls_help", show_controls_help)
		vehicle.connect("hide_controls_help", hide_controls_help)

func hide_crosshair ():
	$AimingReticle.visible = false

func show_crosshair ():
	$AimingReticle.visible = true

func show_realignment_prompt():
	# Check if mobile controls are enabled - show flip button instead of text
	var mobile_ui = get_tree().root.get_node_or_null("RootNode/MobileTouchUI")
	if mobile_ui and mobile_ui.has_method("are_mobile_controls_enabled") and mobile_ui.are_mobile_controls_enabled():
		if mobile_ui.has_method("show_flip_button"):
			mobile_ui.show_flip_button()
		return

	# Fallback: Show text prompt
	$UI/RealignmentPrompt/Label.text = "[LB] / [E] to realign"
	$UI/RealignmentPrompt.visible = true

func hide_realignment_prompt():
	# Hide both the flip button and text prompt
	var mobile_ui = get_tree().root.get_node_or_null("RootNode/MobileTouchUI")
	if mobile_ui and mobile_ui.has_method("hide_flip_button"):
		mobile_ui.hide_flip_button()

	$UI/RealignmentPrompt.visible = false

func show_controls_help():
	$UI/ControlsHelp.visible = true

func hide_controls_help():
	$UI/ControlsHelp.visible = false
