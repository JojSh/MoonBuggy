extends Node3D

var list_of_players = []

#@onready var _debug_init = turn_off_debug_mode()  # can also be turn_off_debug_mode
@onready var current_map = $World.get_children()[0]
var randomise_start_positions: bool = true
var checkpointed_respawn_point
var obstacle_course_timer

func _ready():
	if GameSettings.should_skip_main_menu:
		hide_main_menu()
		start_game()
	else:
		show_main_menu()

# Update the audio listener position every frame in multiplayer mode
func _process(delta):
	if list_of_players.size() > 1:
		update_audio_listener_position()

	if (GameSettings.debug_mode_on) and Input.is_action_just_pressed(str("debug_restart_current_game")):
		# [option + `]
		restart_game()

# Function to update the audio listener position to stay equidistant between all active players
func update_audio_listener_position():
	var active_players = get_active_players()
	
	if active_players.size() == 0:
		return
	
	# Calculate the center position between all active players
	var center_position = Vector3.ZERO
	for player in active_players:
		center_position += player.global_position
	
	center_position /= active_players.size()
	
	# Set the audio listener position to the calculated center
	# Add a slight height offset to ensure better audio pickup
	$AudioListener3DBetweenPlayers.global_position = center_position + Vector3(0, 2, 0)
	
	# Make sure the audio listener is active
	$AudioListener3DBetweenPlayers.current = true

func show_main_menu():
	get_tree().paused = true
	$MenuContainer/Control/MainMenuContainer/VBoxContainer/SinglePlayerLocalButton.grab_focus()
	update_map_display_text()

func hide_main_menu(): 
	$MenuContainer.visible = false
	$MenuContainer/Control/MainMenuContainer.visible = false

func start_game ():
	register_active_players()
	if (current_map.name.begins_with("ObstacleCourse")):
		list_of_players[0].switch_on_obstacle_course_mode()
		setup_obstacle_course_timer()
	else:
		list_of_players[0].switch_off_obstacle_course_mode()
		remove_obstacle_course_timer()
	assign_spawn_points()
	setup_screens()
	MusicManager.start_music()

	# After split screen setup, configure each player's cameras and signals
	# This ensures cameras are in their final viewport context
	for player in list_of_players:
		player.player_eliminated.connect(_on_player_eliminated)
		player.player_lost_a_life.connect(_on_player_lost_a_life)
		player.get_node("ChaseCamPivot/ChaseCam").current = true
		player.notify_chase_cam_of_teleportation()

		if GameSettings.desired_number_players == 1:
			player.needs_realignment.connect(_show_single_player_realignment_prompt)
			player.realignment_resolved.connect(_hide_single_player_realignment_prompt)
			player.show_controls_help.connect(_show_single_player_controls_help)
			player.hide_controls_help.connect(_hide_single_player_controls_help)
	
	# Connect to checkpoint manager signals
	connect_checkpoint_signals()
	
	# Initialize audio listener position if we're in multiplayer mode
	if GameSettings.desired_number_players > 1:
		update_audio_listener_position()
		$AudioListener3DBetweenPlayers.current = true

func assign_spawn_points ():
	var all_player_spawn_points = current_map.get_node("PlayerSpawnPositions").get_children()
	if randomise_start_positions:
		all_player_spawn_points.shuffle()

	for player in list_of_players:
		var selected_spawn_point = all_player_spawn_points.pop_front()
		player.set_new_spawn_point(selected_spawn_point)
		player.move_to_spawn_point()
		all_player_spawn_points.push_back(selected_spawn_point)

func connect_checkpoint_signals():
	# Connect to checkpoint manager if current map has one
	if current_map and current_map.has_node("CheckpointManager"):
		var checkpoint_manager = current_map.get_node("CheckpointManager")
		if not checkpoint_manager.level_complete.is_connected(_on_level_complete):
			checkpoint_manager.level_complete.connect(_on_level_complete)
			checkpoint_manager.set_checkpoint_as_respawn_point.connect(_on_set_checkpoint_as_respawn_point)

