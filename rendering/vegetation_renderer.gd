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
static var _berry_full_mesh:  Mesh = null  # Berry bush WITH berries (built procedurally)
static var _berry_empty_mesh: Mesh = null  # Berry bush WITHOUT berries (just leaves)

# ─── Per-species scale ranges for natural size variation ──────────────────────
# [min_scale, max_scale] — randomized per instance using position hash
const _PINE_SCALE     := [4.2, 6.6]   # Tall narrow conifers, medium variance
const _APPLE_TREE_SCALE    := [3.6, 5.7]   # Apple trees, moderate height
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
	if _berry_full_mesh == null or _berry_empty_mesh == null:
		_build_berry_meshes()

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

## Build berry bush meshes procedurally from BoxMesh primitives.
## Shared mesh = shared draw call. No GLB assets needed.
static func _build_berry_meshes() -> void:
	# ── MagicaVoxel High-Res Sphere Design ────────────────────────────────────
	# A 9x9x9 grid, culled into a perfect radius-4 sphere.
	var voxel_size := 0.225
	var half_size := Vector3(voxel_size * 0.5, voxel_size * 0.5, voxel_size * 0.5)
	var radius := 4
	var radius_sq := radius * radius
	
	var leaf_colors := [
		Color("#365c27"), # Light dark green
		Color("#2b4a1f"), # Mid dark green
		Color("#203816"), # Deep dark green
	]
	var berry_colors := [
		Color("#d93838"), # Red
		Color("#4c3a99"), # Purple/Blue
	]

	var e_verts := PackedVector3Array()
	var e_norms := PackedVector3Array()
	var e_colors:= PackedColorArray()
	var e_idxs  := PackedInt32Array()

	var f_verts := PackedVector3Array()
	var f_norms := PackedVector3Array()
	var f_colors:= PackedColorArray()
	var f_idxs  := PackedInt32Array()

	# Shift up so the bottom of the sphere rests on the ground
	var y_shift := float(radius) * voxel_size

	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var d_sq := x*x + y*y + z*z
				# Cull outside the sphere
				if d_sq > radius_sq:
					continue
					
				var is_surface: bool = (d_sq >= (radius - 1) * (radius - 1))
				var h: int = hash(str(x, "_", y, "_", z))
				var h_abs: int = abs(h)
				
				# Texture the surface by randomly carving out 15% of the outer voxels
				if is_surface:
					if h_abs % 100 < 15:
						continue
						
				var offset := Vector3(float(x) * voxel_size, float(y) * voxel_size + y_shift, float(z) * voxel_size)
				
				# Pick a green color
				var leaf_col: Color = leaf_colors[h_abs % leaf_colors.size()]
				
				# Always add green to the empty bush
				_add_box_to_arrays(e_verts, e_norms, e_colors, e_idxs, offset, half_size, leaf_col)
				
				# Add to the full bush
				var is_berry := false
				var berry_col: Color
				if is_surface:
					# 7% chance to be a berry if it's on the surface
					var r: int = (h_abs / 100) % 100
					if r < 7:
						is_berry = true
						if r < 4:
							berry_col = berry_colors[0] # Red
						else:
							berry_col = berry_colors[1] # Purple/Blue
							
				if is_berry:
					_add_box_to_arrays(f_verts, f_norms, f_colors, f_idxs, offset, half_size, berry_col)
				else:
					_add_box_to_arrays(f_verts, f_norms, f_colors, f_idxs, offset, half_size, leaf_col)

	# Finalize Empty Mesh
	var e_arrays := []
	e_arrays.resize(Mesh.ARRAY_MAX)
	e_arrays[Mesh.ARRAY_VERTEX] = e_verts
	e_arrays[Mesh.ARRAY_NORMAL] = e_norms
	e_arrays[Mesh.ARRAY_COLOR]  = e_colors
	e_arrays[Mesh.ARRAY_INDEX]  = e_idxs
	var empty_mesh := ArrayMesh.new()
	empty_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e_arrays)
	var empty_mat := StandardMaterial3D.new()
	empty_mat.vertex_color_use_as_albedo = true
	empty_mat.roughness = 1.0
	empty_mat.metallic  = 0.0
	empty_mesh.surface_set_material(0, empty_mat)
	_berry_empty_mesh = empty_mesh

	# Finalize Full Mesh
	var f_arrays := []
	f_arrays.resize(Mesh.ARRAY_MAX)
	f_arrays[Mesh.ARRAY_VERTEX] = f_verts
	f_arrays[Mesh.ARRAY_NORMAL] = f_norms
	f_arrays[Mesh.ARRAY_COLOR]  = f_colors
	f_arrays[Mesh.ARRAY_INDEX]  = f_idxs
	var full_mesh := ArrayMesh.new()
	full_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, f_arrays)
	var full_mat := StandardMaterial3D.new()
	full_mat.vertex_color_use_as_albedo = true
	full_mat.roughness = 1.0
	full_mat.metallic  = 0.0
	full_mesh.surface_set_material(0, full_mat)
	_berry_full_mesh = full_mesh

