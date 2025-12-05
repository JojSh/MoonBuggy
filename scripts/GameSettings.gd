extends Node

# Network mode configuration
enum NetworkMode {
	ENET,      # Traditional IP-based networking (Steam Deck, local network)
	WEBRTC     # WebSocket relay for web builds (itch.io) - uses a dedicated server
}

# CHANGE THIS FLAG FOR DIFFERENT BUILDS:
# - Set to NetworkMode.ENET for native builds (Steam Deck, desktop)
# - Set to NetworkMode.WEBRTC for web builds (itch.io)
var network_mode: NetworkMode = NetworkMode.WEBRTC
var should_skip_main_menu: bool = false
var desired_number_players: int = 1
var debug_mode_on: bool = false # true
var current_map_index: int = 0
