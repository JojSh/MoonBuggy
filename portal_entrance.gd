extends Area3D

@export var user_defined_exit_portal: int

func _ready():
	# If user_defined_exit_portal wasn't set in editor, extract it from the node name
	var exit_portal_number = user_defined_exit_portal if user_defined_exit_portal > 0 else str(name)[-1].to_int()

	# Connect to the root node's portal function
	body_entered.connect(get_parent()._on_portal_entrance_area_3d_body_entered.bind(exit_portal_number))
