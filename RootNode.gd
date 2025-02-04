extends Node3D

var list_of_players = []
@export var desired_number_players: int = 1

func _ready():
	register_active_players()
	setup_split_screen()

	for player in list_of_players:
		# Connect elimination signal from each player
		player.player_eliminated.connect(_on_player_eliminated)

func setup_split_screen():
	if desired_number_players == 1:
		# Single player mode - cleanup split screen containers
		for split_screen in $PlayerScreenManager/SplitScreens.get_children():
			split_screen.queue_free()

		$AudioListener3DBetweenPlayers.queue_free()
		return
		
	# Get the appropriate grid container for player count
	var grid_container = $PlayerScreenManager/SplitScreens.get_node("GridContainer" + str(desired_number_players) + "P")
	
	# Clean up unused grid containers
	var all_containers = $PlayerScreenManager/SplitScreens.get_children()
	var unused_containers = all_containers.filter(func(container): 
		# Extract the number from the container name (e.g., "GridContainer2P" -> 2)
		var player_count = container.name.replace("GridContainer", "").replace("P", "").to_int()
		return player_count != desired_number_players
	)
	for container in unused_containers: container.queue_free()
	
	# Free the single player camera
	$Camera3D.queue_free()
	
	# Move players to their respective viewports
	var viewports = grid_container.get_children()
	
	for i in desired_number_players:
		var viewport_container = viewports[i]
		var player = list_of_players[i]
		var viewport = viewport_container.get_node("SubViewport")
		
		# Remove player from original parent
		$PlayerScreenManager/PlayerContainer.remove_child(player)
		# Add to new viewport
		viewport.add_child(player)

func register_active_players():
	# Get all players from PlayerContainer and manage them based on desired player count
	var index = 0
	for player in $PlayerScreenManager/PlayerContainer.get_children():
		if index < desired_number_players:
			list_of_players.append(player)
		else:
			player.queue_free()
		index += 1

func _on_portal_entrance_area_3d_body_entered(body, portal_number: int):
	if !(body is VehicleBody3D):
		return

	var exit_location = get_node("PortalExitArea3D" + str(portal_number)).global_position
	body.position = exit_location
	body.rotation = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO

func _on_player_eliminated(player_number):
	var alive_players = list_of_players.filter(func(player):
		return is_instance_valid(player) and player.is_dead == false
	)
	
	if alive_players.size() == 1:
		var winner_text = str("Player ", alive_players[0].player_number, " wins!")
		print(winner_text)
		$MenuContainer/Control/GameOverScreen/VBoxContainer/PlayerWinNotification.text = winner_text
		$MenuContainer.visible = true
		$MenuContainer/Control/GameOverScreen.visible = true
		$MenuContainer/Control/GameOverScreen.grab_button_focus()

		# Pause all remaining players' inputs
		for player in list_of_players:
			if is_instance_valid(player):
				player.pause_inputs()
		
		# End the game
		# Handle victory
	elif alive_players.size() == 0:
		print("Game Over - All players eliminated!")
		# End the game
		# Handle draw scenario

func restart_game ():
	get_node("/root/DebrisManager").clear_all_debris()
	get_tree().reload_current_scene()

func _on_play_again_button_pressed ():
	get_node("/root/DebrisManager").clear_all_debris()
	get_tree().reload_current_scene()
