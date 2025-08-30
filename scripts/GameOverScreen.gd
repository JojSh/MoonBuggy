extends MarginContainer
@onready var play_again_button = $VBoxContainer/PlayAgainButton

func grab_button_focus ():
	play_again_button.grab_focus()
