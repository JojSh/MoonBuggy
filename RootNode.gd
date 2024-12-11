extends Node3D

var list_of_players = []

func _ready():
	for sub_viewport_container in $GridContainer.get_children():
		var sub_viewport = sub_viewport_container.get_node("SubViewport")
		var player = sub_viewport.get_node("PlayerBuggy")

		list_of_players.append(player)

func _process(_delta):
	if list_of_players.size() == 0:
		print("Warning: No players found!")
		return
		
	var central_point_between_players = Vector3.ZERO
	for player in list_of_players:
		central_point_between_players += player.global_position
	central_point_between_players /= list_of_players.size()
	
	$AudioListener3DBetweenPlayers.global_position = central_point_between_players
