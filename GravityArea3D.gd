extends Area3D

enum SurfaceType { OUTER, INNER, FLAT }
@export var surface_type: SurfaceType = SurfaceType.OUTER

func _ready():
	# Set the meta property so the vehicle can read it
	set_meta("surface_type", surface_type)
