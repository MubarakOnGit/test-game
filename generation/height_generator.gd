class_name HeightGenerator

# ─── Noise Instances ──────────────────────────────────────────────────────────
static var _base_noise:     FastNoiseLite = null
static var _mountain_noise: FastNoiseLite = null
static var _river_noise:    FastNoiseLite = null
static var _lake_noise:     FastNoiseLite = null
static var _initialized:    bool = false

static func _ensure_init(world_seed: int) -> void:
	if _initialized:
		return
	_initialized = true

	# Base terrain shape — large rolling hills
	_base_noise = FastNoiseLite.new()
	_base_noise.seed = world_seed + 111
	_base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_base_noise.frequency = 0.012
	_base_noise.fractal_octaves = 3

	# Ridge noise for mountains
	_mountain_noise = FastNoiseLite.new()
	_mountain_noise.seed = world_seed + 222
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_mountain_noise.frequency = 0.008
	_mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountain_noise.fractal_octaves = 4

	# River noise — low frequency meanders
	_river_noise = FastNoiseLite.new()
	_river_noise.seed = world_seed + 333
	_river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_river_noise.frequency = 0.005
	_river_noise.fractal_octaves = 2

	# Lake noise — very low frequency blobs to form basins
	_lake_noise = FastNoiseLite.new()
	_lake_noise.seed = world_seed + 444
	_lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_lake_noise.frequency = 0.018   # medium scale — smaller than rivers
	_lake_noise.fractal_octaves = 2

# ─── Public API ───────────────────────────────────────────────────────────────

## Fills data.heights[] — bordered (BSIZE × BSIZE) array.
static func generate(data: ChunkData, world_seed: int) -> void:
	_ensure_init(world_seed)

	var bw := ChunkData.BSIZE
	var b  := ChunkData.BORDER
	var cs := ChunkData.CHUNK_SIZE

	for bz in range(bw):
		for bx in range(bw):
			var wx := float(data.cx * cs + (bx - b))
			var wz := float(data.cz * cs + (bz - b))
			data.heights[bz * bw + bx] = _compute(wx, wz)

# ─── Height Formula ───────────────────────────────────────────────────────────

static func _compute(wx: float, wz: float) -> float:
	var base_val := _base_noise.get_noise_2d(wx, wz)
	var h := remap(base_val, -1.0, 1.0, 0.5, 4.5)

	# ── Mountains ─────────────────────────────────────────────────────────────
	var mtn_val := _mountain_noise.get_noise_2d(wx, wz)
	var mtn : float = 1.0 - mtn_val
	if mtn > 0.4 and base_val > 0.2:
		h += (mtn - 0.4) * 5.0

	# ── Rivers ────────────────────────────────────────────────────────────────
	# abs(riv_val) is near 0 at the river centerline → carves a U-shaped channel
	var riv_val := _river_noise.get_noise_2d(wx, wz)
	var river_depth : float = 1.0 - absf(riv_val)
	# Lower threshold (0.75) = wider, more frequent rivers
	if river_depth > 0.75:
		var carve : float = (river_depth - 0.75) / 0.25  # 0→1 as we near centre
		h -= carve * carve * 6.0   # quadratic — smooth U-channel, max -6 at centreline

	# ── Lakes ─────────────────────────────────────────────────────────────────
	# Lake basins only form in low-lying areas (base_val < 0.1) so they don't
	# punch through mountains.
	var lake_val := _lake_noise.get_noise_2d(wx, wz)
	if lake_val > 0.35 and base_val < 0.1:
		var lake_depth : float = (lake_val - 0.35) / 0.65  # normalise 0→1
		h -= lake_depth * lake_depth * 4.0   # gentle bowl shape, max -4

	return floor(h)
