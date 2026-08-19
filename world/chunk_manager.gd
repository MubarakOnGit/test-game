class_name ChunkManager
extends Node

const RENDER_DISTANCE := 3
const MAX_UPLOADS_PER_FRAME := 2

var database: WorldDatabase
var world_seed: int
var player_node: Node3D = null  # Set by WorldManager after player is spawned

var _pool: Array[ChunkNode] = []
var _active_nodes: Dictionary = {} # Vector2i -> ChunkNode

# ─── Queues ───────────────────────────────────────────────────────────────────
# O(1) membership check using Dictionaries for queues
var _queue_generate: Dictionary = {} # Vector2i -> true
var _generating_tasks: Dictionary = {} # Vector2i -> task_id
var _meshing_tasks: Dictionary = {} # Vector2i -> task_id
var _queue_upload: Array[Dictionary] = [] # Processed sequentially, stores { "data": ChunkData, "arrays": MeshArrays }

func _init(db: WorldDatabase, w_seed: int) -> void:
	name = "ChunkManager"
	database = db
	world_seed = w_seed
	
	# Listen to chunk modifications
	WorldEventBus.chunk_modified.connect(_on_chunk_modified)
	add_to_group("chunk_manager")

## Main tick for the chunk streaming lifecycle.
func tick(center_chunk: Vector2i) -> void:
	_update_streaming(center_chunk)
	_process_generation()
	_update_zones(center_chunk)

## Main tick for uploading finished meshes to the GPU.
func tick_uploads() -> void:
	var uploads := 0
	while _queue_upload.size() > 0 and uploads < MAX_UPLOADS_PER_FRAME:
		var job: Dictionary = _queue_upload.pop_front()
		var data: ChunkData = job.data
		var terrain_arrays = job.terrain_arrays
		var water_arrays = job.water_arrays
		
		# Skip if no longer relevant (e.g., player moved far away quickly)
		if data.metadata.state == ChunkMetadata.State.UNLOADING:
			continue
			
		var node: ChunkNode
		if _active_nodes.has(Vector2i(data.cx, data.cz)):
			node = _active_nodes[Vector2i(data.cx, data.cz)]
		else:
			node = _get_pool_node()
			node.chunk_key = Vector2i(data.cx, data.cz)
			node.position = Vector3(data.world_origin_x(), 0, data.world_origin_z())
			
			# Initial zone assignment based on upload distance
			var dist_x = absi(data.cx - player_node.position.x / (ChunkData.CHUNK_SIZE * ChunkData.TILE_SIZE)) if player_node else 0
			var dist_z = absi(data.cz - player_node.position.z / (ChunkData.CHUNK_SIZE * ChunkData.TILE_SIZE)) if player_node else 0
			node.sim_zone = maxi(dist_x, dist_z)
			if node.sim_zone > 2: node.sim_zone = 2
		
		# Run catch-up simulation before spawning animals into the scene
		EcosystemSimulator.catch_up(data)
		
		# Commit to node
		ChunkRenderer.commit(node, data, terrain_arrays, water_arrays)
		
		node.player_ref = player_node
		node.visible = true
		_active_nodes[node.chunk_key] = node
		data.metadata.state = ChunkMetadata.State.VISIBLE
		
		uploads += 1

## Cleanup chunks that are too far away.
func tick_cleanup(center_chunk: Vector2i) -> void:
	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _active_nodes.keys():
		var dist_x := absi(key.x - center_chunk.x)
		var dist_z := absi(key.y - center_chunk.y)
		if dist_x > RENDER_DISTANCE + 1 or dist_z > RENDER_DISTANCE + 1:
			to_remove.append(key)
			
	for key in to_remove:
		var node: ChunkNode = _active_nodes[key]
		var data := database.get_chunk(key)
		if data:
			# Snapshot live animal state before unloading
			EcosystemSimulator.snapshot(data, node)
			data.metadata.state = ChunkMetadata.State.SLEEPING
		_return_pool_node(node)
		_active_nodes.erase(key)
		
	# Clean up generation queue
	var q_remove: Array[Vector2i] = []
	for key: Vector2i in _queue_generate.keys():
		var dist_x := absi(key.x - center_chunk.x)
		var dist_z := absi(key.y - center_chunk.y)
		if dist_x > RENDER_DISTANCE + 1 or dist_z > RENDER_DISTANCE + 1:
			q_remove.append(key)
	for key in q_remove:
		_queue_generate.erase(key)

