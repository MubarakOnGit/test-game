class_name VegetationRenderer

# ─── Cached Meshes (loaded once per session) ──────────────────────────────────
static var _pine_mesh:     Mesh = null  # Pine Tree.glb
static var _birch_mesh:    Mesh = null  # Birch Tree.glb
static var _simple_mesh:   Mesh = null  # Simple Tree.glb
static var _stylized_mesh: Mesh = null  # Stylized Tree.glb
static var _bush_a_mesh:   Mesh = null  # Bush A
static var _rose_bush_mesh:Mesh = null  # Rose Bush
static var _rock_a_mesh:   Mesh = null  # Rock A
static var _rock_b_mesh:   Mesh = null  # Rock B
static var _rock_c_mesh:   Mesh = null  # Rock C

# ─── Per-species scale ranges for natural size variation ──────────────────────
# [min_scale, max_scale] — randomized per instance using position hash
const _PINE_SCALE     := [4.2, 6.6]   # Tall narrow conifers, medium variance
const _BIRCH_SCALE    := [3.6, 5.7]   # Slender birches, moderate height
const _SIMPLE_SCALE   := [3.2, 5.6]   # Broad canopy, most size diversity
const _STYLIZED_SCALE := [2.6, 4.0]   # Mixed mid-elevation trees
const _BUSH_A_SCALE   := [0.05, 0.15]   # Small bushes
const _ROSE_BUSH_SCALE:= [0.05, 0.12]   # Rose bushes
const _ROCK_A_SCALE   := [0.8, 2.5]   # Single rock
const _ROCK_B_SCALE   := [1.0, 3.0]   # Rock cluster 1
const _ROCK_C_SCALE   := [0.6, 1.8]   # Rock cluster 2

static func _ensure_meshes() -> void:
	if _pine_mesh == null:
		_pine_mesh = _extract_mesh("res://assets/trees/pine-base_basic_shaded.glb")
	if _birch_mesh == null:
		_birch_mesh = _extract_mesh("res://assets/trees/oak-base_basic_shaded.glb")
	if _simple_mesh == null:
		_simple_mesh = _extract_mesh("res://assets/trees/Simple Tree.glb")
	if _stylized_mesh == null:
		_stylized_mesh = _extract_mesh("res://assets/trees/Stylized Tree.glb")
	if _bush_a_mesh == null:
		_bush_a_mesh = _extract_mesh("res://assets/elements/Bush by Jarlan Perez - d6STyhH76Qe.glb")
	if _rose_bush_mesh == null:
		_rose_bush_mesh = _extract_mesh("res://assets/elements/Rose bush by Poly by Google - aI3Wtnkueq7.glb")
	if _rock_a_mesh == null:
		_rock_a_mesh = _extract_mesh("res://assets/elements/Rock by Quaternius - RtLRqYjfMs.glb")
	if _rock_b_mesh == null:
		_rock_b_mesh = _extract_mesh("res://assets/elements/Rocks by Don Carson - kCmxD1l2Qu.glb")
	if _rock_c_mesh == null:
		_rock_c_mesh = _extract_mesh("res://assets/elements/Rocks by Quaternius - OQvi8PIZ40.glb")

## Load a GLB scene and extract the first MeshInstance3D's mesh.
## Falls back to a simple box mesh if the GLB cannot be loaded or has no mesh.
static func _extract_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	if packed == null:
		return _fallback_mesh()
	var scene: Node = packed.instantiate()
	var mesh: Mesh = _find_first_mesh(scene)
	if mesh != null:
		for i in mesh.get_surface_count():
			var mat = mesh.surface_get_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
				mesh.surface_set_material(i, mat)
			if mat is StandardMaterial3D:
				mat.vertex_color_use_as_albedo = true
				mat.metallic = 0.0
				mat.roughness = 1.0

	scene.queue_free()
	return mesh if mesh != null else _fallback_mesh()

static func _find_first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m := _find_first_mesh(child)
		if m != null:
			return m
	return null

static func _fallback_mesh() -> Mesh:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 2.0, 0.5)
	return bm


