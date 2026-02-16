extends Node3D

var list_of_players = []

#@onready var _debug_init = turn_off_debug_mode()  # can also be turn_off_debug_mode
@onready var current_map = $World.get_children()[0]
var randomise_start_positions: bool = true
var checkpointed_respawn_point
var obstacle_course_timer

var current_audio_listener_player: Node = null
var all_active_rockets: Array[RigidBody3D] = []
var network_lobby_scene = preload("res://scenes/NetworkLobby.tscn")
var network_lobby_instance = null

# Menu navigation state
var selected_player_count: int = 1

func _ready():
	if GameSettings.should_skip_main_menu:
		hide_main_menu()
		start_game()
	else:
		show_main_menu()

func _process(delta):
	if list_of_players.size() > 1:
		# Update rocket proximity audio listener every frame for now
		update_rocket_proximity_audio_listener()

	if (GameSettings.debug_mode_on) and Input.is_action_just_pressed(str("debug_restart_current_game")):
		# [option + `]
		restart_game()

func show_main_menu():
	get_tree().paused = true
	hide_all_menus()
	$MenuContainer.visible = true
	$MenuContainer/Control/MainMenuContainer.visible = true
	$MenuContainer/Control/MainMenuContainer/VBoxContainer/PlayOnlineButton.grab_focus()

func hide_all_menus():
	$MenuContainer/Control/MainMenuContainer.visible = false
	$MenuContainer/Control/OfflineMenuContainer.visible = false
	$MenuContainer/Control/SinglePlayerMenuContainer.visible = false
	$MenuContainer/Control/PlayerCountMenuContainer.visible = false
	$MenuContainer/Control/ExploreMapsContainer.visible = false
	$MenuContainer/Control/TimeTrialMapsContainer.visible = false
	$MenuContainer/Control/MultiplayerMapsContainer.visible = false
	$MenuContainer/Control/GameOverScreen.visible = false
	$MenuContainer/Control/PauseMenuScreen.visible = false

func hide_main_menu(): 
	$MenuContainer.visible = false
	$MenuContainer/Control/MainMenuContainer.visible = false

func start_game ():
	register_active_players()
	if (current_map.name.begins_with("ObstacleCourse")):
		list_of_players[0].switch_on_obstacle_course_mode()
		setup_obstacle_course_timer()
		MusicManager.start_music(2)
	else:
		list_of_players[0].switch_off_obstacle_course_mode()
		remove_obstacle_course_timer()
		MusicManager.start_music(1)
	assign_spawn_points()
	setup_screens()

	# After split screen setup, configure each player's cameras and signals
	# This ensures cameras are in their final viewport context
	for player in list_of_players:
		# Setup player networking status (will set as local player in offline mode)
		player.setup_network_player()
		
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
	
	# Initialize audio listener system if we're in multiplayer mode
	if GameSettings.desired_number_players > 1:
		update_rocket_proximity_audio_listener()

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

	# In multiplayer mode, start with the rocket proximity audio system
	if GameSettings.desired_number_players > 1:
		# Initialize the rocket proximity audio listener system
		update_rocket_proximity_audio_listener()

func register_active_players():
	# Get all players from PlayerContainer and manage them based on desired player count
	var index = 0
	for player in $PlayerScreenManager/PlayerContainer.get_children():
		if index < GameSettings.desired_number_players:
			list_of_players.append(player)
		else:
			if NetworkManager.is_multiplayer_active():
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
		var winner_name = _get_player_name(alive_players[0].player_number)
		var winner_text = str(winner_name, " wins!")
		show_game_over_menu(winner_text)
	elif alive_players.size() == 0:
		var draw_text = str("DRAW! Everybody died.")
		show_game_over_menu(draw_text)
	
	# Update audio listener based on remaining players and rockets
	if GameSettings.desired_number_players > 1 and alive_players.size() > 0:
		update_rocket_proximity_audio_listener()

