class_name VegetationData

# ─── Species IDs ──────────────────────────────────────────────────────────────
# Four distinct species using the new GLB assets from assets/trees/
const PINE      := 0  # Pine Tree.glb
const APPLE_TREE:= 1  # Birch Tree.glb (Repurposed as Apple Tree)
const SIMPLE    := 2  # Simple Tree.glb
const STYLIZED  := 3  # Stylized Tree.glb
const BUSH_A    := 4  # Bush by Jarlan Perez
const ROSE_BUSH := 5  # Rose bush by Poly by Google
const ROCK_A    := 6  # Rock by Quaternius
const ROCK_B    := 7  # Rocks by Don Carson
const ROCK_C    := 8  # Rocks by Quaternius

# ─── Placement Data ───────────────────────────────────────────────────────────
# Stores LOGICAL data only — no Transform3D.
# The renderer rebuilds transforms deterministically from (species, local_x, local_z)
# + a height lookup from ChunkData. This keeps save files tiny.
var species:  PackedByteArray     # species ID per tree (PINE / APPLE_TREE / SIMPLE / STYLIZED)
var local_xs: PackedFloat32Array  # local X within chunk (0.0 – CHUNK_SIZE)
var local_zs: PackedFloat32Array  # local Z within chunk (0.0 – CHUNK_SIZE)

# ─── Berry Bush Placement Data ────────────────────────────────────────────────
# Berry bushes are tracked separately because they have mutable berry state.
# (local_x, local_z) within the chunk — height is looked up from ChunkData at render time.
var berry_local_xs: PackedFloat32Array
var berry_local_zs: PackedFloat32Array

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

func add_berry_bush(lx: float, lz: float) -> void:
	berry_local_xs.push_back(lx)
	berry_local_zs.push_back(lz)

func berry_bush_count() -> int:
	return berry_local_xs.size()
