# In your item spawner script
class_name ItemSpawner
extends Node

# Array of spawn point node references
var spawn_points = []

# Track which positions are currently occupied
var occupied_positions = []

# Track spawned items by their spawn point index for network sync
# Format: {spawn_index: {"item": Node, "type": int}}
var spawned_items = {}

# Array of different pickup scenes
var pickup_scenes = [
	preload("res://scenes/boost_pick_up.tscn"),
	preload("res://scenes/life_pick_up.tscn"),
	preload("res://scenes/reload_speed_pick_up.tscn"),
	preload("res://scenes/rocket_diarrhea_pick_up.tscn")
]

# Optional: Weights for different pickup types (higher number = more common)
var pickup_weights = [
	10,  # BoostPickUp - most common
	4,   # LifePickUp
	6,   # ReloadSpeedPickUp
	1    # RocketDiarrheaPickUp - rarest
]

# Timer for spawning items
var spawn_timer = null
var spawn_interval = 5.0  # Seconds between spawns

var _spawning_started := false
var _check_timer: Timer

func _ready():
	_collect_spawn_points()
	_setup_spawn_timer()
	_setup_network_listeners()

func _collect_spawn_points():
	for child in get_children():
		if child is Node3D and child.name.begins_with("SpawnPoint"):
			spawn_points.append(child)

	occupied_positions.resize(spawn_points.size())
	occupied_positions.fill(false)

func _setup_spawn_timer():
	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_interval
	spawn_timer.autostart = false
	spawn_timer.connect("timeout", _on_spawn_timer_timeout)
	add_child(spawn_timer)

func _setup_network_listeners():
	NetworkManager.player_connected.connect(_check_and_start_spawning.unbind(1))

	# Polling timer for offline mode (where player_connected signal doesn't fire)
	_check_timer = Timer.new()
	_check_timer.wait_time = 0.5
	_check_timer.autostart = true
	_check_timer.connect("timeout", _check_and_start_spawning)
	add_child(_check_timer)

func _sync_existing_items_to_peer(peer_id: int):
	# Send all currently spawned items to the new player
	var items_to_sync = []
	for spawn_index in spawned_items.keys():
		var item_data = spawned_items[spawn_index]
		if is_instance_valid(item_data.item):
			items_to_sync.append({"spawn_index": spawn_index, "item_type": item_data.type})

	if items_to_sync.size() > 0:
		_receive_item_sync.rpc_id(peer_id, items_to_sync)

@rpc("any_peer", "call_remote", "reliable")
func _receive_item_sync(items_data: Array):
	for item_info in items_data:
		var spawn_index = item_info["spawn_index"]
		var item_type = item_info["item_type"]
		# Only spawn if we don't already have an item at this position
		var existing = spawned_items.get(spawn_index)
		if not existing or not is_instance_valid(existing.item):
			_spawn_item_at(spawn_index, item_type)

func _check_and_start_spawning():
	if _spawning_started:
		return
	_start_spawning()

func _start_spawning():
	if _spawning_started:
		return
	_spawning_started = true

	# Stop the check timer - no longer needed
	if _check_timer:
		_check_timer.stop()
		_check_timer.queue_free()
		_check_timer = null

	# Start the spawn timer
	spawn_timer.start()

	# Only authority spawns items; others request sync
	if _is_spawn_authority():
		spawn_random_item()
	else:
		# Request sync from authority (player 1)
		_request_item_sync.rpc()

@rpc("any_peer", "call_remote", "reliable")
func _request_item_sync():
	# Only authority responds to sync requests
	if not _is_spawn_authority():
		return
	var requester_id = multiplayer.get_remote_sender_id()
	_sync_existing_items_to_peer(requester_id)

func _is_spawn_authority() -> bool:
	# In single player, we have spawn authority
	if not NetworkManager.is_multiplayer_active():
		return true

	# In ENet mode, use is_hosting
	if NetworkManager.is_hosting:
		return true

	# In WebRTC relay mode, player 1 has spawn authority
	var local_data = NetworkManager.get_local_player_data()
	if local_data.has("player_number"):
		return local_data.player_number == 1

	# No player data yet, no authority
	return false

func _on_spawn_timer_timeout():
	# Only authority decides when to spawn
	if _is_spawn_authority():
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

	# Choose a random item type (weighted selection)
	var item_type_index = select_weighted_pickup_index()

	# Spawn locally
	var item = _spawn_item_at(rng_index, item_type_index)

	# Broadcast to other clients in multiplayer
	if NetworkManager.is_multiplayer_active() and _is_spawn_authority():
		_broadcast_spawn.rpc(rng_index, item_type_index)

	return item

func _spawn_item_at(spawn_point_index: int, item_type_index: int) -> Node:
	var spawn_point = spawn_points[spawn_point_index]
	var item_scene = pickup_scenes[item_type_index]

	# Mark position as occupied
	occupied_positions[spawn_point_index] = true

	# Spawn the item
	var item = item_scene.instantiate()
	add_child(item)
	item.global_position = spawn_point.global_position
	item.global_rotation = spawn_point.global_rotation

	# Store reference for network sync (with type for late-join sync)
	spawned_items[spawn_point_index] = {"item": item, "type": item_type_index}

	# Connect to item's collected signal
	item.connect("collected", _on_item_collected.bind(spawn_point_index))

	# Connect to the moved_off_position signal if it exists
	if item.has_signal("moved_off_position"):
		item.connect("moved_off_position", _on_item_moved_off_position.bind(spawn_point_index))

	return item

@rpc("any_peer", "call_remote", "reliable")
func _broadcast_spawn(spawn_point_index: int, item_type_index: int):
	# Clients receive spawn command from authority
	_spawn_item_at(spawn_point_index, item_type_index)

func select_weighted_pickup_index() -> int:
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
			return i

	# Fallback (should never reach here)
	return 0

func _on_item_collected(position_index: int):
	# Mark position as available again
	occupied_positions[position_index] = false
	spawned_items.erase(position_index)

	# In multiplayer, broadcast collection to other clients
	if NetworkManager.is_multiplayer_active():
		_broadcast_collection.rpc(position_index)

func _on_item_moved_off_position(position_index: int):
	# Mark position as available again when item is moved off position
	occupied_positions[position_index] = false
	spawned_items.erase(position_index)

	# In multiplayer, broadcast removal to other clients
	if NetworkManager.is_multiplayer_active():
		_broadcast_collection.rpc(position_index)

@rpc("any_peer", "call_remote", "reliable")
func _broadcast_collection(position_index: int):
	# Remote client: remove the item and mark position available
	occupied_positions[position_index] = false
	if spawned_items.has(position_index):
		var item_data = spawned_items[position_index]
		spawned_items.erase(position_index)
		if is_instance_valid(item_data.item):
			item_data.item.queue_free()