func _on_player_lost_a_life(player_number):
	if checkpointed_respawn_point:
		assign_checkpointed_spawn_point_to_player(player_number, checkpointed_respawn_point)
	else:
		assign_new_spawn_point_to_player(player_number)
		# next up: ^ this is causing the camera to go mental and fly away on death.
		
		# Update audio listener system when player respawns
		if GameSettings.desired_number_players > 1:
			# Add a short delay to ensure the player has fully respawned
			var timer = get_tree().create_timer(0.1)
			timer.timeout.connect(update_rocket_proximity_audio_listener)

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
		if is_instance_valid(player): player.pause_inputs()

func restart_game ():
	get_node("/root/DebrisManager").clear_all_debris()
	get_tree().reload_current_scene()

func _on_play_again_button_pressed ():
	if NetworkManager.is_multiplayer_active():
		# In network mode, tell all players to return to lobby
		return_to_lobby_for_all.rpc()
		return
	restart_game()

@rpc("any_peer", "call_local", "reliable")
func return_to_lobby_for_all():
	# All players receive this and reload to return to lobby
	if OS.has_feature("web"):
		JavaScriptBridge.eval("location.reload();")
	else:
		restart_game()

func _on_return_to_main_menu_button_pressed():
	GameSettings.should_skip_main_menu = false
	restart_game()

func toggle_pause_menu():
	if $MenuContainer/Control/PauseMenuScreen.visible:
		hide_pause_menu()
	else:
		show_pause_menu()

func show_pause_menu():
	# Only pause physics in offline mode
	if not NetworkManager.is_multiplayer_active():
		get_tree().paused = true
	
	$MenuContainer.visible = true
	$MenuContainer/Control/PauseMenuScreen.visible = true
	$MenuContainer/Control/PauseMenuScreen/PauseSound.play()
	$MenuContainer/Control/PauseMenuScreen/VBoxContainer/ResumeButton.grab_focus()
	
	# Update pause menu title based on mode
	var title_label = $MenuContainer/Control/PauseMenuScreen/VBoxContainer/EmptySpace
	if NetworkManager.is_multiplayer_active():
		title_label.text = ""

func hide_pause_menu():
	var unpause_sound = $MenuContainer/Control/PauseMenuScreen/UnpauseSound
	unpause_sound.play()
	
	# Only unpause if we paused (offline mode)
	if not NetworkManager.is_multiplayer_active():
		get_tree().paused = false
	
	$MenuContainer.visible = false
	$MenuContainer/Control/PauseMenuScreen.visible = false

func _on_resume_button_pressed():
	hide_pause_menu()

func _on_pause_menu_return_to_main_menu_button_pressed():
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
	if GameSettings.debug_mode_on:
		turn_off_debug_mode()
		$MenuContainer/Control/OfflineMenuContainer/VBoxContainer/DebugToggle.text = "Debug: Off"
	else:
		turn_on_debug_mode()
		$MenuContainer/Control/OfflineMenuContainer/VBoxContainer/DebugToggle.text = "Debug: On"

# New menu navigation functions
func _on_play_online_pressed():
	show_network_lobby()

func _on_play_offline_pressed():
	hide_all_menus()
	$MenuContainer/Control/OfflineMenuContainer.visible = true
	$MenuContainer/Control/OfflineMenuContainer/VBoxContainer/SinglePlayerButton.grab_focus()

func _on_single_player_pressed():
	hide_all_menus()
	$MenuContainer/Control/SinglePlayerMenuContainer.visible = true
	$MenuContainer/Control/SinglePlayerMenuContainer/VBoxContainer/ExploreButton.grab_focus()

func _on_local_multiplayer_pressed():
	hide_all_menus()
	$MenuContainer/Control/PlayerCountMenuContainer.visible = true
	$MenuContainer/Control/PlayerCountMenuContainer/VBoxContainer/TwoPlayerButton.grab_focus()

func _on_offline_back_pressed():
	show_main_menu()

