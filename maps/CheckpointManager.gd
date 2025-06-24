extends Node3D

#signal checkpoint_reached(checkpoint_index: int)

var checkpoint_rings: Array[Area3D] = []
var current_checkpoint_index: int = 0

func _ready ():
	initialize_checkpoints()

func initialize_checkpoints ():
	collect_and_connect_checkpoints()
	activate_checkpoint(0) # the first one

func collect_and_connect_checkpoints ():
	for child in get_children():
		if child.name.begins_with("CheckpointRing") and child is Area3D:
			checkpoint_rings.append(child)
			child.checkpoint_triggered.connect(_on_checkpoint_triggered)

	checkpoint_rings.sort_custom(func(a, b): return a.name < b.name)

func activate_checkpoint (index: int):
	var ring = checkpoint_rings[index]
	ring.activate()

func deactivate_checkpoint (index: int):
	var ring = checkpoint_rings[index]
	ring.deactivate()

func hide_checkpoint (index: int):
	var ring = checkpoint_rings[index]
	ring.hide()

func _on_checkpoint_triggered ():
	hide_checkpoint(current_checkpoint_index)
	current_checkpoint_index += 1
	
	if current_checkpoint_index < checkpoint_rings.size():
		activate_checkpoint(current_checkpoint_index)
		#checkpoint_reached.emit(current_checkpoint_index - 1)
	else:
		pass
		#checkpoint_reached.emit(current_checkpoint_index - 1)
