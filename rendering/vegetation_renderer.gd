class_name VegetationRenderer

static var _pine_mesh: Mesh = null
static var _oak_mesh: Mesh = null

static func _ensure_meshes() -> void:
	if _pine_mesh == null:
		_pine_mesh = load("res://assets/pineTreeBaked.res")
	if _oak_mesh == null:
		_oak_mesh = load("res://assets/oakTreeBaked.res")


## Populates the MultiMeshes in the ChunkNode based on VegetationData.
static func commit(node: ChunkNode, data: ChunkData) -> void:
	_ensure_meshes()
	var veg := data.vegetation
	var pine_count := veg.count_of(VegetationData.PINE)
	var oak_count  := veg.count_of(VegetationData.OAK)
	
	_setup_multimesh(node.pine_multimesh, pine_count, _pine_mesh)
	_setup_multimesh(node.oak_multimesh, oak_count, _oak_mesh)
	
	var pine_idx := 0
	var oak_idx  := 0
	
	for i in veg.count():
		var sp := veg.species[i]
		var lx := veg.local_xs[i]
		var lz := veg.local_zs[i]
		
		var hidx := ChunkData.hi(int(lx), int(lz))
		var y := data.heights[hidx]
		
		# Local transform relative to chunk origin. Shifted down 0.1 to avoid Z-fighting with terrain.
		var pos := Vector3(lx * ChunkData.TILE_SIZE, y - 0.1, lz * ChunkData.TILE_SIZE)
		var rot := float(hash(pos)) / 2147483647.0 * TAU
		# Apply rotation, translation, and scale (double size as requested)
		var b := Basis().scaled(Vector3(2.0, 2.0, 2.0)).rotated(Vector3.UP, rot)
		var t := Transform3D(b, pos)
		
		if sp == VegetationData.PINE:
			if node.pine_multimesh.multimesh != null:
				node.pine_multimesh.multimesh.set_instance_transform(pine_idx, t)
			pine_idx += 1
		else:
			if node.oak_multimesh.multimesh != null:
				node.oak_multimesh.multimesh.set_instance_transform(oak_idx, t)
			oak_idx += 1

static func _setup_multimesh(mmi: MultiMeshInstance3D, count: int, mesh: Mesh) -> void:
	if count == 0:
		mmi.multimesh = null
		return
		
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = count
	
	# Use fallback box mesh if GLB mesh couldn't be loaded
	if mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 2.0, 0.5)
		mm.mesh = bm
	else:
		mm.mesh = mesh
		
	# Force a massive AABB to prevent Godot from frustum-culling procedurally generated meshes
	mmi.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	mmi.multimesh = mm
