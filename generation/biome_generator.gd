class_name BiomeGenerator

# ─── Biome IDs (used as vertex color encoding in the shader) ──────────────────
const GRASS := 0
const SAND  := 1
const ROCK  := 2
const SNOW  := 3

## Fills data.biomes[] and data.fertilities[].
## Requires heights[], temperatures[], moistures[], slopes[] to be populated.
static func generate(data: ChunkData) -> void:
	var cs := ChunkData.CHUNK_SIZE

	for lz in range(cs):
		for lx in range(cs):
			var bidx := ChunkData.bi(lx, lz)
			var hidx := ChunkData.hi(lx, lz)

			var h     := data.heights[hidx]
			var temp  := data.temperatures[hidx]
			var moist := data.moistures[hidx]

			var biome := _classify(data, lx, lz, h, temp, moist)
			data.biomes[bidx] = biome

			# Fertility: grass biome with high moisture = fertile farmland
			if biome == GRASS:
				data.fertilities[bidx] = clampf(moist * 1.3, 0.0, 1.0)
			else:
				data.fertilities[bidx] = 0.0

# ─── Classification ───────────────────────────────────────────────────────────

static func _classify(data: ChunkData, lx: int, lz: int, h: float, temp: float, _moist: float) -> int:
	if h >= 5.0:
		return SNOW
	elif h >= 4.0:
		return ROCK
	elif _is_shore(data, lx, lz):
		return SAND
	else:
		return GRASS

static func _is_shore(data: ChunkData, lx: int, lz: int) -> bool:
	# A tile is a shore if any of its 8 neighbors is at or below sea level
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			if data.heights[ChunkData.hi(lx + dx, lz + dz)] <= ChunkData.SEA_LEVEL:
				return true
	return false
