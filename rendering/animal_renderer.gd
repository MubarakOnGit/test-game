class_name AnimalRenderer

static var _animal_script = preload("res://world/animal.gd")
static var _animal_scenes: Dictionary = {}

static func _get_animal_scene(type_name: String) -> PackedScene:
	if _animal_scenes.has(type_name):
		return _animal_scenes[type_name]
	
	var path = "res://assets/animals/" + type_name
	if not path.ends_with(".glb"):
		path += ".glb"
		
	var packed = load(path)
	if packed:
		_animal_scenes[type_name] = packed
	return packed

static func commit(node: ChunkNode, data: ChunkData) -> void:
	# Clear existing animals in this chunk (already handled in reset, but just to be sure)
	for child in node.animals_container.get_children():
		child.queue_free()
		
	for a_data in data.animals:
		var scene = _get_animal_scene(a_data["type"])
		if not scene:
			continue
			
		var visual = scene.instantiate()
		
		# Scale down models so they aren't massive compared to the player
		if "Fish" in a_data["type"] or "Shark" in a_data["type"]:
			visual.scale = Vector3(0.15, 0.15, 0.15)
		else:
			visual.scale = Vector3(0.35, 0.35, 0.35)
			
		var instance = CharacterBody3D.new()
		
		# Attach script and properties
		instance.set_script(_animal_script)
		instance.add_child(visual)
		
		instance.is_water_animal = a_data["is_water"]
		instance.position = Vector3(a_data["x"] * ChunkData.TILE_SIZE, a_data["y"], a_data["z"] * ChunkData.TILE_SIZE)
		
		# Add a small random rotation
		instance.rotation.y = randf() * TAU
		
		node.animals_container.add_child(instance)
