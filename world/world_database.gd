class_name WorldDatabase

# ─── Single Source of Truth ───────────────────────────────────────────────────
# Only WorldDatabase creates, owns, and destroys ChunkData objects.
# ChunkManager streams. Renderers render. Simulation simulates.
# None of them own data — they borrow it from here.

var _chunks: Dictionary = {}   # Vector2i → ChunkData

# ─── Query ────────────────────────────────────────────────────────────────────

func has_chunk(key: Vector2i) -> bool:
	return _chunks.has(key)

func get_chunk(key: Vector2i) -> ChunkData:
	return _chunks.get(key, null)

func all_keys() -> Array:
	return _chunks.keys()

func chunk_count() -> int:
	return _chunks.size()

# ─── Mutation ─────────────────────────────────────────────────────────────────

func store_chunk(data: ChunkData) -> void:
	var key := Vector2i(data.cx, data.cz)
	_chunks[key] = data

func remove_chunk(key: Vector2i) -> void:
	_chunks.erase(key)

func mark_terrain_dirty(key: Vector2i) -> void:
	var d := get_chunk(key)
	if d:
		d.metadata.mark_terrain_dirty()

func mark_vegetation_dirty(key: Vector2i) -> void:
	var d := get_chunk(key)
	if d:
		d.metadata.mark_vegetation_dirty()

# ─── World-Space Height Lookup ─────────────────────────────────────────────────

func get_height_at_world(world_x: int, world_z: int) -> float:
	var cx := floori(float(world_x) / float(ChunkData.CHUNK_SIZE))
	var cz := floori(float(world_z) / float(ChunkData.CHUNK_SIZE))
	var data := get_chunk(Vector2i(cx, cz))
	if data == null:
		return 0.0
	var lx := world_x - cx * ChunkData.CHUNK_SIZE
	var lz := world_z - cz * ChunkData.CHUNK_SIZE
	return data.get_height(lx, lz)

# ─── World Modification ───────────────────────────────────────────────────────

func modify_height(world_x: int, world_z: int, new_height: float) -> void:
	var cx := floori(float(world_x) / float(ChunkData.CHUNK_SIZE))
	var cz := floori(float(world_z) / float(ChunkData.CHUNK_SIZE))
	var key := Vector2i(cx, cz)
	var data := get_chunk(key)
	if data == null:
		return
	
	var lx := world_x - cx * ChunkData.CHUNK_SIZE
	var lz := world_z - cz * ChunkData.CHUNK_SIZE
	
	data.set_height(lx, lz, new_height)
	data.metadata.mark_terrain_dirty()
	
	# Emit event for the primary chunk
	WorldEventBus.chunk_modified.emit(key)
	
	# Handle chunk boundaries
	if lx == 0:
		var n_key = key + Vector2i(-1, 0)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
	elif lx == ChunkData.CHUNK_SIZE - 1:
		var n_key = key + Vector2i(1, 0)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
		
	if lz == 0:
		var n_key = key + Vector2i(0, -1)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
	elif lz == ChunkData.CHUNK_SIZE - 1:
		var n_key = key + Vector2i(0, 1)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
		
	# Corner boundaries
	if lx == 0 and lz == 0:
		var n_key = key + Vector2i(-1, -1)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
	elif lx == ChunkData.CHUNK_SIZE - 1 and lz == 0:
		var n_key = key + Vector2i(1, -1)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
	elif lx == 0 and lz == ChunkData.CHUNK_SIZE - 1:
		var n_key = key + Vector2i(-1, 1)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
	elif lx == ChunkData.CHUNK_SIZE - 1 and lz == ChunkData.CHUNK_SIZE - 1:
		var n_key = key + Vector2i(1, 1)
		if has_chunk(n_key): WorldEventBus.chunk_modified.emit(n_key)
