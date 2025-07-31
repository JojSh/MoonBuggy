extends Node

var eliminated_players: Array[Node] = []
var available_rockets: Array[RigidBody3D] = []
var rocket_assignment_timer: float = 0.0
const ASSIGNMENT_INTERVAL: float = 3.0  # Assign rockets every 3 seconds

signal rocket_takeover_started(player: Node, rocket: RigidBody3D)
signal rocket_takeover_ended(player: Node, rocket: RigidBody3D)

func _ready():
	print("SpectatorManager initialized")

func _process(delta):
	rocket_assignment_timer += delta
	
	if rocket_assignment_timer >= ASSIGNMENT_INTERVAL:
		rocket_assignment_timer = 0.0
		attempt_rocket_assignments()

func register_eliminated_player(player: Node):
	if not eliminated_players.has(player):
		eliminated_players.append(player)
		print("SpectatorManager: Registered eliminated player ", player.player_number)
		print("SpectatorManager: Total eliminated players: ", eliminated_players.size())

func register_rocket(rocket: RigidBody3D):
	if not available_rockets.has(rocket):
		available_rockets.append(rocket)
		print("SpectatorManager: Registered rocket at ", rocket.global_position)
		print("SpectatorManager: Total available rockets: ", available_rockets.size())
		
		# Connect to rocket destruction
		if rocket.has_signal("rocket_exploded"):
			rocket.rocket_exploded.connect(_on_rocket_destroyed.bind(rocket))
		if rocket.has_signal("rocket_out_of_bounds"):
			rocket.rocket_out_of_bounds.connect(_on_rocket_destroyed.bind(rocket))

func _on_rocket_destroyed(rocket: RigidBody3D):
	if available_rockets.has(rocket):
		available_rockets.erase(rocket)
		print("SpectatorManager: Removed destroyed rocket. Remaining: ", available_rockets.size())

func attempt_rocket_assignments():
	if eliminated_players.is_empty() or available_rockets.is_empty():
		return
		
	# Clean up invalid rockets (might have been destroyed)
	available_rockets = available_rockets.filter(func(rocket): return is_instance_valid(rocket))
	
	if available_rockets.is_empty():
		return
		
	print("SpectatorManager: Attempting rocket assignments...")
	print("  - Eliminated players: ", eliminated_players.size())
	print("  - Available rockets: ", available_rockets.size())
	
	# For Phase 1, just show that assignment would happen
	var player = eliminated_players[0]  # Take first eliminated player
	var rocket = available_rockets[0]   # Take first available rocket
	
	print("SpectatorManager: Would assign Player ", player.player_number, " to rocket at ", rocket.global_position)
	emit_signal("rocket_takeover_started", player, rocket)

func get_eliminated_player_count() -> int:
	return eliminated_players.size()

func get_available_rocket_count() -> int:
	return available_rockets.filter(func(rocket): return is_instance_valid(rocket)).size()