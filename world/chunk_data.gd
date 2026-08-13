class_name ChunkData

# ─── Dimensions ───────────────────────────────────────────────────────────────
const CHUNK_SIZE := 16
const BORDER     := 1
# BSIZE = bordered dimension: includes 1 tile on each side for face-culling neighbors
const BSIZE      := CHUNK_SIZE + 2 * BORDER   # = 18

const SEA_LEVEL  := 0.0
const BOTTOM_Y   := -2.0
const TILE_SIZE  := 1.0

# ─── Identity ─────────────────────────────────────────────────────────────────
var cx:         int   # chunk X coordinate (in chunk units)
var cz:         int   # chunk Z coordinate
var world_seed: int

# ─── Bordered Arrays (BSIZE * BSIZE = 324 elements) ──────────────────────────
# Indexed via hi(lx, lz). lx/lz range from -BORDER to CHUNK_SIZE+BORDER-1.
var heights:      PackedFloat32Array  # terrain height (world Y) per tile
var temperatures: PackedFloat32Array  # 0.0 (cold) – 1.0 (hot)
var moistures:    PackedFloat32Array  # 0.0 (dry)  – 1.0 (wet)
var slopes:       PackedFloat32Array  # max height delta to any neighbor
var water_levels: PackedFloat32Array  # dynamic cellular automata water volume

# ─── Core Arrays (CHUNK_SIZE * CHUNK_SIZE = 256 elements) ─────────────────────
# Indexed via bi(lx, lz). lx/lz range from 0 to CHUNK_SIZE-1.
var biomes:      PackedByteArray      # BiomeGenerator constants
var fertilities: PackedFloat32Array   # 0.0–1.0

# ─── Object Placement ─────────────────────────────────────────────────────────
var vegetation: VegetationData

# ─── Metadata ─────────────────────────────────────────────────────────────────
var metadata: ChunkMetadata

# ─── Index Helpers ────────────────────────────────────────────────────────────

# Bordered index: lx and lz may range from -BORDER to CHUNK_SIZE + BORDER - 1
static func hi(lx: int, lz: int) -> int:
	return (lz + BORDER) * BSIZE + (lx + BORDER)

# Core index: lx and lz must be in [0, CHUNK_SIZE-1]
static func bi(lx: int, lz: int) -> int:
	return lz * CHUNK_SIZE + lx

# ─── Construction ─────────────────────────────────────────────────────────────

## Factory — the only way to create a ChunkData. All fields allocated here.
static func create(cx_: int, cz_: int, seed: int) -> ChunkData:
	var d := ChunkData.new()
	d.cx         = cx_
	d.cz         = cz_
	d.world_seed = seed

	var bsq := BSIZE * BSIZE
	var csq := CHUNK_SIZE * CHUNK_SIZE

	d.heights      = PackedFloat32Array(); d.heights.resize(bsq)
	d.temperatures = PackedFloat32Array(); d.temperatures.resize(bsq)
	d.moistures    = PackedFloat32Array(); d.moistures.resize(bsq)
	d.slopes       = PackedFloat32Array(); d.slopes.resize(bsq)
	d.water_levels = PackedFloat32Array(); d.water_levels.resize(bsq)

	d.biomes       = PackedByteArray();    d.biomes.resize(csq)
	d.fertilities  = PackedFloat32Array(); d.fertilities.resize(csq)

	d.vegetation = VegetationData.new()
	d.metadata   = ChunkMetadata.new()
	return d

# ─── Convenience Accessors ────────────────────────────────────────────────────

func get_height(lx: int, lz: int) -> float:
	return heights[hi(lx, lz)]

func set_height(lx: int, lz: int, value: float) -> void:
	heights[hi(lx, lz)] = value

func get_biome(lx: int, lz: int) -> int:
	return biomes[bi(lx, lz)]

## World-space X origin of this chunk
func world_origin_x() -> float:
	return float(cx * CHUNK_SIZE) * TILE_SIZE

## World-space Z origin of this chunk
func world_origin_z() -> float:
	return float(cz * CHUNK_SIZE) * TILE_SIZE