func _on_explore_pressed():
	hide_all_menus()
	$MenuContainer/Control/ExploreMapsContainer.visible = true
	$MenuContainer/Control/ExploreMapsContainer/VBoxContainer/Map1Button.grab_focus()

func _on_time_trials_pressed():
	hide_all_menus()
	$MenuContainer/Control/TimeTrialMapsContainer.visible = true
	$MenuContainer/Control/TimeTrialMapsContainer/VBoxContainer/ObstacleCourse1Button.grab_focus()

func _on_single_player_back_pressed():
	hide_all_menus()
	$MenuContainer/Control/OfflineMenuContainer.visible = true
	$MenuContainer/Control/OfflineMenuContainer/VBoxContainer/SinglePlayerButton.grab_focus()

func _on_player_count_selected(count: int):
	selected_player_count = count
	hide_all_menus()
	$MenuContainer/Control/MultiplayerMapsContainer.visible = true
	$MenuContainer/Control/MultiplayerMapsContainer/VBoxContainer/Map1Button.grab_focus()

func _on_player_count_back_pressed():
	hide_all_menus()
	$MenuContainer/Control/OfflineMenuContainer.visible = true
	$MenuContainer/Control/OfflineMenuContainer/VBoxContainer/MultiplayerButton.grab_focus()

func _on_explore_map_selected(map_name: String):
	$World.load_map_by_name(map_name)
	current_map = $World.current_map_instance
	GameSettings.desired_number_players = 1
	GameSettings.should_skip_main_menu = true
	hide_main_menu()
	start_game()
	get_tree().paused = false

func _on_time_trial_map_selected(map_name: String):
	$World.load_map_by_name(map_name)
	current_map = $World.current_map_instance
	GameSettings.desired_number_players = 1
	GameSettings.should_skip_main_menu = true
	hide_main_menu()
	start_game()
	get_tree().paused = false

func _on_explore_maps_back_pressed():
	hide_all_menus()
	$MenuContainer/Control/SinglePlayerMenuContainer.visible = true
	$MenuContainer/Control/SinglePlayerMenuContainer/VBoxContainer/ExploreButton.grab_focus()

func _on_time_trial_maps_back_pressed():
	hide_all_menus()
	$MenuContainer/Control/SinglePlayerMenuContainer.visible = true
	$MenuContainer/Control/SinglePlayerMenuContainer/VBoxContainer/TimeTrialsButton.grab_focus()

func _on_multiplayer_map_selected(map_name: String):
	$World.load_map_by_name(map_name)
	current_map = $World.current_map_instance
	GameSettings.desired_number_players = selected_player_count
	GameSettings.should_skip_main_menu = true
	hide_main_menu()
	start_game()
	get_tree().paused = false

func _on_multiplayer_maps_back_pressed():
	hide_all_menus()
	$MenuContainer/Control/PlayerCountMenuContainer.visible = true
	$MenuContainer/Control/PlayerCountMenuContainer/VBoxContainer/TwoPlayerButton.grab_focus()

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
		if not is_instance_valid(player) or player.is_eliminated:
			return false
		# In network games, exclude unpopulated players (marked invisible)
		if NetworkManager.is_multiplayer_active() and not player.visible:
			return false
		return true
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

func find_closest_player_to_rockets() -> Node:
	var active_players = get_active_players()
	if active_players.size() == 0:
		return null

	var active_rockets = all_active_rockets.filter(func(rocket):
		return is_instance_valid(rocket)
	)

	if active_rockets.size() == 0:
		return null

	var closest_player = null
	var shortest_distance = INF

	# Check each player against each rocket to find the overall closest
	for player in active_players:
		if not is_instance_valid(player): continue # skip on past invalid instances 

		for rocket in active_rockets:
			var distance_to_rocket = player.global_position.distance_to(rocket.global_position)
			if distance_to_rocket < shortest_distance:
				shortest_distance = distance_to_rocket
				closest_player = player

	return closest_player

