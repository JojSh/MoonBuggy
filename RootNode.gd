extends Node3D

var list_of_players = []
var multiplayer_split_screen : bool = false

func _ready():
	add_players_to_list()

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
	print("body is VehicleBody3D")

	var exit_location = get_node("PortalExitArea3D" + str(portal_number)).global_position
	body.position = exit_location
	body.rotation = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO
	body.update_new_center_of_gravity_point(Vector3.ZERO)
