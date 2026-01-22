extends Control

@onready var name_container = $VBoxContainer/NameContainer
@onready var name_input = $VBoxContainer/NameContainer/NameInput
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
	NetworkManager.player_data_updated.connect(_on_player_data_updated)

	# Auto-connect to relay
	back_button.grab_focus()
	_auto_connect()

func _auto_connect():
	status_label.text = "Connecting to server..."

	# Try to join the default relay
	if NetworkManager.join_game(""):
		# Connection attempt started
		pass
	else:
		status_label.text = "Failed to connect! Check your internet."

func _on_start_game_button_pressed():
	# Update local player name one more time before starting
	_update_local_player_name()

	if NetworkManager.is_server():
		start_network_game_for_all.rpc()
	elif NetworkManager.is_webrtc_mode():
		# In WebRTC mode, just start locally - no RPC coordination needed
		emit_signal("start_network_game")
	else:
		status_label.text = "Only the host can start the game"

func _on_name_input_text_changed(_new_text: String):
	_update_local_player_name()

func _update_local_player_name():
	var player_name = name_input.text.strip_edges()
	if player_name.is_empty():
		return

	var local_data = NetworkManager.get_local_player_data()
	if local_data and local_data.has("peer_id"):
		NetworkManager.set_player_name(local_data.peer_id, player_name)

@rpc("any_peer", "call_local", "reliable")
func start_network_game_for_all():
	# Update names before starting for all players
	_update_local_player_name()
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
	status_label.text = player_name + " joined!"

	# When a new player joins, update our own name to sync it to the new player
	_update_local_player_name()

func _on_player_disconnected(peer_id: int):
	remove_player_from_list(peer_id)
	status_label.text = "A player left the game"

func _on_connection_succeeded():
	status_label.text = "Connected! Enter your name and click Play."

	# Show name input now that we're connected
	name_container.visible = true
	name_input.grab_focus()

	# Wait briefly for player data to sync, then refresh the full player list
	await get_tree().create_timer(0.5).timeout
	refresh_players_list()

	# Refresh again after another delay to catch any late updates
	await get_tree().create_timer(0.3).timeout
	refresh_players_list()

	# Set NetworkSync authority immediately to prevent sync errors during lobby
	_set_initial_network_authority()

	# Update UI to enable start button
	update_ui()

func _set_initial_network_authority():
	var root = get_tree().root.get_node("RootNode")
	if not root:
		return

	var player_container = root.get_node_or_null("PlayerScreenManager/PlayerContainer")
	if not player_container:
		return

	var local_player_data = NetworkManager.get_local_player_data()
	if not local_player_data:
		return

	for child in player_container.get_children():
		_assign_initial_network_authority(child, local_player_data)

func _assign_initial_network_authority(player, local_player_data):
	var my_player_number = local_player_data.player_number
	var network_sync_node = player.get_node_or_null("NetworkSync")
	if player.name.begins_with("PlayerBuggy") and network_sync_node:
		if player.player_number == my_player_number: # it's a local player
			network_sync_node.set_multiplayer_authority(local_player_data.peer_id)
		else: # remote player's puppet
			for peer_data in NetworkManager.connected_players.values():
				if peer_data.player_number == player.player_number:
					network_sync_node.set_multiplayer_authority(peer_data.peer_id)
					break

func _on_connection_failed():
	status_label.text = "Failed to connect to server!"
	start_game_button.disabled = true

func _on_server_disconnected():
	status_label.text = "Disconnected from server"
	clear_players_list()
	name_container.visible = false
	start_game_button.disabled = true

func _on_player_data_updated():
	# Refresh the entire player list with updated names
	refresh_players_list()

func add_player_to_list(peer_id: int, name: String):
	var player_label = Label.new()
	player_label.name = "Player_" + str(peer_id)
	player_label.text = "• " + name
	player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_label.add_theme_font_size_override("font_size", 32)
	players_container.add_child(player_label)

func remove_player_from_list(peer_id: int):
	var player_node = players_container.get_node_or_null("Player_" + str(peer_id))
	if player_node:
		player_node.queue_free()

func clear_players_list():
	for child in players_container.get_children():
		child.queue_free()

func refresh_players_list():
	clear_players_list()
	var local_id = multiplayer.get_unique_id()
	for peer_data in NetworkManager.connected_players.values():
		var display_name = peer_data.name
		if peer_data.peer_id == local_id:
			display_name += " (You)"
		add_player_to_list(peer_data.peer_id, display_name)

func update_ui():
	# Update UI state based on current network status
	if NetworkManager.is_multiplayer_active():
		if NetworkManager.is_server():
			status_label.text = "Hosting - Waiting for players"
			start_game_button.disabled = false
		else:
			if NetworkManager.is_webrtc_mode():
				status_label.text = "Connected! Enter your name and click Play."
				start_game_button.disabled = false
				start_game_button.grab_focus()
			else:
				status_label.text = "Connected - Waiting for host to start"
				start_game_button.disabled = true
	else:
		status_label.text = "Connecting..."
		start_game_button.disabled = true
