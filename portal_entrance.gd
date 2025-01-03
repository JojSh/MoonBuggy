extends Area3D

@export var portal_number: int

func _ready():
	# If portal_number wasn't set in editor, extract it from the node name
	var number = portal_number if portal_number > 0 else str(name)[-1].to_int()
	
	# Connect to the root node's portal function
	body_entered.connect(get_parent()._on_portal_entrance_area_3d_body_entered.bind(number))
