extends Node

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal connection_failed
signal connection_succeeded
signal server_disconnected
signal player_data_updated()

# ENet configuration
const DEFAULT_PORT = 9001
const MAX_CLIENTS = 3  # Host + 3 clients = 4 players total

# Relay (WebSocket) configuration
#const DEFAULT_RELAY_URL = "ws://localhost:9080"
const DEFAULT_RELAY_URL = "wss://semidomesticated-verona-oozily.ngrok-free.dev" # should be updated if relay ngrok address changes

var is_hosting: bool = false
var connected_players: Dictionary = {}  # peer_id -> player_data
var current_network_mode: GameSettings.NetworkMode
var pending_player_name: String = ""  # Stored before connection completes

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Store current network mode
	current_network_mode = GameSettings.network_mode

func host_game(port: int = DEFAULT_PORT) -> bool:
	if current_network_mode == GameSettings.NetworkMode.ENET:
		return _host_game_enet(port)
	else:
		# Hosting is handled by the relay server for web builds
		printerr("Web mode uses a dedicated relay server; clients cannot host.")
		return false

func _host_game_enet(port: int) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_hosting = true
		
		# Host is always player 1 (server ID is always 1 in Godot)
		connected_players[1] = {
			"peer_id": 1,
			"player_number": 1,
			"name": "Host"
		}
		
		print("ENet server started on port ", port)
		return true
	else:
		printerr("Failed to start ENet server: ", error)
		return false


func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	if current_network_mode == GameSettings.NetworkMode.ENET:
		return _join_game_enet(address, port)
	else:
		return _join_game_relay(address)

func _join_game_enet(ip: String, port: int) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_hosting = false
		print("Connecting to ENet server at ", ip, ":", port)
		return true
	else:
		printerr("Failed to connect to ENet server: ", error)
		return false

func _join_game_relay(server_url_or_empty: String) -> bool:
	var url := server_url_or_empty.strip_edges()
	if url.is_empty():
		url = DEFAULT_RELAY_URL
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		is_hosting = false
		print("Connecting to relay ", url)
		return true
	else:
		printerr("Failed to connect to relay: ", err)
		return false

func disconnect_from_game():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	connected_players.clear()
	is_hosting = false

func reset_network_state():
	# Clean reset of all network state
	disconnect_from_game()
	connected_players.clear()
	is_hosting = false
	# Reload network mode from settings
	current_network_mode = GameSettings.network_mode

func get_player_count() -> int:
	return connected_players.size()

func get_next_player_number() -> int:
	# Find the lowest available player number (1-4)
	for i in range(1, 5):
		var number_taken = false
		for player_data in connected_players.values():
			if player_data.player_number == i:
				number_taken = true
				break
		if not number_taken:
			return i
	return -1  # No slots available

func _on_player_connected(peer_id: int):
	if peer_id == 1 and is_webrtc_mode():
		return
		
	# Assign player number
	var player_number = get_next_player_number()
	if player_number == -1:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	
	# Store player data
	connected_players[peer_id] = {
		"peer_id": peer_id,
		"player_number": player_number,
		"name": "Player " + str(player_number)
	}
	
	# Notify game manager
	player_connected.emit(peer_id)
	
	# Sync existing players to new player
	if is_hosting:
		_sync_players_to_new_client.rpc_id(peer_id, connected_players)

func _on_player_disconnected(peer_id: int):
	connected_players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server():
	var my_id = multiplayer.get_unique_id()

	# Send our name to the server (ENet mode)
	if not is_webrtc_mode():
		var player_name = pending_player_name if not pending_player_name.is_empty() else ""
		_register_client_name.rpc_id(1, player_name)

	# WebRTC: register ourselves
	if is_webrtc_mode():
		# IMPORTANT: Don't do anything if we're somehow the relay server
		if my_id == 1:
			return

		# CRITICAL: Wait briefly for existing player announcements to arrive
		# Otherwise we might pick an already-taken player number
		await get_tree().create_timer(0.2).timeout

		var player_number = _get_next_available_player_number()
		var player_name = pending_player_name if not pending_player_name.is_empty() else "Player " + str(player_number)
		connected_players[my_id] = {
			"peer_id": my_id,
			"player_number": player_number,
			"name": player_name
		}
		# Broadcast our info to all other clients (relay will ignore it)
		_announce_player.rpc(my_id, player_number, player_name)

	connection_succeeded.emit()

func _get_next_available_player_number() -> int:
	# Find lowest available player number locally
	for i in range(1, 5):
		var taken = false
		for player_data in connected_players.values():
			if player_data.player_number == i:
				taken = true
				break
		if not taken:
			return i
	return 1  # Fallback

func _on_connection_failed():
	connection_failed.emit()

func _on_server_disconnected():
	connected_players.clear()
	server_disconnected.emit()

@rpc("authority", "call_local", "reliable")
func _sync_players_to_new_client(players_data: Dictionary):
	connected_players = players_data
	player_data_updated.emit()

@rpc("any_peer", "call_remote", "reliable")
func _announce_player(peer_id: int, player_number: int, player_name: String = ""):
	var my_id = multiplayer.get_unique_id()

	if my_id == 1 or peer_id == 1:
		return

	if not connected_players.has(peer_id):
		var final_name = player_name if not player_name.is_empty() else "Player " + str(player_number)
		connected_players[peer_id] = {
			"peer_id": peer_id,
			"player_number": player_number,
			"name": final_name
		}
		player_connected.emit(peer_id)

func is_multiplayer_active() -> bool:
	# Check if multiplayer is active (ENet or WebRTC)
	# OfflineMultiplayerPeer is the default and indicates offline mode
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer or multiplayer.multiplayer_peer is WebSocketMultiplayerPeer

func is_server() -> bool:
	return multiplayer.is_server()

func get_local_player_data() -> Dictionary:
	var local_id = multiplayer.get_unique_id()
	return connected_players.get(local_id, {})

# Set a player's name
func set_player_name(peer_id: int, player_name: String):
	if connected_players.has(peer_id):
		connected_players[peer_id]["name"] = player_name
		# Emit local update
		player_data_updated.emit()
		# Broadcast name change to all peers
		if is_multiplayer_active():
			_sync_player_name.rpc(peer_id, player_name)

@rpc("any_peer", "call_remote", "reliable")
func _sync_player_name(peer_id: int, player_name: String):
	if connected_players.has(peer_id):
		connected_players[peer_id]["name"] = player_name
		player_data_updated.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register_client_name(client_name: String):
	var peer_id = multiplayer.get_remote_sender_id()
	if connected_players.has(peer_id):
		if not client_name.is_empty():
			connected_players[peer_id]["name"] = client_name
		# Sync updated player data to ALL clients
		for other_peer_id in connected_players.keys():
			_sync_players_to_new_client.rpc_id(other_peer_id, connected_players)

# Check if current mode is Web (relay)
func is_webrtc_mode() -> bool:
	return current_network_mode == GameSettings.NetworkMode.WEBRTC
