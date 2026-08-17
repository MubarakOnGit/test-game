class_name GrassRenderer

# ── Shared mesh resources (loaded once) ───────────────────────────────────────
static var _mesh_a: Mesh = null  # Short / young
static var _mesh_b: Mesh = null  # Medium / thick
static var _mesh_c: Mesh = null  # Tall / old

# ── Placement config ──────────────────────────────────────────────────────────
# Grid cell (in tile units): 1 grass per CELL x CELL area max
const CELL_TILES        := 2
# Patch noise threshold — raises this to get fewer, more distinct patches
const DENSITY_THRESHOLD := 0.35
# Scale ranges per variation
const SCALE_A := [0.7, 1.1]   # Short young: small variance
const SCALE_B := [0.9, 1.4]   # Medium: moderate variance
const SCALE_C := [1.0, 1.6]   # Tall: biggest, most variance

static func _ensure_resources() -> void:
	if _mesh_a == null:
		_mesh_a = _load_mesh("res://assets/grass/grass_a.glb")
	if _mesh_b == null:
		_mesh_b = _load_mesh("res://assets/grass/grass_b.glb")
	if _mesh_c == null:
		_mesh_c = _load_mesh("res://assets/grass/grass_c.glb")

static func _load_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	if packed == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.3, 0.6)
		return bm
	var scene := packed.instantiate()
	var m := _find_mesh(scene)
	scene.queue_free()
	return m if m != null else BoxMesh.new()

static func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		var m: Mesh = (node as MeshInstance3D).mesh
		if m != null:
			for i in m.get_surface_count():
				var mat: Material = m.surface_get_material(i)
				if mat == null:
					var sm := StandardMaterial3D.new()
					sm.vertex_color_use_as_albedo = true
					sm.metallic = 0.0
					sm.roughness = 1.0
					m.surface_set_material(i, sm)
				elif mat is StandardMaterial3D:
					(mat as StandardMaterial3D).vertex_color_use_as_albedo = true
					(mat as StandardMaterial3D).metallic = 0.0
					(mat as StandardMaterial3D).roughness = 1.0
		return m
	for child in node.get_children():
		var r := _find_mesh(child)
		if r != null:
			return r
	return null

