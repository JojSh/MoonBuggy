extends Node3D

# Map scene resources
const Map1 = preload("res://maps/map_1.tscn")
const Map2 = preload("res://maps/map_2.tscn")
const ObstacleCourse1P = preload("res://maps/obstable_course_1p.tscn")

# Array of all available maps
const AVAILABLE_MAPS = [Map1, Map2, ObstacleCourse1P]

# Current map index
var current_map_index = GameSettings.current_map_index
var current_map_instance = null

# Called when the node enters the scene tree for the first time.
func _ready():
	load_map(current_map_index)

# Loads a specific map by index
func load_map(map_index):
	# Remove current map if it exists
	if current_map_instance:
		current_map_instance.queue_free()
	
	# Update current map index
	current_map_index = map_index
	GameSettings.current_map_index = map_index
	
	# Instantiate and add new map
	current_map_instance = AVAILABLE_MAPS[current_map_index].instantiate()
	add_child(current_map_instance)
	
	# Notify that map has changed (optional)
	var current_map_name = AVAILABLE_MAPS[current_map_index].resource_path.get_file().trim_suffix(".tscn").capitalize().replace("_", " ")
	var root_node = get_tree().get_root().get_node("RootNode")
	if root_node:
		root_node.current_map = current_map_instance

# Cycles to the next available map
func cycle_to_next_map():
	# Calculate next map index (with wrap-around)
	var next_map_index = (current_map_index + 1) % AVAILABLE_MAPS.size()
	
	# Load the next map
	load_map(next_map_index)
