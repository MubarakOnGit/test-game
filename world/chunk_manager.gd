class_name ChunkManager
extends Node

const RENDER_DISTANCE := 4
const MAX_UPLOADS_PER_FRAME := 2

var database: WorldDatabase
var world_seed: int

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

## Main tick for the chunk streaming lifecycle.
func tick(center_chunk: Vector2i) -> void:
	_update_streaming(center_chunk)
	_process_generation()

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
		
		# Commit to node
		ChunkRenderer.commit(node, data, terrain_arrays, water_arrays)
		
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
