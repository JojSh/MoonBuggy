extends Node

var eliminated_players: Array[Node] = []
var available_rockets: Array[RigidBody3D] = []
var rocket_assignment_timer: float = 0.0
var next_player_index: int = 0  # Index for round-robin player assignment
const ASSIGNMENT_INTERVAL: float = 3.0  # Assign rockets every 3 seconds

signal rocket_takeover_started(player: Node, rocket: RigidBody3D)
signal rocket_takeover_ended(player: Node, rocket: RigidBody3D)

func _process(delta):
	rocket_assignment_timer += delta
	
	if rocket_assignment_timer >= ASSIGNMENT_INTERVAL:
		rocket_assignment_timer = 0.0
		attempt_rocket_assignments()

func register_eliminated_player(player: Node):
	if not eliminated_players.has(player):
		eliminated_players.append(player)
		# Reset index when player list changes to ensure fair rotation
		next_player_index = 0

func register_rocket(rocket: RigidBody3D):
	if not available_rockets.has(rocket):
		available_rockets.append(rocket)

		# Connect to rocket destruction
		if rocket.has_signal("rocket_exploded"):
			rocket.rocket_exploded.connect(_on_rocket_exploded.bind(rocket))
		if rocket.has_signal("rocket_out_of_bounds"):
			rocket.rocket_out_of_bounds.connect(_on_rocket_out_of_bounds.bind(rocket))

func _on_rocket_exploded(position: Vector3, rocket: RigidBody3D):
	if available_rockets.has(rocket):
		available_rockets.erase(rocket)

func _on_rocket_out_of_bounds(rocket: RigidBody3D):
	if available_rockets.has(rocket):
		available_rockets.erase(rocket)

func attempt_rocket_assignments():
	if eliminated_players.is_empty() or available_rockets.is_empty():
		return
		
	# Clean up invalid rockets and eliminate those already under control
	available_rockets = available_rockets.filter(func(rocket): 
		return is_instance_valid(rocket) and not rocket.is_under_player_control()
	)
	
	if available_rockets.is_empty():
		return
		
	
	# Round-robin assignment: cycle through eliminated players
	if next_player_index >= eliminated_players.size():
		next_player_index = 0  # Wrap around to start
	
	var player = eliminated_players[next_player_index]
	var rocket = available_rockets[0]
	
	# Move to next player for next assignment
	next_player_index = (next_player_index + 1) % eliminated_players.size()

	# Always enable roll leveling
	rocket.assign_player_control(player, true)
	emit_signal("rocket_takeover_started", player, rocket)

func get_eliminated_player_count() -> int:
	return eliminated_players.size()

func get_available_rocket_count() -> int:
	return available_rockets.filter(func(rocket): return is_instance_valid(rocket)).size()
