class_name AnimalGenerator

static var _initialized: bool = false
static var _animal_noise: FastNoiseLite = null

static func _ensure_init(world_seed: int) -> void:
	if _initialized:
		return
	_initialized = true
	
	_animal_noise = FastNoiseLite.new()
	_animal_noise.seed = world_seed + 9999
	_animal_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_animal_noise.frequency = 0.08

static func generate(data: ChunkData, world_seed: int) -> void:
	_ensure_init(world_seed)
	
	var cs := ChunkData.CHUNK_SIZE
	
	var water_tiles: Array[Vector2i] = []
	
	# 1. Land Animals Generation
	for lz in range(cs):
		for lx in range(cs):
			var world_x = data.cx * cs + lx
			var world_z = data.cz * cs + lz
			
			var hidx = ChunkData.hi(lx, lz)
			var h = data.heights[hidx]
			var is_water = h <= ChunkData.SEA_LEVEL or data.water_levels[hidx] > 0.0
			
			if is_water:
				water_tiles.append(Vector2i(lx, lz))
				continue
				
			# Sparse grid check for land animals (1 per 8x8 cell)
			var cell_size = 8
			var cell_x = floori(float(world_x) / float(cell_size))
			var cell_z = floori(float(world_z) / float(cell_size))
			var h_seed = abs(hash(Vector3i(cell_x, cell_z, world_seed + 5000)))
			
			var offset_x = h_seed % cell_size
			var offset_z = (h_seed / cell_size) % cell_size
			
			var chosen_x = cell_x * cell_size + offset_x
			var chosen_z = cell_z * cell_size + offset_z
			
			if world_x != chosen_x or world_z != chosen_z:
				continue
				
			var noise_val = _animal_noise.get_noise_2d(float(world_x), float(world_z))
			if noise_val < 0.2: # Spawn density threshold
				continue
				
			var pick = h_seed % 100
			
			# Land animals:
			# 0–59  (60%) → Rabbits (small groups of 1–3)
			# 60–79 (20%) → Wolf pack (2–4 wolves)
			# 80–99 (20%) → Nothing (natural sparsity)
			if pick < 60:
				var rabbit_count = 1 + (h_seed % 3)
				for i in range(rabbit_count):
					var angle = float(i) * (TAU / float(rabbit_count))
					var dist = randf_range(0.5, 1.5)
					data.animals.push_back({
						"type": "blocky_rabbit",
						"x": float(lx) + 0.5 + (cos(angle) * dist),
						"y": h,
						"z": float(lz) + 0.5 + (sin(angle) * dist),
						"is_water": false
					})
			elif pick < 80:
				var pack_size = 2 + (h_seed % 3)
				for i in range(pack_size):
					var angle = float(i) * (TAU / float(pack_size))
					var dist = 1.0 + (float(h_seed % 10) / 10.0)
					data.animals.push_back({
						"type": "wolf",
						"x": float(lx) + 0.5 + (cos(angle) * dist),
						"y": h,
						"z": float(lz) + 0.5 + (sin(angle) * dist),
						"is_water": false
					})

	# 2. Water Animals Generation (Crocodiles scaled to water size)
	var water_count := water_tiles.size()
	if water_count >= 4:
		var chunk_seed = abs(hash(Vector3i(data.cx, data.cz, world_seed + 777)))
		var croc_count := 0
		if water_count >= 40:
			croc_count = 2 + (chunk_seed % 2) # 2 to 3 crocs in large water bodies
		elif water_count >= 12:
			croc_count = 1 + (chunk_seed % 2) # 1 to 2 crocs in medium rivers
		elif chunk_seed % 100 < 50:
			croc_count = 1 # 50% chance in small ponds
			
		for i in range(croc_count):
			var tile_idx = (chunk_seed + i * 17) % water_tiles.size()
			var tile = water_tiles[tile_idx]
			var hidx = ChunkData.hi(tile.x, tile.y)
			data.animals.push_back({
				"type": "crocodile",
				"x": float(tile.x) + 0.5,
				"y": data.heights[hidx],
				"z": float(tile.y) + 0.5,
				"is_water": true
			})

