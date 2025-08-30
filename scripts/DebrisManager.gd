extends Node

# Optional: Configure how long debris should last before auto-cleanup
const MAX_DEBRIS_LIFETIME := 45.0  # seconds

var active_debris: Array[Node] = []

func add_debris(debris: Node) -> void:
	active_debris.append(debris)
	add_child(debris)
	
	# Optional: Add timer for auto-cleanup of old debris
	var timer := get_tree().create_timer(MAX_DEBRIS_LIFETIME)
	timer.timeout.connect(func(): remove_debris(debris))

func remove_debris(debris: Node) -> void:
	if debris and is_instance_valid(debris):
		active_debris.erase(debris)
		debris.queue_free()

func clear_all_debris() -> void:
	for debris in active_debris:
		remove_debris(debris)
	active_debris.clear()
