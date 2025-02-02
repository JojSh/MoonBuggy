extends Node3D

var list_of_players = []
@export var desired_number_players: int = 1

func _ready():
	add_players_to_list()
	setup_split_screen()

	for player in list_of_players:
		# Connect elimination signal from each player
		player.player_eliminated.connect(_on_player_eliminated)

func setup_split_screen():
	if desired_number_players == 1:
		# Single player mode - cleanup split screen containers
		$SplitScreenGridContainer2P.queue_free()
		$SplitScreenGridContainer3P.queue_free()
		$SplitScreenGridContainer4P.queue_free()
		$AudioListener3DBetweenPlayers.queue_free()
		
		# Remove all players except the first one
		var players = $PlayerContainer.get_children()
		for i in range(1, players.size()):
			players[i].queue_free()
		
		return
		
	# Get the appropriate grid container for player count
	var grid_container = get_node("SplitScreenGridContainer" + str(desired_number_players) + "P")
	
	# Clean up unused grid containers
	for i in range(2, 5):  # handles 2P, 3P, and 4P containers
		if i != desired_number_players:
			get_node("SplitScreenGridContainer" + str(i) + "P").queue_free()
	
	# Free the single player camera
	$Camera3D.queue_free()
	
	# Move players to their respective viewports
	var players = $PlayerContainer.get_children()
	var viewports = grid_container.get_children()
	
	for i in range(min(players.size(), desired_number_players)):
		var player = players[i]
		var viewport_container = viewports[i]
		var viewport = viewport_container.get_node("SubViewport")
		
		# Remove player from original parent
		$PlayerContainer.remove_child(player)
		# Add to new viewport
		viewport.add_child(player)

func add_players_to_list():
	# Get all players from PlayerContainer before they're moved
	for player in $PlayerContainer.get_children():
		list_of_players.append(player)

func get_players_from_sub_viewport_container (sub_viewport_container):
	var sub_viewport = sub_viewport_container.get_node("SubViewport")
	var player = sub_viewport.get_node("PlayerBuggy")
	list_of_players.append(player)

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
