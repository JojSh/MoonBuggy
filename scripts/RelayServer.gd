extends Node

# Minimal WebSocket relay server using Godot's high-level multiplayer
# One shared room per server instance (simple and works for web)

const PORT := 9080
const MAX_CLIENTS = 3

var connected_players: Dictionary = {}  # peer_id -> player_data

func _ready():
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(PORT)
	if err != OK:
		printerr("Failed to start relay server on port ", PORT, ": ", err)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print("Relay server listening on ws://0.0.0.0:", PORT)
	print("Server is peer ID 1 and manages player connections")
	
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(id: int):
	print("Player ", id, " connected to relay")
	
	# Assign player number
	var player_number = _get_next_player_number()
	if player_number == -1:
		print("Max players reached, disconnecting ", id)
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	
	# Store player data on server
	connected_players[id] = {
		"peer_id": id,
		"player_number": player_number,
		"name": "Player " + str(player_number)
	}
	
	print("Assigned player number ", player_number, " to peer ", id)
	# Note: Clients handle their own peer announcements via _announce_player RPC

func _on_peer_disconnected(id: int):
	print("Player ", id, " disconnected from relay")
	connected_players.erase(id)

func _get_next_player_number() -> int:
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
