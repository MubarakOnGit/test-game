class_name VegetationGenerator

# ─── Noise Fields ─────────────────────────────────────────────────────────────
static var _tree_noise:    FastNoiseLite = null  # Forest density / clustering
static var _species_noise: FastNoiseLite = null  # Species selection gradient
static var _jitter_noise:  FastNoiseLite = null  # Extra scatter at patch edges
static var _initialized:   bool = false

static func _ensure_init(world_seed: int) -> void:
	if _initialized:
		return
	_initialized = true

	# Primary density noise — controls where forest patches appear
	_tree_noise = FastNoiseLite.new()
	_tree_noise.seed = world_seed + 700
	_tree_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_tree_noise.frequency = 0.06

	# Species gradient — controls which species clusters where
	_species_noise = FastNoiseLite.new()
	_species_noise.seed = world_seed + 1337
	_species_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_species_noise.frequency = 0.04

	# Edge scatter — irregular forest patch borders
	_jitter_noise = FastNoiseLite.new()
	_jitter_noise.seed = world_seed + 2023
	_jitter_noise.noise_type = FastNoiseLite.TYPE_VALUE
	_jitter_noise.frequency = 0.15

## Populates data.vegetation with diverse, biome-aware tree placements.
static func generate(data: ChunkData, world_seed: int) -> void:
	_ensure_init(world_seed)

	var cs := ChunkData.CHUNK_SIZE

	for lz in range(cs):
		for lx in range(cs):
			var bidx := ChunkData.bi(lx, lz)
			var hidx := ChunkData.hi(lx, lz)

			var h     := data.heights[hidx]
			var biome := data.biomes[bidx]
			var moist := data.moistures[hidx]

			# ── 1. Water guards — both run first, before biome/density ───────
			# Guard A: Height — catches all tiles at/below sea level.
			#          biome_generator also classifies these as SAND now.
			if h <= ChunkData.SEA_LEVEL:
				continue
			# Guard B: water_levels — catches tiles above sea level that are
			#          flooded (river banks, lake shores). water_levels is now
			#          seeded by GenerationPipeline._seed_water() BEFORE
			#          vegetation runs, so this check is always reliable.
			if data.water_levels[hidx] > 0.0:
				continue

			# ── 3. Height gate — extra safety margin above water level ────────
			if h < 2.0 or h > 4.6:
				continue

			# ── 4. Clearance check for large meshes ───────────────────────────
			# Trees are scaled up very large (3-5 units) on a 1.0 unit grid.
			# If we place a tree 2 tiles away from water or a cliff, its branches
			# will still visually hang over the water or clip into the rock.
			var has_clearance := true
			var world_x   := data.cx * cs + lx
			var world_z   := data.cz * cs + lz
			
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if dx == 0 and dz == 0: continue
					
					# Dynamically compute the exact height in world space so we 
					# aren't limited by the chunk's 1-tile BORDER cache.
					var check_wx = float(world_x + dx)
					var check_wz = float(world_z + dz)
					var n_h = HeightGenerator._compute(check_wx, check_wz)
					
					# If any tile within a 2-tile radius is water (<= 0) or a cliff (>= 4.0)
					if n_h <= ChunkData.SEA_LEVEL or n_h >= 4.0:
						has_clearance = false
						break
						
				if not has_clearance:
					break
			if not has_clearance:
				continue

			# ── 4. Jittered grid — one candidate per NxN cell ────────────────
			var is_tree = biome == BiomeGenerator.GRASS and h <= 4.2 and _is_tree_candidate(world_x, world_z, world_seed, _cell_size_for_height(h))
			var is_bush = biome == BiomeGenerator.GRASS and h <= 4.0 and _is_tree_candidate(world_x, world_z, world_seed + 100, 3)
			var is_rock = _is_tree_candidate(world_x, world_z, world_seed + 200, 4)

			if not (is_tree or is_bush or is_rock):
				continue

			# ── 5. Density and Scatter logic ──────────────
			var density := _tree_noise.get_noise_2d(float(world_x), float(world_z))
			var scatter := _jitter_noise.get_noise_2d(float(world_x) * 0.5, float(world_z) * 0.5)

			var species = -1
			if is_tree and density >= _density_threshold(h, moist) and scatter >= -0.3:
				species = _pick_species(world_x, world_z, h, moist)
			elif is_bush and density >= -0.15:
				species = VegetationData.BUSH_A if scatter > 0.0 else VegetationData.ROSE_BUSH
			elif is_rock and scatter > -0.2:
				var rock_val = abs(hash(Vector2(world_x, world_z))) % 3
				if rock_val == 0: species = VegetationData.ROCK_A
				elif rock_val == 1: species = VegetationData.ROCK_B
				else: species = VegetationData.ROCK_C
			
			if species == -1:
				continue

			# Small sub-tile offset for natural feel (tight to avoid water edge crossings)
			var off_x := clampf(scatter * 0.15, -0.15, 0.15)
			var off_z := clampf(density  * 0.15, -0.15, 0.15)
			data.vegetation.add(species, float(lx) + 0.5 + off_x, float(lz) + 0.5 + off_z)