func _update_streaming(center_chunk: Vector2i) -> void:
	# Prioritize by distance (rings)
	var candidates: Array[Vector2i] = []
	
	for cx in range(center_chunk.x - RENDER_DISTANCE, center_chunk.x + RENDER_DISTANCE + 1):
		for cz in range(center_chunk.y - RENDER_DISTANCE, center_chunk.y + RENDER_DISTANCE + 1):
			var key := Vector2i(cx, cz)
			
			if not _active_nodes.has(key):
				if not database.has_chunk(key):
					# Brand new chunk, needs generating
					if not _queue_generate.has(key) and not _generating_tasks.has(key):
						candidates.append(key)
				else:
					# Existing chunk in memory, needs waking up
					var data := database.get_chunk(key)
					if data.metadata.state == ChunkMetadata.State.SLEEPING and not _meshing_tasks.has(key):
						var is_uploading = false
						for job in _queue_upload:
							if job.data == data: is_uploading = true
						if not is_uploading:
							_queue_meshing(data)
				
	if candidates.size() > 0:
		candidates.sort_custom(func(a: Vector2i, b: Vector2i):
			return Vector2(a.x - center_chunk.x, a.y - center_chunk.y).length_squared() < \
				   Vector2(b.x - center_chunk.x, b.y - center_chunk.y).length_squared()
		)
		
		# Enqueue the closest chunk
		var key = candidates[0]
		_queue_generate[key] = true

func _update_zones(center_chunk: Vector2i) -> void:
	for key in _active_nodes.keys():
		var node: ChunkNode = _active_nodes[key]
		var dist_x := absi(key.x - center_chunk.x)
		var dist_z := absi(key.y - center_chunk.y)
		var dist := maxi(dist_x, dist_z)
		
		var current_zone = node.sim_zone
		var new_zone = current_zone
		
		# Hysteresis:
		# Zone 0: enters <=0, exits >1
		# Zone 1: enters <=1, exits >2
		# Zone 2: enters <=4, exits >5 (but cleanup handles >4 anyway)
		if current_zone == 0 and dist > 1:
			new_zone = 1
		elif current_zone == 1:
			if dist <= 1:
				new_zone = 0
			elif dist > 2:
				new_zone = 2
		elif current_zone == 2:
			if dist <= 2:
				new_zone = 1
				
		if new_zone != current_zone:
			node.sim_zone = new_zone
			# If crossing LOD boundary (between 1 and 2), rebuild detail multimeshes
			if (current_zone < 2 and new_zone == 2) or (current_zone == 2 and new_zone < 2):
				var data = database.get_chunk(key)
				if data:
					GrassRenderer.commit(node, data)
					FlowerRenderer.commit(node, data)
					if new_zone == 2:
						node.berry_full_multimesh.multimesh = null
						node.berry_empty_multimesh.multimesh = null
						_set_tree_shadows(node, false)
					else:
						node._rebuild_berry_meshes()
						_set_tree_shadows(node, true)
			
			# If entering/leaving Zone 0, dynamically toggle shadows without rebuilding
			if new_zone == 0:
				node.grass_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				node.grass_multimesh_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				node.grass_multimesh_c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			elif current_zone == 0:
				node.grass_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.grass_multimesh_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.grass_multimesh_c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _set_tree_shadows(node: ChunkNode, on: bool) -> void:
	var setting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.pine_multimesh.cast_shadow = setting
	node.birch_multimesh.cast_shadow = setting
	node.simple_multimesh.cast_shadow = setting
	node.stylized_multimesh.cast_shadow = setting
	node.bush_a_multimesh.cast_shadow = setting
	node.rose_bush_multimesh.cast_shadow = setting

func _process_generation() -> void:
	if _queue_generate.size() > 0:
		var key: Vector2i = _queue_generate.keys()[0]
		_queue_generate.erase(key)
		
		_generating_tasks[key] = WorkerThreadPool.add_task(_generate_thread.bind(key, world_seed), true)

func _generate_thread(key: Vector2i, seed: int) -> void:
	var data := GenerationPipeline.generate(key.x, key.y, seed)
	call_deferred("_on_chunk_generated", data)

func _on_chunk_generated(data: ChunkData) -> void:
	var key := Vector2i(data.cx, data.cz)
	_generating_tasks.erase(key)
	
	# Skip if it was cancelled/unloaded before generation finished
	if data.metadata.state == ChunkMetadata.State.UNLOADING:
		return
		
	database.store_chunk(data)
	_queue_meshing(data)

