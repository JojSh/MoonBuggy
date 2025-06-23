extends Area3D

@export var active := false

func _on_body_entered(body):
	$CheckedSound.play()
	deactivate()
	# send signal to CheckpointManager

func activate ():
	active = true
	visible = true

func deactivate ():
	active = false
	visible = false