## Scatter 3 grass variations across this chunk's grass tiles.
static func commit(node: ChunkNode, data: ChunkData) -> void:
	_ensure_resources()

	var cs: int   = ChunkData.CHUNK_SIZE
	var ts: float = ChunkData.TILE_SIZE

	# Separate position/transform lists per variation
	var trans_a: Array[Transform3D] = []
	var trans_b: Array[Transform3D] = []
	var trans_c: Array[Transform3D] = []
	var color_a: Array[Color] = []
	var color_b: Array[Color] = []
	var color_c: Array[Color] = []

	for lz in range(cs):
		for lx in range(cs):
			var bidx := ChunkData.bi(lx, lz)
			var hidx := ChunkData.hi(lx, lz)

			if data.biomes[bidx] != 0:
				continue
			var h: float = data.heights[hidx]
			if h <= ChunkData.SEA_LEVEL or data.water_levels[hidx] > 0.0:
				continue

			var world_x: float = data.cx * cs * ts + lx * ts
			var world_z: float = data.cz * cs * ts + lz * ts

			# ── Jittered grid: max one tuft per CELL_TILES x CELL_TILES area ──
			var cell_x: int = int(world_x / (ts * CELL_TILES))
			var cell_z: int = int(world_z / (ts * CELL_TILES))
			var cseed: int  = abs(hash(Vector2i(cell_x, cell_z)))

			var chosen_lx: int = cseed % CELL_TILES
			var chosen_lz: int = (cseed / CELL_TILES) % CELL_TILES
			if (lx % CELL_TILES) != chosen_lx or (lz % CELL_TILES) != chosen_lz:
				continue

			# ── Density noise: distinct patches with clear bare areas ──────────
			var noise_val: float = _patch_noise(world_x, world_z)
			if noise_val < DENSITY_THRESHOLD:
				continue

			# No grass on steep slopes
			if data.slopes[hidx] > 0.7:
				continue

			# ── Jitter position within tile ───────────────────────────────────
			var jx: float = (float(cseed % 100) / 100.0 - 0.5) * ts * 0.55
			var jz: float = (float((cseed / 100) % 100) / 100.0 - 0.5) * ts * 0.55
			var pos := Vector3(lx * ts + ts * 0.5 + jx, h, lz * ts + ts * 0.5 + jz)

			# ── Variation selection ────────────────────────────────────────────
			# Use a second hash so variation is independent from position jitter
			var vseed: int = abs(hash(Vector2i(cell_x * 7 + 3, cell_z * 13 + 5)))
			var variation: int = vseed % 3   # 0=A, 1=B, 2=C

			# ── Rotation (full 360°) ──────────────────────────────────────────
			var rot_y: float = float(cseed % 628) / 100.0

			# ── Scale ─────────────────────────────────────────────────────────
			var st: float = float(cseed % 1000) / 999.0
			var scale: float
			match variation:
				0: scale = lerpf(SCALE_A[0], SCALE_A[1], st)
				1: scale = lerpf(SCALE_B[0], SCALE_B[1], st)
				_: scale = lerpf(SCALE_C[0], SCALE_C[1], st)

			var basis := Basis.from_euler(Vector3(0, rot_y, 0)).scaled(Vector3(scale, scale, scale))
			var t := Transform3D(basis, pos)

			# ── Per-instance color tint for age variation ─────────────────────
			# Patch-level noise to tint entire local area yellow/green/dark
			var tint_noise: float = _patch_noise(world_x * 0.4, world_z * 0.4)
			var age_tint: Color
			if tint_noise < 0.35:
				age_tint = Color(1.10, 1.05, 0.85)   # Slightly yellow = younger/dry
			elif tint_noise > 0.70:
				age_tint = Color(0.80, 0.90, 0.75)   # Slightly dark = older/shaded
			else:
				age_tint = Color(1.0, 1.0, 1.0)       # No tint = standard

			match variation:
				0:
					trans_a.append(t)
					color_a.append(age_tint)
				1:
					trans_b.append(t)
					color_b.append(age_tint)
				_:
					trans_c.append(t)
					color_c.append(age_tint)

	_build_multimesh(node.grass_multimesh,   _mesh_a, trans_a, color_a)
	_build_multimesh(node.grass_multimesh_b, _mesh_b, trans_b, color_b)
	_build_multimesh(node.grass_multimesh_c, _mesh_c, trans_c, color_c)

static func _build_multimesh(
	mmi: MultiMeshInstance3D,
	mesh: Mesh,
	transforms: Array[Transform3D],
	colors: Array[Color]
) -> void:
	var count := transforms.size()
	if count == 0:
		mmi.multimesh = null
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors       = true   # Enable per-instance color tinting
	mm.instance_count   = count
	mm.mesh             = mesh

	for i in count:
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])

	mmi.multimesh   = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mmi.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))

# ── Smooth patch noise (large sweeping 15-30m blobs) ─────────────────────────
static func _patch_noise(x: float, z: float) -> float:
	var freq: float = 0.022
	var px: float = x * freq
	var pz: float = z * freq
	var ix: int = int(floor(px))
	var iz: int = int(floor(pz))
	var fx: float = px - floor(px)
	var fz: float = pz - floor(pz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a: float = _fhash(ix,   iz  )
	var b: float = _fhash(ix+1, iz  )
	var c: float = _fhash(ix,   iz+1)
	var d: float = _fhash(ix+1, iz+1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

static func _fhash(x: int, z: int) -> float:
	return float(abs(hash(Vector2i(x, z))) % 1000) / 999.0

## Pass entity positions to grass wind shader (if active).
static func update_entities(_positions: Array) -> void:
	pass  # Wind shader removed until color is confirmed working