func setup_screens():
	if GameSettings.desired_number_players == 1:
		# Single player mode - cleanup split screen containers
		for split_screen in $PlayerScreenManager/SplitScreens.get_children():
			split_screen.queue_free()

		$AudioListener3DBetweenPlayers.queue_free()
		var player1 = $PlayerScreenManager/PlayerContainer/PlayerBuggy1
		$PlayerScreenManager/PlayerContainer.remove_child(player1)
		$SinglePlayerCamera.add_child(player1)
		$SinglePlayerCamera.connect_crosshair_control_signals()
		return

	# Get the appropriate grid container for player count
	var grid_container = $PlayerScreenManager/SplitScreens.get_node("GridContainer" + str(GameSettings.desired_number_players) + "P")
	
	# Clean up unused grid containers
	var all_containers = $PlayerScreenManager/SplitScreens.get_children()
	var unused_containers = all_containers.filter(func(container): 
		# Extract the number from the container name (e.g., "GridContainer2P" -> 2)
		var player_count = container.name.replace("GridContainer", "").replace("P", "").to_int()
		return player_count != GameSettings.desired_number_players
	)
	for container in unused_containers: container.queue_free()
	
	# Free the single player camera
	$SinglePlayerCamera.queue_free()
	
	# Move players to their respective viewports
	var viewports = grid_container.get_children()
	
	for i in GameSettings.desired_number_players:
		var viewport_container = viewports[i]
		var player = list_of_players[i]
		var viewport = viewport_container.get_node("SubViewport")

		# Remove player from original parent
		$PlayerScreenManager/PlayerContainer.remove_child(player)
		# Add to new viewport
		viewport.add_child(player)
		viewport.connect_crosshair_control_signals()

	# If in multiplayer mode, make sure the central audio listener is active
	if GameSettings.desired_number_players > 1:
		$AudioListener3DBetweenPlayers.current = true

func register_active_players():
	# Get all players from PlayerContainer and manage them based on desired player count
	var index = 0
	for player in $PlayerScreenManager/PlayerContainer.get_children():
		if index < GameSettings.desired_number_players:
			list_of_players.append(player)
		else:
			player.queue_free()
		index += 1

func _on_portal_entrance_area_3d_body_entered(body, portal_number: int):
	if !(body is VehicleBody3D):
		return

	var exit_node = current_map.get_node("PortalExitArea3D" + str(portal_number))
	var exit_location = exit_node.global_position
	var exit_rotation = exit_node.global_rotation
	body.position = exit_location
	body.rotation = exit_rotation
	body.angular_velocity = Vector3.ZERO
	body.linear_velocity = Vector3.ZERO
	body.notify_chase_cam_of_teleportation()

func _on_player_eliminated(player_number):
	var alive_players = get_active_players()
	
	if alive_players.size() == 1:
		var winner_text = str("Player ", alive_players[0].player_number, " wins!")
		show_game_over_menu(winner_text)
	elif alive_players.size() == 0:
		var draw_text = str("DRAW! Everybody died.")
		show_game_over_menu(draw_text)
	
	# Update audio listener position based on remaining players
	if GameSettings.desired_number_players > 1 and alive_players.size() > 0:
		update_audio_listener_position()

func _on_player_lost_a_life(player_number):
	if checkpointed_respawn_point:
		assign_checkpointed_spawn_point_to_player(player_number, checkpointed_respawn_point)
	else:
		assign_new_spawn_point_to_player(player_number)
		# next up: ^ this is causing the camera to go mental and fly away on death.
		
		# Update audio listener position when player respawns
		if GameSettings.desired_number_players > 1:
			# Add a short delay to ensure the player has fully respawned
			var timer = get_tree().create_timer(0.1)
			timer.timeout.connect(func(): update_audio_listener_position())

func assign_checkpointed_spawn_point_to_player (player_number, checkpoint):
	var current_player = get_current_player(player_number)
	
	# Create a new spawn point entity with the checkpoint's transform
	var spawn_point = Node3D.new()
	spawn_point.transform = checkpoint.transform
	
	# Adjust the spawn point transform if needed
	# Convert degrees to radians for rotation
	spawn_point.rotation.x -= deg_to_rad(90)
	
	current_player.set_new_spawn_point(spawn_point)
	current_player.move_to_spawn_point()

func assign_new_spawn_point_to_player (player_number):
	var all_player_spawn_points = current_map.get_node("PlayerSpawnPositions").get_children()
	var new_spawn_point = all_player_spawn_points.pick_random()
	var current_player = get_current_player(player_number)
	
	current_player.set_new_spawn_point(new_spawn_point)
	current_player.move_to_spawn_point()

func show_game_over_menu (message):
	$MenuContainer/Control/GameOverScreen/VBoxContainer/PlayerWinNotification.text = message
	$MenuContainer.visible = true
	$MenuContainer/Control/GameOverScreen.visible = true
	$MenuContainer/Control/GameOverScreen.grab_button_focus()
	# Pause all remaining players' inputs
	for player in list_of_players:
		if is_instance_valid(player):
			player.pause_inputs()

func restart_game ():
	get_node("/root/DebrisManager").clear_all_debris()
	get_tree().reload_current_scene()