func _queue_meshing(data: ChunkData) -> void:
	var key := Vector2i(data.cx, data.cz)
	var needs_full := (data.metadata.state != ChunkMetadata.State.VISIBLE)
	data.metadata.state = ChunkMetadata.State.MESHING
	_meshing_tasks[key] = WorkerThreadPool.add_task(_mesh_thread.bind(data, needs_full), true)

func _mesh_thread(data: ChunkData, needs_full: bool) -> void:
	var terrain_arrays = null
	if data.metadata.dirty_terrain or needs_full:
		terrain_arrays = TerrainMesher.build(data)
		data.metadata.dirty_terrain = false
		
	var water_arrays = null
	if data.metadata.dirty_water or needs_full:
		water_arrays = WaterMesher.build(data)
		data.metadata.dirty_water = false
		
	call_deferred("_on_chunk_meshed", data, terrain_arrays, water_arrays)

func _on_chunk_meshed(data: ChunkData, terrain_arrays, water_arrays) -> void:
	var key := Vector2i(data.cx, data.cz)
	_meshing_tasks.erase(key)
	
	if data.metadata.state == ChunkMetadata.State.UNLOADING:
		return
		
	data.metadata.state = ChunkMetadata.State.UPLOADING
	_queue_upload.append({ "data": data, "terrain_arrays": terrain_arrays, "water_arrays": water_arrays })

func _on_chunk_modified(key: Vector2i) -> void:
	var data := database.get_chunk(key)
	if data and not _meshing_tasks.has(key):
		_queue_meshing(data)

# ─── Object Pooling ───────────────────────────────────────────────────────────

func _get_pool_node() -> ChunkNode:
	if _pool.size() > 0:
		return _pool.pop_back()
	
	var node := ChunkNode.new()
	add_child(node)
	return node

func _return_pool_node(node: ChunkNode) -> void:
	node.reset()
	_pool.push_back(node)

# ─── Ecosystem Queries ────────────────────────────────────────────────────────

func find_nearest_animal(global_pos: Vector3, radius: float, type: String, max_y: float = 999.0) -> Node3D:
	var closest: Node3D = null
	var min_dist := radius
	
	for node in _active_nodes.values():
		var dist = node.global_position.distance_to(global_pos)
		if dist > radius + 20.0:
			continue
			
		for child in node.animals_container.get_children():
			if child is Animal and child.animal_type == type:
				if child.global_position.y > max_y:
					continue
				var d = child.global_position.distance_to(global_pos)
				if d < min_dist:
					min_dist = d
					closest = child
	return closest

func find_all_animals_in_radius(global_pos: Vector3, radius: float, type: String) -> Array[Node3D]:
	var results: Array[Node3D] = []
	for node in _active_nodes.values():
		var dist = node.global_position.distance_to(global_pos)
		if dist > radius + 20.0:
			continue
			
		for child in node.animals_container.get_children():
			if child is Animal and child.animal_type == type:
				if child.global_position.distance_to(global_pos) <= radius:
					results.append(child)
	return results

func find_nearest_food(global_pos: Vector3, radius: float) -> Dictionary:
	var closest_dict: Dictionary = {}
	var min_dist := radius
	
	for node in _active_nodes.values():
		var dist = node.global_position.distance_to(global_pos)
		if dist > radius + 20.0:
			continue
			
		# Check apples
		for i in range(node.apple_ground_positions.size()):
			var wpos = node.global_position + node.apple_ground_positions[i]
			var d = wpos.distance_to(global_pos)
			if d < min_dist:
				min_dist = d
				closest_dict = {"chunk": node, "type": "apple", "index": i, "position": wpos}
				
		# Check berries
		for i in range(node.berry_positions.size()):
			if node.berry_has_berry[i]:
				var wpos = node.global_position + node.berry_positions[i]
				var d = wpos.distance_to(global_pos)
				if d < min_dist:
					min_dist = d
					closest_dict = {"chunk": node, "type": "berry", "index": i, "position": wpos}
					
	return closest_dict

func consume_food(food_dict: Dictionary) -> void:
	if not food_dict.has("chunk") or not is_instance_valid(food_dict.chunk):
		return
	var chunk: ChunkNode = food_dict.chunk
	if food_dict.type == "apple":
		if chunk.has_method("consume_apple"):
			chunk.consume_apple(food_dict.index)
	elif food_dict.type == "berry":
		if chunk.has_method("consume_berry"):
			chunk.consume_berry(food_dict.index)
