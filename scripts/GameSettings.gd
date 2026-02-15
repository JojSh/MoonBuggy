extends Node

# Network mode configuration
enum NetworkMode {
	ENET,      # Traditional IP-based networking (Steam Deck, local network)
	WEBRTC     # WebSocket relay for web builds (itch.io) - uses a dedicated server
}

# Display mode configuration
enum DisplayOrientation {
	LANDSCAPE,  # 1920x1080 - desktop/console
	PORTRAIT    # 1080x1920 - mobile
}

# CHANGE THIS FLAG FOR DIFFERENT BUILDS:
# - Set to NetworkMode.ENET for native builds (Steam Deck, desktop)
# - Set to NetworkMode.WEBRTC for web builds (itch.io)
var network_mode: NetworkMode = NetworkMode.WEBRTC
var display_orientation: DisplayOrientation = DisplayOrientation.PORTRAIT
var should_skip_main_menu: bool = false
var desired_number_players: int = 1
var debug_mode_on: bool = false # true
var current_map_index: int = 0

# Network synchronization settings
var enable_periodic_state_sync: bool = true  # Enable/disable periodic state verification and correction

func is_portrait_mode() -> bool:
	#return display_orientation == DisplayOrientation.PORTRAIT
	return display_orientation == DisplayOrientation.LANDSCAPE