func _on_play_again_button_pressed ():
	restart_game()

func _on_choose_player_count_button_pressed(player_count):
	GameSettings.desired_number_players = player_count
	GameSettings.should_skip_main_menu = true
	hide_main_menu()
	start_game()
	get_tree().paused = false

func _on_return_to_main_menu_button_pressed():
	GameSettings.should_skip_main_menu = false
	restart_game()

func turn_on_debug_mode():
	GameSettings.debug_mode_on = true
	get_tree().call_group("killzones", "update_debug_visibility")
	# Instantiate FPS Display
	const FPSDisplay = preload("res://scenes/FPSDisplay.tscn")
	var fps_display = FPSDisplay.instantiate()
	add_child(fps_display)

func turn_off_debug_mode():
	GameSettings.debug_mode_on = false
	get_tree().call_group("killzones", "update_debug_visibility")
	# Remove FPS Display if it exists
	var fps_display = get_node_or_null("FPSDisplay")
	if fps_display:
		fps_display.queue_free()

func _on_debug_toggle_pressed():
	if (GameSettings.debug_mode_on):
		turn_off_debug_mode()
	else:
		turn_on_debug_mode()

func _on_change_map_pressed():
	$World.cycle_to_next_map()
	
	# Reset player positions on the new map
	assign_spawn_points()

	update_map_display_text()

func update_map_display_text():
	#var current_player = get_current_player(1)
	if (current_map.name.begins_with("ObstacleCourse")):
		hide_multiplayer_options()
	else:
		unhide_multiplayer_options()
	$MenuContainer/Control/MainMenuContainer/VBoxContainer/ChangeMap.text = "Change map: " + current_map.name + " "

func hide_multiplayer_options ():
	var twoPlayerButton = $MenuContainer/Control/MainMenuContainer/VBoxContainer/TwoPlayerSplitScreenButton
	var threePlayerButton = $MenuContainer/Control/MainMenuContainer/VBoxContainer/ThreePlayerSplitScreenButton
	var fourPlayerButton = $MenuContainer/Control/MainMenuContainer/VBoxContainer/FourPlayerSplitScreenButton

	for button in [twoPlayerButton, threePlayerButton, fourPlayerButton]:
		button.visible = false

func unhide_multiplayer_options ():
	var twoPlayerButton = $MenuContainer/Control/MainMenuContainer/VBoxContainer/TwoPlayerSplitScreenButton
	var threePlayerButton = $MenuContainer/Control/MainMenuContainer/VBoxContainer/ThreePlayerSplitScreenButton
	var fourPlayerButton = $MenuContainer/Control/MainMenuContainer/VBoxContainer/FourPlayerSplitScreenButton

	for button in [twoPlayerButton, threePlayerButton, fourPlayerButton]:
		button.visible = true

func _on_level_complete():
	# Stop the timer if it's running
	if obstacle_course_timer:
		obstacle_course_timer.stop_timer()
		var completion_time = obstacle_course_timer.get_completion_time()
		show_game_over_menu("Level Complete!\nTime: " + completion_time)
	else:
		show_game_over_menu("Level Complete!")
	# Pause all players' inputs
	for player in list_of_players:
		if is_instance_valid(player):
			player.pause_inputs()

func _on_set_checkpoint_as_respawn_point (point):
	var player_1 = list_of_players[0]
	checkpointed_respawn_point = point

func get_current_player (player_number):
	var current_player = list_of_players.filter(func(p): 
		return p.player_number == player_number
	)[0]
	
	return current_player

func get_active_players ():
	var active_players = list_of_players.filter(func(player):
		return is_instance_valid(player) and not player.is_dead
	)

	return active_players

func setup_obstacle_course_timer():
	# Load and instantiate the timer
	const ObstacleCourseTimer = preload("res://scenes/ObstacleCourseTimer.tscn")
	obstacle_course_timer = ObstacleCourseTimer.instantiate()
	add_child(obstacle_course_timer)
	
	# Start the timer when the game begins
	obstacle_course_timer.start_timer()

func remove_obstacle_course_timer():
	if obstacle_course_timer:
		obstacle_course_timer.queue_free()
		obstacle_course_timer = null

func _show_single_player_realignment_prompt():
	$SinglePlayerUI/RealignmentPrompt.visible = true

func _hide_single_player_realignment_prompt():
	$SinglePlayerUI/RealignmentPrompt.visible = false

func _show_single_player_controls_help():
	$SinglePlayerUI/ControlsHelp.visible = true

func _hide_single_player_controls_help():
	$SinglePlayerUI/ControlsHelp.visible = false