## Helper: appends a box's verts/norms/colors/indices into the given arrays.
static func _add_box_to_arrays(
		verts: PackedVector3Array, norms: PackedVector3Array,
		colors: PackedColorArray, idxs: PackedInt32Array,
		offset: Vector3, half_size: Vector3, color: Color) -> void:
	var corners: Array[Vector3] = [
		offset + Vector3(-half_size.x, -half_size.y, -half_size.z),
		offset + Vector3( half_size.x, -half_size.y, -half_size.z),
		offset + Vector3( half_size.x,  half_size.y, -half_size.z),
		offset + Vector3(-half_size.x,  half_size.y, -half_size.z),
		offset + Vector3(-half_size.x, -half_size.y,  half_size.z),
		offset + Vector3( half_size.x, -half_size.y,  half_size.z),
		offset + Vector3( half_size.x,  half_size.y,  half_size.z),
		offset + Vector3(-half_size.x,  half_size.y,  half_size.z),
	]
	var faces: Array[Array] = [
		[0,1,2,3], [5,4,7,6], [0,3,7,4],
		[1,5,6,2], [3,2,6,7], [0,4,5,1]
	]
	var face_norms: Array[Vector3] = [
		Vector3(0,0,-1), Vector3(0,0,1), Vector3(-1,0,0),
		Vector3(1,0,0),  Vector3(0,1,0), Vector3(0,-1,0)
	]
	for fi in 6:
		var face: Array  = faces[fi]
		var n: Vector3   = face_norms[fi]
		var base := verts.size()
		for vi in 4:
			verts.append(corners[face[vi]])
			norms.append(n)
			colors.append(color)
		idxs.append_array([base, base+1, base+2, base, base+2, base+3])


## Populates the MultiMeshes in the ChunkNode based on VegetationData.
static func commit(node: ChunkNode, data: ChunkData) -> void:
	_ensure_meshes()
	var veg := data.vegetation

	# Count instances per species
	var pine_count     := veg.count_of(VegetationData.PINE)
	var apple_tree_count    := veg.count_of(VegetationData.APPLE_TREE)
	var simple_count   := veg.count_of(VegetationData.SIMPLE)
	var stylized_count := veg.count_of(VegetationData.STYLIZED)
	var bush_a_count   := veg.count_of(VegetationData.BUSH_A)
	var rose_bush_count:= veg.count_of(VegetationData.ROSE_BUSH)
	var rock_a_count   := veg.count_of(VegetationData.ROCK_A)
	var rock_b_count   := veg.count_of(VegetationData.ROCK_B)
	var rock_c_count   := veg.count_of(VegetationData.ROCK_C)

	_setup_multimesh(node.pine_multimesh,     pine_count,     _pine_mesh)
	_setup_multimesh(node.birch_multimesh,    apple_tree_count,    _birch_mesh)
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

	# Clear previous tree/rock trunk colliders (tagged so we don't wipe terrain collision)
	for child in node.static_body.get_children():
		if child.has_meta("trunk_collider"):
			child.queue_free()

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
					_add_trunk_collider(node, pos, scale * 0.50, scale * 3.5)
				pine_idx += 1
			VegetationData.APPLE_TREE:
				if node.birch_multimesh.multimesh != null:
					node.birch_multimesh.multimesh.set_instance_transform(birch_idx, t)
					node.apple_tree_positions.append(pos)
					_add_trunk_collider(node, pos, scale * 0.45, scale * 3.0)
				birch_idx += 1
			VegetationData.SIMPLE:
				if node.simple_multimesh.multimesh != null:
					node.simple_multimesh.multimesh.set_instance_transform(simple_idx, t)
					_add_trunk_collider(node, pos, scale * 0.55, scale * 2.8)
				simple_idx += 1
			VegetationData.STYLIZED:
				if node.stylized_multimesh.multimesh != null:
					node.stylized_multimesh.multimesh.set_instance_transform(stylized_idx, t)
					_add_trunk_collider(node, pos, scale * 0.45, scale * 2.5)
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

	# Start apple dropping now that all positions are known
	node.begin_apple_drops()

	# ── Berry Bush Commit ────────────────────────────────────────────────────
	var bcount := veg.berry_bush_count()
	for i in bcount:
		var lx := veg.berry_local_xs[i]
		var lz := veg.berry_local_zs[i]
		var hidx := ChunkData.hi(int(lx), int(lz))
		var y    := data.heights[hidx]
		var local_pos := Vector3(lx * ChunkData.TILE_SIZE, y, lz * ChunkData.TILE_SIZE)
		node.berry_positions.append(local_pos)
		node.berry_has_berry.append(1)        # start with berries
		node.berry_respawn_times.append(0.0)
		node.berry_colors.append(abs(hash(local_pos)) % 2)  # 0=red, 1=violet
	if bcount > 0:
		node._rebuild_berry_meshes()

## Adds a cylinder collision shape to the chunk's static_body at a tree trunk position.
## Tagged with "trunk_collider" meta so it can be cleared on chunk reset.
## NOTE: pos is LOCAL to the chunk node (not world space), so we use it directly.
static func _add_trunk_collider(node: ChunkNode, pos: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	cs.shape = cyl
	# pos is local to the chunk, static_body sits at chunk origin, so use pos directly
	cs.position = Vector3(pos.x, pos.y + height * 0.5, pos.z)
	cs.set_meta("trunk_collider", true)
	node.static_body.add_child(cs)

# ─── Per-species scale helpers ────────────────────────────────────────────────

## Returns a scale value randomized within the species' natural size range.
static func _instance_scale(sp: int, pos: Vector3) -> float:
	var seed_val: int = abs(hash(pos + Vector3(sp * 100.0, 0.0, 0.0)))
	var t := float(seed_val % 1000) / 999.0  # 0.0 – 1.0
	match sp:
		VegetationData.PINE:
			return lerpf(_PINE_SCALE[0],     _PINE_SCALE[1],     t)
		VegetationData.APPLE_TREE:
			return lerpf(_APPLE_TREE_SCALE[0],    _APPLE_TREE_SCALE[1],    t)
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
		VegetationData.APPLE_TREE:    return 1.20   # Moderately tall and slender
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
		VegetationData.APPLE_TREE: return _birch_mesh
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
