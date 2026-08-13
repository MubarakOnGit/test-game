class_name VegetationData

# ─── Species IDs ──────────────────────────────────────────────────────────────
const PINE := 0
const OAK  := 1

# ─── Placement Data ───────────────────────────────────────────────────────────
# Stores LOGICAL data only — no Transform3D.
# The renderer rebuilds transforms deterministically from (species, local_x, local_z)
# + a height lookup from ChunkData. This keeps save files tiny.
var species:  PackedByteArray     # VegetationData.PINE or .OAK per tree
var local_xs: PackedFloat32Array  # local X within chunk (0.0 – CHUNK_SIZE)
var local_zs: PackedFloat32Array  # local Z within chunk (0.0 – CHUNK_SIZE)

# ─── API ──────────────────────────────────────────────────────────────────────

func count() -> int:
	return species.size()

func add(sp: int, lx: float, lz: float) -> void:
	species.push_back(sp)
	local_xs.push_back(lx)
	local_zs.push_back(lz)

func count_of(sp: int) -> int:
	var n := 0
	for i in species.size():
		if species[i] == sp:
			n += 1
	return n
