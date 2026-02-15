extends Node

# WebSocket relay server for MoonBuggy multiplayer
# Deployed on Fly.io at wss://moonbuggy-relay.fly.dev

const PORT := 9080
const MAX_CLIENTS = 3

var connected_players: Dictionary = {}  # peer_id -> player_data

func _ready():
	var peer := WebSocketMultiplayerPeer.new()
	var err = peer.create_server(PORT, "0.0.0.0")
	if err != OK:
		printerr("Failed to start relay server: ", err)
		return

	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Relay server listening on port ", PORT)

func _on_peer_connected(id: int):
	var player_number = _get_next_player_number()
	if player_number == -1:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	connected_players[id] = {"peer_id": id, "player_number": player_number}
	print("Player ", id, " connected (slot ", player_number, ")")

func _on_peer_disconnected(id: int):
	print("Player ", id, " disconnected")
	connected_players.erase(id)

func _get_next_player_number() -> int:
	for i in range(1, 5):
		var taken = false
		for data in connected_players.values():
			if data.player_number == i:
				taken = true
				break
		if not taken:
			return i
	return -1
