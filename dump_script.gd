extends Node

func _ready():
	# Wait a couple of frames for everything to spawn
	await get_tree().process_frame
	await get_tree().process_frame
	
	var file = FileAccess.open("scene_dump.txt", FileAccess.WRITE)
	var root = get_node("/root/Node3D")
	if not root:
		file.store_line("Root Node3D not found!")
		return
	
	file.store_line("Camera position: " + str(root.camera.global_position))
	file.store_line("Camera rotation: " + str(root.camera.rotation_degrees))
	file.store_line("Camera target: " + str(root.camera_target))
	
	file.store_line("Water plane position: " + str(root.water_plane.global_position))
	
	var chunk_count = root.loaded_chunks.size()
	file.store_line("Loaded chunks: " + str(chunk_count))
	
	var total_tiles = 0
	for chunk in root.loaded_chunks.values():
		total_tiles += chunk.get_child_count()
	
	file.store_line("Total tiles: " + str(total_tiles))
	
	if total_tiles > 0:
		var first_tile = root.loaded_chunks.values()[0].get_child(0)
		file.store_line("First tile position: " + str(first_tile.global_position))
	
	file.close()
	get_tree().quit()
