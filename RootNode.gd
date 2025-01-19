extends Node3D

var list_of_players = []
var multiplayer_split_screen : bool = true

func _ready():
	add_players_to_list()
	# Connect elimination signal from each player
	for player in list_of_players:
		player.player_eliminated.connect(_on_player_eliminated)

func _process(_delta):
	if !multiplayer_split_screen: return
	if list_of_players.size() == 0:
		print("Warning: No players found!")
		return
		
	var central_point_between_players = Vector3.ZERO
	for player in list_of_players:
		central_point_between_players += player.global_position
	central_point_between_players /= list_of_players.size()
	
	$AudioListener3DBetweenPlayers.global_position = central_point_between_players

func add_players_to_list ():
	if multiplayer_split_screen:
		for sub_viewport_container in $SplitScreenGridContainer.get_children():
			var sub_viewport = sub_viewport_container.get_node("SubViewport")
			var player = sub_viewport.get_node("PlayerBuggy")
			list_of_players.append(player)

	else:
		$SplitScreenGridContainer.queue_free()
		$AudioListener3DBetweenPlayers.queue_free()
		for player in $PlayerContainer.get_children():
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
		print("Player ", alive_players[0].player_number, " wins!")
		# End the game
		# Handle victory
	elif alive_players.size() == 0:
		print("Game Over - All players eliminated!")
		# End the game
		# Handle draw scenario
