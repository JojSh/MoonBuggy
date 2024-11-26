extends Node3D

@onready var draw_debug: MeshInstance3D = $MeshInstance3D

func _physics_process (_delta: float) -> void:
	if draw_debug.mesh is ImmediateMesh:
		draw_debug.mesh.clear_surfaces()
	
	#draw_line(Vector3.UP, Vector3.UP * 10, Color.GREEN)

func draw_line (point_a: Vector3, point_b: Vector3, color: Color = Color.RED):
	if point_a.is_equal_approx(point_b):
		return

	if draw_debug.mesh is ImmediateMesh:
		draw_debug.mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		draw_debug.mesh.surface_set_color(color)
		
		draw_debug.mesh.surface_add_vertex(point_a)
		draw_debug.mesh.surface_add_vertex(point_b)
		
		draw_debug.mesh.surface_end()
