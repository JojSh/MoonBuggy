extends Control

@onready var status_label = $VBoxContainer/StatusLabel

func _ready():
	print("NetworkTest ready!")

func _on_test_button_pressed():
	print("Test button clicked!")
	status_label.text = "Button works!"
	
	if NetworkManager:
		print("NetworkManager exists")
		status_label.text = "NetworkManager found!"
		
		if NetworkManager.host_game():
			status_label.text = "Server started!"
		else:
			status_label.text = "Server failed!"
	else:
		print("NetworkManager not found!")
		status_label.text = "NetworkManager missing!"
