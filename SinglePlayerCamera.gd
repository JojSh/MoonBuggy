extends Camera3D

# called from Rootnode programmatically
func connect_crosshair_control_signals ():
	var p1_vehicle = get_children().filter(func(child):
		return child.name.begins_with("PlayerBuggy")
	)[0]

	if p1_vehicle:
		p1_vehicle.connect("hide_crosshair", hide_crosshair)
		p1_vehicle.connect("show_crosshair", show_crosshair)

func hide_crosshair ():
	$AimingReticle.visible = false

func show_crosshair ():
	$AimingReticle.visible = true