## Populates the MultiMeshes in the ChunkNode based on VegetationData.
static func commit(node: ChunkNode, data: ChunkData) -> void:
	_ensure_meshes()
	var veg := data.vegetation

	# Count instances per species
	var pine_count     := veg.count_of(VegetationData.PINE)
	var birch_count    := veg.count_of(VegetationData.BIRCH)
	var simple_count   := veg.count_of(VegetationData.SIMPLE)
	var stylized_count := veg.count_of(VegetationData.STYLIZED)
	var bush_a_count   := veg.count_of(VegetationData.BUSH_A)
	var rose_bush_count:= veg.count_of(VegetationData.ROSE_BUSH)
	var rock_a_count   := veg.count_of(VegetationData.ROCK_A)
	var rock_b_count   := veg.count_of(VegetationData.ROCK_B)
	var rock_c_count   := veg.count_of(VegetationData.ROCK_C)

	_setup_multimesh(node.pine_multimesh,     pine_count,     _pine_mesh)
	_setup_multimesh(node.birch_multimesh,    birch_count,    _birch_mesh)
	_setup_multimesh(node.simple_multimesh,   simple_count,   _simple_mesh)
	_setup_multimesh(node.stylized_multimesh, stylized_count, _stylized_mesh)
	_setup_multimesh(node.bush_a_multimesh,   bush_a_count,   _bush_a_mesh)
	_setup_multimesh(node.rose_bush_multimesh,rose_bush_count,_rose_bush_mesh)
	_setup_multimesh(node.rock_a_multimesh,   rock_a_count,   _rock_a_mesh)
	_setup_multimesh(node.rock_b_multimesh,   rock_b_count,   _rock_b_mesh)
	_setup_multimesh(node.rock_c_multimesh,   rock_c_count,   _rock_c_mesh)

	var pine_idx     := 0
	var birch_idx    := 0
	var simple_idx   := 0
	var stylized_idx := 0
	var bush_a_idx   := 0
	var rose_bush_idx:= 0
	var rock_a_idx   := 0
	var rock_b_idx   := 0
	var rock_c_idx   := 0

	for i in veg.count():
		var sp := veg.species[i]
		var lx := veg.local_xs[i]
		var lz := veg.local_zs[i]

		var hidx := ChunkData.hi(int(lx), int(lz))
		var y := data.heights[hidx]

		var mesh := _get_mesh_for_species(sp)
		var aabb := mesh.get_aabb()
		var bottom_y := aabb.position.y

		# Initial world position for hash calculations
		var pos := Vector3(lx * ChunkData.TILE_SIZE, y - 0.1, lz * ChunkData.TILE_SIZE)

		# Scale varies per instance within species-appropriate range
		var scale := _instance_scale(sp, pos)
		var y_scale := scale * _height_ratio(sp)
		
		# Shift so the bottom of the mesh AABB is at ground level (-0.1 to sink roots slightly)
		var y_offset := -bottom_y * y_scale
		pos.y += y_offset

		# Deterministic rotation from position hash (full TAU rotation variety)
		var rot_hash := float(hash(pos)) / 2147483647.0
		var rot      := rot_hash * TAU

		# Build transform: Y-axis rotation + non-uniform scale for natural tilt variety
		var tilt_x := (fmod(abs(rot_hash * 17.3), 1.0) - 0.5) * 0.08  # ±2.3° X tilt
		var tilt_z := (fmod(abs(rot_hash * 31.7), 1.0) - 0.5) * 0.08  # ±2.3° Z tilt
		var b := Basis().rotated(Vector3.RIGHT, tilt_x).rotated(Vector3.FORWARD, tilt_z)
		b = b.rotated(Vector3.UP, rot)
		b = b.scaled(Vector3(scale, scale * _height_ratio(sp), scale))
		var t := Transform3D(b, pos)

		match sp:
			VegetationData.PINE:
				if node.pine_multimesh.multimesh != null:
					node.pine_multimesh.multimesh.set_instance_transform(pine_idx, t)
				pine_idx += 1
			VegetationData.BIRCH:
				if node.birch_multimesh.multimesh != null:
					node.birch_multimesh.multimesh.set_instance_transform(birch_idx, t)
				birch_idx += 1
			VegetationData.SIMPLE:
				if node.simple_multimesh.multimesh != null:
					node.simple_multimesh.multimesh.set_instance_transform(simple_idx, t)
				simple_idx += 1
			VegetationData.STYLIZED:
				if node.stylized_multimesh.multimesh != null:
					node.stylized_multimesh.multimesh.set_instance_transform(stylized_idx, t)
				stylized_idx += 1
			VegetationData.BUSH_A:
				if node.bush_a_multimesh.multimesh != null:
					node.bush_a_multimesh.multimesh.set_instance_transform(bush_a_idx, t)
				bush_a_idx += 1
			VegetationData.ROSE_BUSH:
				if node.rose_bush_multimesh.multimesh != null:
					node.rose_bush_multimesh.multimesh.set_instance_transform(rose_bush_idx, t)
				rose_bush_idx += 1
			VegetationData.ROCK_A:
				if node.rock_a_multimesh.multimesh != null:
					node.rock_a_multimesh.multimesh.set_instance_transform(rock_a_idx, t)
				rock_a_idx += 1
			VegetationData.ROCK_B:
				if node.rock_b_multimesh.multimesh != null:
					node.rock_b_multimesh.multimesh.set_instance_transform(rock_b_idx, t)
				rock_b_idx += 1
			VegetationData.ROCK_C:
				if node.rock_c_multimesh.multimesh != null:
					node.rock_c_multimesh.multimesh.set_instance_transform(rock_c_idx, t)
				rock_c_idx += 1

