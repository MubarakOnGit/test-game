extends SceneTree

func _init():
	var script = load("res://terrain_generator.gd").new()
	script._ready()
	script._process(0.16)
	print("Loaded chunks count: ", script.loaded_chunks.size())
	if script.loaded_chunks.size() > 0:
		var chunk = script.loaded_chunks.values()[0]
		print("Children in first chunk: ", chunk.get_child_count())
	print("Camera global position: ", script.camera.global_position)
	print("Camera rotation: ", script.camera.rotation_degrees)
	quit()
