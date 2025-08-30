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
	# Always show "Press LB to realign" regardless of player
	$UI/RealignmentPrompt/Label.text = "Press [LB] to realign"
	$UI/RealignmentPrompt.visible = true

func hide_realignment_prompt():
	$UI/RealignmentPrompt.visible = false

func show_controls_help():
	$UI/ControlsHelp.visible = true

func hide_controls_help():
	$UI/ControlsHelp.visible = false
