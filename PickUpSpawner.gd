# In your item spawner script
class_name ItemSpawner
extends Node

# Array of spawn point node references
var spawn_points = []

# Track which positions are currently occupied
var occupied_positions = []

# Array of different pickup scenes
var pickup_scenes = [
	preload("res://boost_pick_up.tscn"),
	preload("res://life_pick_up.tscn"),
	preload("res://reload_speed_pick_up.tscn"),
	preload("res://rocket_diarrhea_pick_up.tscn")
]

# Optional: Weights for different pickup types (higher number = more common)
var pickup_weights = [
	10,  # BoostPickUp - most common # 10
	4,  # LifePickUp # 4
	6,  # ReloadSpeedPickUp # 6
	1   # RocketDiarrheaPickUp - rarest # 1
]

# Timer for spawning items
var spawn_timer = null
var spawn_interval = 5.0  # Seconds between spawns

func _ready():
	# Get spawn point nodes
	for child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			spawn_points.append(child)
	
	# Initialize all positions as available
	occupied_positions.resize(spawn_points.size())
	for i in range(occupied_positions.size()):
		occupied_positions[i] = false

	# Create and start the spawn timer
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.autostart = true
	spawn_timer.connect("timeout", _on_spawn_timer_timeout)
	add_child(spawn_timer)

	# Spawn initial item
	spawn_random_item()

func _on_spawn_timer_timeout():
	spawn_random_item()

func spawn_random_item():
	# Get all available positions
	var available_indices = []
	for i in range(spawn_points.size()):
		if not occupied_positions[i]:
			available_indices.append(i)

	# If no positions available, exit
	if available_indices.size() == 0:
		return null

	# Choose a random available position
	var rng_index = available_indices[randi() % available_indices.size()]
	var spawn_point = spawn_points[rng_index]

	# Mark position as occupied
	occupied_positions[rng_index] = true

	# Choose a random item type (weighted selection)
	var item_scene = select_weighted_pickup()

	# Spawn the item
	var item = item_scene.instantiate()
	add_child(item)
	item.global_position = spawn_point.global_position
	item.global_rotation = spawn_point.global_rotation

	# Connect to item's collected signal
	item.connect("collected", _on_item_collected.bind(rng_index))
	
	# Connect to the moved_off_position signal if it exists
	if item.has_signal("moved_off_position"):
		item.connect("moved_off_position", _on_item_moved_off_position.bind(rng_index))

	return item

func select_weighted_pickup():
	# Calculate total weight
	var total_weight = 0
	for weight in pickup_weights:
		total_weight += weight

	# Get a random value between 0 and total weight
	var random_value = randi() % total_weight

	# Find which pickup this corresponds to
	var current_weight = 0
	for i in range(pickup_weights.size()):
		current_weight += pickup_weights[i]
		if random_value < current_weight:
			return pickup_scenes[i]

	# Fallback (should never reach here)
	return pickup_scenes[0]

func _on_item_collected(position_index):
	# Mark position as available again
	occupied_positions[position_index] = false
	
func _on_item_moved_off_position(position_index):
	# Mark position as available again when item is moved off position
	occupied_positions[position_index] = false
