class_name ClimateGenerator

static var _temp_noise:  FastNoiseLite = null
static var _moist_noise: FastNoiseLite = null
static var _initialized: bool = false

static func _ensure_init(world_seed: int) -> void:
	if _initialized:
		return
	_initialized = true

	_temp_noise = FastNoiseLite.new()
	_temp_noise.seed            = world_seed + 500
	_temp_noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX
	_temp_noise.frequency       = 0.003
	_temp_noise.fractal_octaves = 2

	_moist_noise = FastNoiseLite.new()
	_moist_noise.seed            = world_seed + 600
	_moist_noise.noise_type      = FastNoiseLite.TYPE_SIMPLEX
	_moist_noise.frequency       = 0.004
	_moist_noise.fractal_octaves = 2

## Fills data.temperatures[] and data.moistures[].
## Requires data.heights[] to be populated first.
static func generate(data: ChunkData, world_seed: int) -> void:
	_ensure_init(world_seed)

	var bw := ChunkData.BSIZE
	var b  := ChunkData.BORDER
	var cs := ChunkData.CHUNK_SIZE

	for bz in range(bw):
		for bx in range(bw):
			var wx  := float(data.cx * cs + (bx - b))
			var wz  := float(data.cz * cs + (bz - b))
			var idx := bz * bw + bx
			var h   := data.heights[idx]

			# Base temperature from noise; decreases with elevation (lapse rate)
			var base_t := remap(_temp_noise.get_noise_2d(wx, wz), -1.0, 1.0, 0.0, 1.0)
			data.temperatures[idx] = clampf(base_t - h * 0.06, 0.0, 1.0)

			# Moisture from independent noise layer
			data.moistures[idx] = remap(_moist_noise.get_noise_2d(wx, wz), -1.0, 1.0, 0.0, 1.0)
