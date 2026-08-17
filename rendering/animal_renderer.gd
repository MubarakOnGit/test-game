class_name AnimalRenderer

static var _animal_script = preload("res://world/animal.gd")
static var _animal_scenes: Dictionary = {}

static func _get_animal_scene(type_name: String) -> PackedScene:
	if _animal_scenes.has(type_name):
		return _animal_scenes[type_name]
	
	var candidate_paths: Array[String] = []
	if type_name.begins_with("res://"):
		candidate_paths.append(type_name)
	else:
		var with_ext = type_name if (type_name.ends_with(".glb") or type_name.ends_with(".tscn")) else type_name + ".glb"
		candidate_paths.append("res://assets/models/" + with_ext)
		candidate_paths.append("res://assets/animals/" + with_ext)
		candidate_paths.append("res://assets/" + with_ext)
		
		if type_name == "wolf" or type_name == "Wolf":
			candidate_paths.append("res://assets/models/wolf.glb")
			candidate_paths.append("res://assets/animals/blocky_wolf.glb")
		elif type_name == "blocky_wolf":
			candidate_paths.append("res://assets/animals/blocky_wolf.glb")
			candidate_paths.append("res://assets/models/wolf.glb")
		elif type_name == "rabbit" or type_name == "Rabbit":
			candidate_paths.append("res://assets/animals/blocky_rabbit.glb")
			candidate_paths.append("res://assets/animals/low_poly_rabbit.glb")
		
	var packed: PackedScene = null
	for path in candidate_paths:
		if ResourceLoader.exists(path):
			packed = load(path)
			if packed:
				break
				
	if packed:
		_animal_scenes[type_name] = packed
	else:
		push_warning("AnimalRenderer: Could not load animal scene for type: " + type_name)
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
		
		# Scale down models so they aren't massive compared to the player, and set correct animations
		var instance = CharacterBody3D.new()
		var type_lower: String = a_data["type"].to_lower()
		
		if "wolf" in type_lower:
			visual.scale = Vector3(1.7, 1.7, 1.7)
			instance.set("move_anim", "Walk")
		elif "rabbit" in type_lower:
			visual.scale = Vector3(0.70, 0.70, 0.70)
			instance.set("move_anim", "Run")
		else:
			visual.scale = Vector3(0.35, 0.35, 0.35)
			instance.set("move_anim", "walk")
			
		# Attach script and properties
		instance.set_script(_animal_script)
		instance.add_child(visual)
		
		instance.is_water_animal = a_data["is_water"]
		instance.position = Vector3(a_data["x"] * ChunkData.TILE_SIZE, a_data["y"], a_data["z"] * ChunkData.TILE_SIZE)
		
		# Add a small random rotation
		instance.rotation.y = randf() * TAU
		
		node.animals_container.add_child(instance)
