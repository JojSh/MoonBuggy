extends Node

# Preload shader-heavy scenes to avoid first-time compilation stutter
var explosion_prefab = preload("res://scenes/ExplosionPrefab.tscn")

func _ready():
	if OS.has_feature("web"):
		print("[ShaderPreloader] Is web, init shader warmup")
		_preload_shaders()

func _preload_shaders():
	# Instantiate explosion at origin (visible to camera) to ensure shaders compile
	var explosion_instance = explosion_prefab.instantiate()
	explosion_instance.position = Vector3(0, 0, 0)
	add_child(explosion_instance)

	# Wait one frame for scene to be added to tree
	await get_tree().process_frame

	# Trigger all particle systems to force shader compilation
	for node in explosion_instance.find_children("*", "GPUParticles3D"):
		node.emitting = true
		node.restart()

	# Trigger the explosion animation to compile particle shaders
	if explosion_instance.has_node("Explosion/AnimationPlayer"):
		var anim_player = explosion_instance.get_node("Explosion/AnimationPlayer")
		if anim_player.has_animation("PlayExplosion"):
			anim_player.play("PlayExplosion")

	print("[ShaderPreloader] Explosion particles triggered, waiting for compile...")

	# Wait a couple frames for WebGL to actually render and compile shaders
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout

	# Clean up immediately after shaders compile
	explosion_instance.queue_free()

	print("[ShaderPreloader] Shader warmup complete")
