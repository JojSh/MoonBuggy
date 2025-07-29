@tool
extends Area3D

@export var size: Vector3 = Vector3(10, 10, 10): set = set_size

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
var debug_mesh: MeshInstance3D

func _ready():
	if not Engine.is_editor_hint():
		add_to_group("killzones")
		body_entered.connect(_on_body_entered)
		if debug_mesh:
			debug_mesh.visible = GameSettings.debug_mode_on
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
	
	# Update debug visual in editor
	if true:
	#if Engine.is_editor_hint():
		if not debug_mesh:
			debug_mesh = MeshInstance3D.new()
			add_child.call_deferred(debug_mesh)
			call_deferred("_set_debug_mesh_owner")
			
			var material = StandardMaterial3D.new()
			material.albedo_color = Color(1, 0, 0, 0.3)
			material.flags_transparent = true
			debug_mesh.material_override = material
		
		var box_mesh = BoxMesh.new()
		box_mesh.size = size
		debug_mesh.mesh = box_mesh
		debug_mesh.visible = Engine.is_editor_hint() or (GameSettings and GameSettings.debug_mode_on)

func _set_debug_mesh_owner():
	if debug_mesh and debug_mesh.get_parent() == self:
		debug_mesh.owner = self

func update_debug_visibility():
	if debug_mesh and not Engine.is_editor_hint():
		debug_mesh.visible = GameSettings and GameSettings.debug_mode_on

func _on_body_entered(body):
	if body is VehicleBody3D:
		body.die()
		body.get_node("ImpactSound").play()
