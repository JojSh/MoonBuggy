extends Area3D

signal checkpoint_triggered

@export var active := false
var illuminated_material: Material = preload("res://illuminated_checkpoint_ring.tres")
var inactive_material: Material = preload("res://inactive_checkpoint_ring.tres")

func _on_body_entered (body):
	if active:
		$CheckedSound.play()
		checkpoint_triggered.emit()

func activate ():
	active = true
	$MeshInstance3D.material_override = illuminated_material

func deactivate ():
	active = false
	$MeshInstance3D.material_override = inactive_material