# ─── Per-species scale helpers ────────────────────────────────────────────────

## Returns a scale value randomized within the species' natural size range.
static func _instance_scale(sp: int, pos: Vector3) -> float:
	var seed_val: int = abs(hash(pos + Vector3(sp * 100.0, 0.0, 0.0)))
	var t := float(seed_val % 1000) / 999.0  # 0.0 – 1.0
	match sp:
		VegetationData.PINE:
			return lerpf(_PINE_SCALE[0],     _PINE_SCALE[1],     t)
		VegetationData.BIRCH:
			return lerpf(_BIRCH_SCALE[0],    _BIRCH_SCALE[1],    t)
		VegetationData.SIMPLE:
			return lerpf(_SIMPLE_SCALE[0],   _SIMPLE_SCALE[1],   t)
		VegetationData.STYLIZED:
			return lerpf(_STYLIZED_SCALE[0], _STYLIZED_SCALE[1], t)
		VegetationData.BUSH_A:
			return lerpf(_BUSH_A_SCALE[0],   _BUSH_A_SCALE[1],   t)
		VegetationData.ROSE_BUSH:
			return lerpf(_ROSE_BUSH_SCALE[0],_ROSE_BUSH_SCALE[1],t)
		VegetationData.ROCK_A:
			return lerpf(_ROCK_A_SCALE[0],   _ROCK_A_SCALE[1],   t)
		VegetationData.ROCK_B:
			return lerpf(_ROCK_B_SCALE[0],   _ROCK_B_SCALE[1],   t)
		VegetationData.ROCK_C:
			return lerpf(_ROCK_C_SCALE[0],   _ROCK_C_SCALE[1],   t)
	return 1.8  # fallback

## Height-to-width ratio — pines are tall and narrow, simple trees are wide.
static func _height_ratio(sp: int) -> float:
	match sp:
		VegetationData.PINE:     return 1.35   # Tall narrow conifer silhouette
		VegetationData.BIRCH:    return 1.20   # Moderately tall and slender
		VegetationData.SIMPLE:   return 0.90   # Broad wide canopy
		VegetationData.STYLIZED: return 1.10   # Balanced mixed-forest shape
		VegetationData.BUSH_A:   return 1.00
		VegetationData.ROSE_BUSH:return 1.00
		VegetationData.ROCK_A:   return randf_range(0.8, 1.2)  # Some vertical squash/stretch for rocks
		VegetationData.ROCK_B:   return randf_range(0.8, 1.2)
		VegetationData.ROCK_C:   return randf_range(0.8, 1.2)
	return 1.0

# ─── Mesh Access ─────────────────────────────────────────────────────────────

static func _get_mesh_for_species(sp: int) -> Mesh:
	match sp:
		VegetationData.PINE: return _pine_mesh
		VegetationData.BIRCH: return _birch_mesh
		VegetationData.SIMPLE: return _simple_mesh
		VegetationData.STYLIZED: return _stylized_mesh
		VegetationData.BUSH_A: return _bush_a_mesh
		VegetationData.ROSE_BUSH: return _rose_bush_mesh
		VegetationData.ROCK_A: return _rock_a_mesh
		VegetationData.ROCK_B: return _rock_b_mesh
		VegetationData.ROCK_C: return _rock_c_mesh
	return _pine_mesh

# ─── MultiMesh Setup ─────────────────────────────────────────────────────────

static func _setup_multimesh(mmi: MultiMeshInstance3D, count: int, mesh: Mesh) -> void:
	if count == 0:
		mmi.multimesh = null
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count   = count
	mm.mesh             = mesh  # Already guaranteed non-null from _extract_mesh

	# Force a massive AABB to prevent Godot from frustum-culling procedurally generated meshes
	mmi.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	mmi.multimesh   = mm
