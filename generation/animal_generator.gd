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
	
	for lz in range(cs):
		for lx in range(cs):
			var world_x = data.cx * cs + lx
			var world_z = data.cz * cs + lz
			
			# Sparse grid check to avoid clustering (e.g. 1 per 8x8 cell)
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
				
			var hidx = ChunkData.hi(lx, lz)
			var h = data.heights[hidx]
			var is_water = h <= ChunkData.SEA_LEVEL or data.water_levels[hidx] > 0.0
			
			var animal_type = ""
			var water_animal = false
			
			# Decide which animal to spawn
			var pick = h_seed % 100
			
			if is_water:
				if h > -0.6:
					continue # Don't spawn fish in shallow puddles where they stick out
				water_animal = true
				if pick < 40: animal_type = "Fish"
				elif pick < 80: animal_type = "Fish-XWl86YFtpF"
				elif pick < 90: animal_type = "Fish-BEcU9rjiAq"
				else: animal_type = "Shark by Quaternius - YYsK3gRCBZ"
			else:
				# Land animals
				if pick < 30: animal_type = "wolf"
				elif pick < 60: animal_type = "Stag by Quaternius - tQdzbZ1Cmw"
				elif pick < 90: animal_type = "blocky_rabbit"
				else: animal_type = "bird_5_-_animated_low_poly" # Maybe birds just hop around
			
			if animal_type != "":
				data.animals.push_back({
					"type": animal_type,
					"x": float(lx) + 0.5,
					"y": h,
					"z": float(lz) + 0.5,
					"is_water": water_animal
				})