func switch_audio_listener_to_player (player: Node):
	if not player or current_audio_listener_player == player:
		return

	# Deactivate all audio listeners first
	if current_audio_listener_player:
		var current_viewport = get_player_subviewport(current_audio_listener_player)
		if current_viewport:
			current_viewport.audio_listener_enable_3d = false

	# Activate the new player's listener
	var new_viewport = get_player_subviewport(player)
	if new_viewport:
		new_viewport.audio_listener_enable_3d = true
		current_audio_listener_player = player

func get_player_subviewport(player: Node) -> SubViewport:
	if not player:
		return null

	var parent = player.get_parent()
	if parent is SubViewport:
		return parent

	# In single player mode, there is no SubViewport
	return null

func update_rocket_proximity_audio_listener():
	var closest_player = find_closest_player_to_rockets()

	if closest_player:
		switch_audio_listener_to_player(closest_player)

func register_rocket_for_audio(rocket: RigidBody3D):
	if not all_active_rockets.has(rocket):
		all_active_rockets.append(rocket)

		if rocket.has_signal("rocket_exploded"):
			rocket.rocket_exploded.connect(_on_rocket_destroyed_audio.bind(rocket))
		if rocket.has_signal("rocket_out_of_bounds"):
			rocket.rocket_out_of_bounds.connect(_on_rocket_out_of_bounds_audio.bind(rocket))

func _on_rocket_destroyed_audio(position: Vector3, rocket: RigidBody3D):
	var timer = get_tree().create_timer(2.0)  # Wait 2 seconds for explosion sound
	await timer.timeout
	if is_instance_valid(rocket):
		remove_rocket_from_audio_tracking(rocket)

func _on_rocket_out_of_bounds_audio(rocket: RigidBody3D):
	remove_rocket_from_audio_tracking(rocket)

func remove_rocket_from_audio_tracking(rocket: RigidBody3D):
	if all_active_rockets.has(rocket):
		all_active_rockets.erase(rocket)

# Network lobby functions
func show_network_lobby():
	network_lobby_instance = network_lobby_scene.instantiate()
	add_child(network_lobby_instance)
	
	# Connect signals
	network_lobby_instance.lobby_closed.connect(_on_network_lobby_closed)
	network_lobby_instance.start_local_game.connect(_on_start_local_game)
	network_lobby_instance.start_network_game.connect(_on_start_network_game)
	
	hide_main_menu()

func _on_network_lobby_closed():
	if network_lobby_instance:
		network_lobby_instance.queue_free()
		network_lobby_instance = null
	show_main_menu()

func _on_start_local_game():
	# Start local multiplayer without networking
	if network_lobby_instance:
		network_lobby_instance.queue_free()
		network_lobby_instance = null
	
	# Ensure network is reset for offline play
	NetworkManager.reset_network_state()
	
	GameSettings.desired_number_players = 2  # Default to 2 players for local
	start_game()
	# Unpause the game (matching behavior from main branch)
	get_tree().paused = false

func _on_start_network_game():
	# Start network multiplayer game
	if network_lobby_instance:
		network_lobby_instance.queue_free()
		network_lobby_instance = null
	
	# Set player count based on connected players
	GameSettings.desired_number_players = NetworkManager.get_player_count()
	start_network_game_session()

func start_network_game_session():
	# Network-aware version of start_game
	register_active_players()
	
	# Skip obstacle course for network games
	for player in list_of_players:
		player.switch_off_obstacle_course_mode()
	remove_obstacle_course_timer()
	MusicManager.start_music(1)
	
	assign_spawn_points()
	setup_network_screens()  # Use network-specific screen setup
	
	# Configure players for networking
	for i in range(list_of_players.size()):
		var player = list_of_players[i]
		player.player_eliminated.connect(_on_player_eliminated)
		player.player_lost_a_life.connect(_on_player_lost_a_life)
		# Only set camera current for local player
		if player.is_local_player:
			player.get_node("ChaseCamPivot/ChaseCam").current = true
			player.notify_chase_cam_of_teleportation()
	
	# Connect to checkpoint manager signals
	connect_checkpoint_signals()
	
	# Setup network puppet spawning for players that join later
	NetworkManager.player_connected.connect(_on_network_player_joined)
	NetworkManager.player_disconnected.connect(_on_network_player_left)
	
	# Unpause the game for network play
	get_tree().paused = false

