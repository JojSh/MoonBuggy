extends Control

@onready var status_label = $VBoxContainer/StatusLabel

func _on_test_button_pressed():
	status_label.text = "Button works!"
	
	if NetworkManager:
		status_label.text = "NetworkManager found!"
		
		if NetworkManager.host_game():
			status_label.text = "Server started!"
		else:
			status_label.text = "Server failed!"
	else:
		status_label.text = "NetworkManager missing!"
