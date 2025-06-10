extends SubViewport

# called from Rootnode programmatically
func connect_crosshair_control_signals ():
	var vehicle = get_children().filter(func(child):
		return child.name.begins_with("PlayerBuggy")
	)[0]

	if vehicle:
		vehicle.connect("hide_crosshair", hide_crosshair)
		vehicle.connect("show_crosshair", show_crosshair)

func hide_crosshair ():
	$AimingReticle.visible = false

func show_crosshair ():
	$AimingReticle.visible = true