func setup_network_screens():
	# In network mode, each client gets full screen with only their local player
	# Clean up split screen containers (not needed for network)
	for split_screen in $PlayerScreenManager/SplitScreens.get_children():
		split_screen.queue_free()
	
	# Get the local player data to determine which player number this client controls
	var local_player_data = NetworkManager.get_local_player_data()
	var local_player_number = local_player_data.player_number if local_player_data else 1
	
	await get_tree().create_timer(0.3).timeout
	
	for player in list_of_players:
		player.setup_network_player()
	
	# Find local player and enable their camera
	var local_player
	for player in list_of_players:
		if player.player_number == local_player_number:
			local_player = player
			player.get_node("ChaseCamPivot/ChaseCam").current = true
			player.visible = true
		else:
			# Disable cameras for remote players
			player.get_node("ChaseCamPivot/ChaseCam").current = false
			player.get_node("SideCam").current = false
			player.get_node("FirstPersonCam").current = false
			player.get_node("ThirdPersonCam").current = false
			player.get_node("ChaseCamLocked").current = false
			
			# Hide players that don't have a connected peer yet
			var has_player = false
			for peer_data in NetworkManager.connected_players.values():
				if peer_data.player_number == player.player_number:
					has_player = true
					break
			player.visible = has_player
			# Disable physics and collision for unpopulated players
			# But keep physics enabled for remote players so they can display lasers etc.
			if not has_player:
				player.set_physics_process(false)
				player.collision_layer = 0
				player.collision_mask = 0
				# Stop engine sound for unpopulated players
				if player.has_node("EngineSound"):
					player.get_node("EngineSound").stop()
			else:
				# Remote player exists - ensure physics is enabled

				player.set_physics_process(true)
				player.collision_layer = 1
				player.collision_mask = 1
	
	if not local_player:
		return

	if local_player and $SinglePlayerCamera:
		local_player.connect("hide_crosshair", $SinglePlayerCamera.hide_crosshair)
		local_player.connect("show_crosshair", $SinglePlayerCamera.show_crosshair)
		local_player.connect("needs_realignment", $SinglePlayerCamera.show_realignment_prompt)
		local_player.connect("realignment_resolved", $SinglePlayerCamera.hide_realignment_prompt)
		local_player.connect("show_controls_help", $SinglePlayerCamera.show_controls_help)
		local_player.connect("hide_controls_help", $SinglePlayerCamera.hide_controls_help)

func _on_network_player_joined(peer_id: int):
	if not NetworkManager.is_multiplayer_active():
		return
	
	var player_data = NetworkManager.connected_players.get(peer_id, {})
	var player_number = player_data.get("player_number", -1)
	
	if player_number > 0:
		for player in list_of_players:
			if player.player_number == player_number:
				var network_sync = player.get_node_or_null("NetworkSync")
				if network_sync:
					network_sync.set_multiplayer_authority(peer_id)
					player.setup_network_player()
					player.visible = true  # Show the player when they join
					# Re-enable physics and collision when player joins
					player.set_physics_process(true)
					player.collision_layer = 1
					player.collision_mask = 1
				break

func _on_network_player_left(peer_id: int):
	# A player left during gameplay - remove their puppet
	print("Player ", peer_id, " left the game")
	# TODO: Remove puppet player here when needed

func _get_player_name(player_number: int) -> String:
	# In network mode, get name from NetworkManager
	if NetworkManager.is_multiplayer_active():
		for peer_data in NetworkManager.connected_players.values():
			if peer_data.player_number == player_number:
				return peer_data.name
	# Fallback to "Player X" for offline mode
	return "Player " + str(player_number)
