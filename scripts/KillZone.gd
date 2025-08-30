@tool
extends Area3D

@export var size: Vector3 = Vector3(10, 10, 10): set = set_size

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var debug_mesh: MeshInstance3D = $DebugMesh

func _ready():
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
	update_visual()

func set_size(new_size: Vector3):
	size = new_size
	update_visual()

func update_visual():
	# Update collision shape - create unique instance to avoid shared resource issues
	if collision_shape:
		if not collision_shape.shape or not collision_shape.shape is BoxShape3D:
			collision_shape.shape = BoxShape3D.new()
		
		# Create a new BoxShape3D to ensure each instance has its own
		var new_shape = BoxShape3D.new()
		new_shape.size = size
		collision_shape.shape = new_shape
	
	# Update debug mesh if it exists
	if debug_mesh:
		var box_mesh = BoxMesh.new()
		box_mesh.size = size
		debug_mesh.mesh = box_mesh
		
		# Show in editor or when debug mode is enabled
		var should_show = Engine.is_editor_hint() or (GameSettings and GameSettings.debug_mode_on)
		debug_mesh.visible = should_show

func update_debug_visibility():
	if not Engine.is_editor_hint() and debug_mesh:
		debug_mesh.visible = GameSettings and GameSettings.debug_mode_on

func _on_body_entered(body):
	if body is VehicleBody3D:
		body.die()
		body.get_node("ImpactSound").play()
