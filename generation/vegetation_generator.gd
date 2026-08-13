class_name VegetationGenerator

static var _tree_noise: FastNoiseLite = null
static var _initialized: bool = false

static func _ensure_init(world_seed: int) -> void:
	if _initialized:
		return
	_initialized = true

	_tree_noise = FastNoiseLite.new()
	_tree_noise.seed = world_seed + 700
	_tree_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_tree_noise.frequency = 0.08

## Populates data.vegetation with tree placements based on biome and height.
static func generate(data: ChunkData, world_seed: int) -> void:

	_ensure_init(world_seed)

	var cs := ChunkData.CHUNK_SIZE
	
	for lz in range(cs):
		for lx in range(cs):
			var bidx := ChunkData.bi(lx, lz)
			var hidx := ChunkData.hi(lx, lz)
			
			var biome := data.biomes[bidx]
			var h := data.heights[hidx]
			
			# Only place trees on grass (height 2-3)
			if biome != BiomeGenerator.GRASS or h < 2.0 or h > 3.0:
				continue
				
			# Jittered grid check to prevent overlapping
			var world_x := data.cx * cs + lx
			var world_z := data.cz * cs + lz
			if not _is_tree_candidate(world_x, world_z, world_seed):
				continue
				
			# Forest biome noise
			var t := _tree_noise.get_noise_2d(float(world_x), float(world_z))
			if t < 0.0: # ~50% chance in a candidate cell
				continue
				
			var species := VegetationData.OAK if t > 0.5 else VegetationData.PINE
			
			# Center in the tile (local offset 0.5)
			data.vegetation.add(species, float(lx) + 0.5, float(lz) + 0.5)

## Ensures exactly one tree candidate per 4x4 area to prevent overlap.
static func _is_tree_candidate(world_x: int, world_z: int, world_seed: int) -> bool:
	var cell_x := floori(float(world_x) / 4.0)
	var cell_z := floori(float(world_z) / 4.0)
	
	# Pseudo-random choice within the 4x4 cell
	# Include world_seed so different worlds have different tree placements
	var h: int = abs(hash(Vector3i(cell_x, cell_z, world_seed)))
	var offset_x: int = h % 4
	var offset_z: int = (h / 4) % 4
	
	var chosen_x := cell_x * 4 + offset_x
	var chosen_z := cell_z * 4 + offset_z
	
	return world_x == chosen_x and world_z == chosen_z
