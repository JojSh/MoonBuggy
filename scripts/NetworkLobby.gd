extends Control

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinContainer/JoinButton
@onready var ip_input = $VBoxContainer/JoinContainer/IPInput
@onready var local_mode_button = $VBoxContainer/LocalModeButton
@onready var status_label = $VBoxContainer/StatusLabel
@onready var players_container = $VBoxContainer/PlayersList/PlayersContainer
@onready var start_game_button = $VBoxContainer/StartGameButton
@onready var back_button = $VBoxContainer/BackButton

signal lobby_closed
signal start_local_game
signal start_network_game

func _ready():
	# CRITICAL: Set process mode to work when paused
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	
	# Reset network state when opening lobby
	NetworkManager.reset_network_state()
	clear_players_list()
	
	# Connect NetworkManager signals
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	
	# Connect button signals (only if not already connected)
	if not host_button.pressed.is_connected(_on_host_button_pressed):
		host_button.pressed.connect(_on_host_button_pressed)
	if not join_button.pressed.is_connected(_on_join_button_pressed):
		join_button.pressed.connect(_on_join_button_pressed)
	if not local_mode_button.pressed.is_connected(_on_local_mode_button_pressed):
		local_mode_button.pressed.connect(_on_local_mode_button_pressed)
	if not back_button.pressed.is_connected(_on_back_button_pressed):
		back_button.pressed.connect(_on_back_button_pressed)
	
	# Setup UI
	host_button.grab_focus()
	update_ui()

func _on_host_button_pressed():
	status_label.text = "Starting server..."
	
	if NetworkManager.host_game():
		status_label.text = "Hosting game on port " + str(NetworkManager.DEFAULT_PORT)
		host_button.disabled = true
		join_button.disabled = true
		local_mode_button.disabled = true
		start_game_button.disabled = false
		start_game_button.grab_focus()
		
		# Add host to players list
		add_player_to_list(1, "Host (You)")
	else:
		status_label.text = "Failed to start server!"

func _on_join_button_pressed():
	var ip = ip_input.text.strip_edges()
	
	if ip.is_empty():
		status_label.text = "Please enter server IP address"
		return
	
	status_label.text = "Connecting to " + ip + "..."
	
	if NetworkManager.join_game(ip):
		host_button.disabled = true
		join_button.disabled = true
		local_mode_button.disabled = true
	else:
		print("join_game returned false - connection failed")  # Debug
		status_label.text = "Failed to connect!"

func _on_local_mode_button_pressed():
	# Skip networking, go directly to local multiplayer
	emit_signal("start_local_game")

func _on_start_game_button_pressed():
	if NetworkManager.is_server():
		# Host starts the game for everyone
		print("Host starting network game for all players")
		start_network_game_for_all.rpc()  # This will call the RPC on all clients INCLUDING host
	else:
		status_label.text = "Only the host can start the game"

@rpc("authority", "call_local", "reliable")
func start_network_game_for_all():
	# This is called on all clients (including host) to start the game
	print("Received start game signal from host")
	emit_signal("start_network_game")

func _on_back_button_pressed():
	# Disconnect if connected
	if NetworkManager.is_multiplayer_active():
		NetworkManager.disconnect_from_game()
	
	emit_signal("lobby_closed")

func _on_player_connected(peer_id: int):
	var player_data = NetworkManager.connected_players.get(peer_id, {})
	var player_name = player_data.get("name", "Player " + str(peer_id))
	
	add_player_to_list(peer_id, player_name)
	status_label.text = player_name + " joined the game"

func _on_player_disconnected(peer_id: int):
	remove_player_from_list(peer_id)
	status_label.text = "Player " + str(peer_id) + " left the game"

func _on_connection_succeeded():
	status_label.text = "Connected to server!"
	
	# Add local player to list
	var local_data = NetworkManager.get_local_player_data()
	if local_data:
		add_player_to_list(local_data.peer_id, local_data.name + " (You)")

func _on_connection_failed():
	status_label.text = "Failed to connect to server!"
	reset_ui()

func _on_server_disconnected():
	status_label.text = "Disconnected from server"
	clear_players_list()
	reset_ui()

func add_player_to_list(peer_id: int, name: String):
	var player_label = Label.new()
	player_label.name = "Player_" + str(peer_id)
	player_label.text = "• " + name
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_container.add_child(player_label)

func remove_player_from_list(peer_id: int):
	var player_node = players_container.get_node_or_null("Player_" + str(peer_id))
	if player_node:
		player_node.queue_free()

func clear_players_list():
	for child in players_container.get_children():
		child.queue_free()

func reset_ui():
	host_button.disabled = false
	join_button.disabled = false
	local_mode_button.disabled = false
	start_game_button.disabled = true
	host_button.grab_focus()

func update_ui():
	# Update UI state based on current network status
	if NetworkManager.is_multiplayer_active():
		if NetworkManager.is_server():
			status_label.text = "Hosting - Waiting for players"
			start_game_button.disabled = false
		else:
			status_label.text = "Connected - Waiting for host to start"
			start_game_button.disabled = true
	else:
		status_label.text = "Ready to connect..."
		start_game_button.disabled = true
