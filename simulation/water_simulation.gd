class_name WaterSimulation

const MAX_FLOW = 1.0 # Max water that can flow per tick
const MIN_FLOW = 0.01

## Simulates one step of water cellular automata for a single chunk.
## Mutates ChunkData and triggers chunk updates if water flows to neighbors.
static func step(data: ChunkData, database: WorldDatabase) -> void:
	var cs = ChunkData.CHUNK_SIZE
	
	# We need a copy of the water levels to read from while writing to the real array,
	# so we don't process the same water twice in one tick.
	var old_water = data.water_levels.duplicate()
	var dirty = false
	
	var neighbors_to_update = {} # Dictionary of Vector2i keys to ChunkData

	for lz in range(cs):
		for lx in range(cs):
			var idx = ChunkData.hi(lx, lz)
			var w = old_water[idx]
			
			if w <= 0.001:
				continue
				
			var h = data.heights[idx]
			var total_h = h + w
			
			# Find lowest neighbors
			var h_n = _get_neighbor_total_height(data, database, old_water, lx, lz - 1)
			var h_s = _get_neighbor_total_height(data, database, old_water, lx, lz + 1)
			var h_e = _get_neighbor_total_height(data, database, old_water, lx + 1, lz)
			var h_w = _get_neighbor_total_height(data, database, old_water, lx - 1, lz)
			
			# Collect all neighbors that are lower than us
			var candidates = []
			if total_h > h_n: candidates.append({"dx": 0, "dz": -1, "h": h_n})
			if total_h > h_s: candidates.append({"dx": 0, "dz": 1, "h": h_s})
			if total_h > h_e: candidates.append({"dx": 1, "dz": 0, "h": h_e})
			if total_h > h_w: candidates.append({"dx": -1, "dz": 0, "h": h_w})
			
			if candidates.size() == 0:
				continue
				
			# Sort by lowest first
			candidates.sort_custom(func(a, b): return a.h < b.h)
			
			var flow_amount = minf(w, MAX_FLOW) / candidates.size()
			if flow_amount < MIN_FLOW:
				flow_amount = w # Flow all remaining if it's very small
			
			for cand in candidates:
				# Flow to neighbor
				var diff = total_h - cand.h
				var actual_flow = minf(flow_amount, diff / 2.0) # Don't overshoot
				if actual_flow <= 0.0: continue
				
				# Remove from us
				data.water_levels[idx] -= actual_flow
				w -= actual_flow
				dirty = true
				
				# Add to neighbor
				_add_water_to_neighbor(data, database, neighbors_to_update, lx + cand.dx, lz + cand.dz, actual_flow)
				
				if w <= 0.0: break
	
	if dirty:
		data.metadata.mark_water_dirty()
		WorldEventBus.chunk_modified.emit(Vector2i(data.cx, data.cz))
		
	for n_key in neighbors_to_update:
		var n_data = neighbors_to_update[n_key]
		n_data.metadata.mark_water_dirty()
		WorldEventBus.chunk_modified.emit(n_key)

static func _get_neighbor_total_height(data: ChunkData, database: WorldDatabase, old_water: PackedFloat32Array, lx: int, lz: int) -> float:
	var cs = ChunkData.CHUNK_SIZE
	
	if lx >= 0 and lx < cs and lz >= 0 and lz < cs:
		var idx = ChunkData.hi(lx, lz)
		return data.heights[idx] + old_water[idx]
	else:
		# It's in another chunk
		var dcx = 0
		if lx < 0: dcx = -1
		elif lx >= cs: dcx = 1
		
		var dcz = 0
		if lz < 0: dcz = -1
		elif lz >= cs: dcz = 1
		
		var n_key = Vector2i(data.cx + dcx, data.cz + dcz)
		var n_data = database.get_chunk(n_key)
		if n_data == null:
			return 9999.0 # Can't flow into unloaded chunks
			
		var n_lx = (lx + cs) % cs
		var n_lz = (lz + cs) % cs
		var n_idx = ChunkData.hi(n_lx, n_lz)
		
		return n_data.heights[n_idx] + n_data.water_levels[n_idx]

static func _add_water_to_neighbor(data: ChunkData, database: WorldDatabase, neighbors_to_update: Dictionary, lx: int, lz: int, amount: float) -> void:
	var cs = ChunkData.CHUNK_SIZE
	
	if lx >= 0 and lx < cs and lz >= 0 and lz < cs:
		var idx = ChunkData.hi(lx, lz)
		data.water_levels[idx] += amount
	else:
		# It's in another chunk
		var dcx = 0
		if lx < 0: dcx = -1
		elif lx >= cs: dcx = 1
		
		var dcz = 0
		if lz < 0: dcz = -1
		elif lz >= cs: dcz = 1
		
		var n_key = Vector2i(data.cx + dcx, data.cz + dcz)
		var n_data = database.get_chunk(n_key)
		if n_data != null:
			var n_lx = (lx + cs) % cs
			var n_lz = (lz + cs) % cs
			var n_idx = ChunkData.hi(n_lx, n_lz)
			n_data.water_levels[n_idx] += amount
			neighbors_to_update[n_key] = n_data