# ─── Species Selection ────────────────────────────────────────────────────────

static func _pick_species(world_x: int, world_z: int, h: float, moist: float) -> int:
	var sn := _species_noise.get_noise_2d(float(world_x), float(world_z))  # -1..1

	# Alpine pine: dominates at height > 3.2, or cold dense patches at high ground
	if h > 3.2:
		return VegetationData.PINE
	if h > 2.8 and sn < -0.1:
		return VegetationData.PINE

	# Birch: moisture-loving, thrives near water edges and moist meadows
	if moist > 0.65 and h < 2.6:
		return VegetationData.BIRCH
	if moist > 0.5 and sn > 0.4 and h < 2.8:
		return VegetationData.BIRCH

	# Simple Tree: open lowland canopy, dry or average moisture
	if h < 2.4 and moist < 0.5:
		return VegetationData.SIMPLE
	if sn < -0.3 and h < 2.6:
		return VegetationData.SIMPLE

	# Stylized: mid-elevation mixed forest backbone
	return VegetationData.STYLIZED

# ─── Density Thresholds ───────────────────────────────────────────────────────
# Higher value = fewer trees pass. Tuned for natural spacing with larger cell sizes.
#
# | Elevation  | Cell Size | Threshold | Effect                          |
# |------------|----------:| ---------:|-------------------------------- |
# | Lowlands   |         5 |     -0.05 | Comfortable forest spacing      |
# | Hills      |         6 |      0.10 | Natural clusters with glades    |
# | Mountains  |         8 |      0.25 | Sparse alpine pine groves       |

static func _density_threshold(h: float, moist: float) -> float:
	if h > 3.0:
		return 0.25   # Mountains — very sparse
	if h > 2.8:
		return 0.10   # Hills — natural clusters
	if moist > 0.6:
		return -0.05  # Wet lowland — lush but not congested
	return -0.05      # Lowlands default

# ─── Jittered Grid ───────────────────────────────────────────────────────────
# Cell sizes control minimum distance between trees.
# Larger cell = sparser forest.
#
# | Elevation  | Cell size | Min tree spacing |
# |------------|----------:|------------------|
# | Lowlands   |         5 | 5 tiles          |
# | Hills      |         6 | 6 tiles          |
# | Mountains  |         8 | 8 tiles          |

static func _cell_size_for_height(h: float) -> int:
	if h > 3.2: return 8  # Alpine — very sparse
	if h > 2.8: return 6  # Hills — moderate spacing
	return 5               # Lowland forest — comfortable density

## Returns true for exactly ONE tile within each NxN cell.
## The winning tile is deterministic but randomly offset inside the cell,
## creating organic scatter without any grid-line artifacts.
static func _is_tree_candidate(world_x: int, world_z: int, world_seed: int, cell_size: int) -> bool:
	var cell_x := floori(float(world_x) / float(cell_size))
	var cell_z := floori(float(world_z) / float(cell_size))

	# Hash the cell + world seed → unique jitter offset per cell
	var h: int = abs(hash(Vector3i(cell_x, cell_z, world_seed)))
	var offset_x: int = h % cell_size
	var offset_z: int = (h / cell_size) % cell_size

	# The single chosen tile within this cell
	var chosen_x := cell_x * cell_size + offset_x
	var chosen_z := cell_z * cell_size + offset_z

	return world_x == chosen_x and world_z == chosen_z
