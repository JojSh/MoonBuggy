extends Node

signal player_connected(peer_id)
signal player_disconnected(peer_id) 
signal connection_failed
signal connection_succeeded
signal server_disconnected

const DEFAULT_PORT = 9001
const MAX_CLIENTS = 3  # Host + 3 clients = 4 players total

var is_hosting: bool = false
var connected_players: Dictionary = {}  # peer_id -> player_data

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host_game(port: int = DEFAULT_PORT) -> bool:
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
		
		print("Server started on port ", port)
		return true
	else:
		print("Failed to start server: ", error)
		return false

func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	
	if error == OK:
		multiplayer.multiplayer_peer = peer
		is_hosting = false
		print("Attempting to connect to ", ip, ":", port)
		return true
	else:
		print("Failed to create client: ", error)
		return false

func disconnect_from_game():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	connected_players.clear()
	is_hosting = false
	print("Disconnected from game")

func reset_network_state():
	# Clean reset of all network state
	disconnect_from_game()
	connected_players.clear()
	is_hosting = false

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
	print("Player connected: ", peer_id)
	
	# Assign player number
	var player_number = get_next_player_number()
	if player_number == -1:
		print("Server full! Disconnecting player ", peer_id)
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
	print("Player disconnected: ", peer_id)
	connected_players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connected_to_server():
	print("Successfully connected to server")
	connection_succeeded.emit()

func _on_connection_failed():
	print("Failed to connect to server")
	connection_failed.emit()

func _on_server_disconnected():
	print("Disconnected from server")
	connected_players.clear()
	server_disconnected.emit()

@rpc("authority", "call_local", "reliable")
func _sync_players_to_new_client(players_data: Dictionary):
	connected_players = players_data
	print("Received player list: ", connected_players)

func is_multiplayer_active() -> bool:
	# Only consider ENetMultiplayerPeer as actual multiplayer
	# OfflineMultiplayerPeer is the default and indicates offline mode
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer is ENetMultiplayerPeer

func is_server() -> bool:
	return multiplayer.is_server()

func get_local_player_data() -> Dictionary:
	var local_id = multiplayer.get_unique_id()
	return connected_players.get(local_id, {})
