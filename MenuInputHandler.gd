extends CanvasLayer

func _process(delta):
	# Only handle menu input when this container is visible
	if visible and Input.is_action_just_pressed("any_player_choose_menu_item"):
		var focused_button = get_viewport().gui_get_focus_owner()
		if focused_button and focused_button is Button:
			focused_button.pressed.emit()
