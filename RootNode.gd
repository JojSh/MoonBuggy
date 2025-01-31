extends Node3D

var list_of_players = []
@export var desired_number_players: int = 1

func _ready():
	add_players_to_list()
	# Connect elimination signal from each player
	for player in list_of_players:
		player.player_eliminated.connect(_on_player_eliminated)

func _process(_delta):
	if desired_number_players == 1: return
	if list_of_players.size() == 0:
		print("Warning: No players found!")
		return
		
	var central_point_between_players = Vector3.ZERO
	for player in list_of_players:
		central_point_between_players += player.global_position
	central_point_between_players /= list_of_players.size()
	
	$AudioListener3DBetweenPlayers.global_position = central_point_between_players

func add_players_to_list ():
	if desired_number_players == 2:
		for sub_viewport_container in $SplitScreenGridContainer2P.get_children():
			get_players_from_sub_viewport_container(sub_viewport_container)
			$SplitScreenGridContainer4P.queue_free()
			$Camera3D.queue_free()
	elif desired_number_players == 4:
		for sub_viewport_container in $SplitScreenGridContainer4P.get_children():
			get_players_from_sub_viewport_container(sub_viewport_container)
			$SplitScreenGridContainer2P.queue_free()
			$Camera3D.queue_free()
	else:
		$SplitScreenGridContainer2P.queue_free()
		$SplitScreenGridContainer4P.queue_free()
		$AudioListener3DBetweenPlayers.queue_free()
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
		return player.is_dead == false
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
