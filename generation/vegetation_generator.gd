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

			var biome := data.biomes[bidx]
			
			# Only spawn on GRASS
			if biome != 0: # BiomeGenerator.GRASS
				continue
				
			var h := data.heights[hidx]
			if h <= ChunkData.SEA_LEVEL or data.water_levels[hidx] > 0.0:
				continue
				
			var world_x := data.cx * cs + lx
			var world_z := data.cz * cs + lz
			
			# Sparse placement
			if not _is_tree_candidate(world_x, world_z, world_seed, 6):
				continue
				
			var density := _tree_noise.get_noise_2d(float(world_x), float(world_z))
			var scatter := _jitter_noise.get_noise_2d(float(world_x) * 0.5, float(world_z) * 0.5)

			if density < -0.1:
				continue
				
			# Randomly pick between Pine and Oak (using BIRCH index for Oak)
			var species = 0 # VegetationData.PINE
			if abs(hash(Vector2(world_x, world_z))) % 2 == 0:
				species = 1 # VegetationData.BIRCH
			
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
