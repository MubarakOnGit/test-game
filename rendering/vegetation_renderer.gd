class_name VegetationRenderer

static var _pine_mesh: Mesh = null
static var _oak_mesh: Mesh = null

static func _ensure_meshes() -> void:
	if _pine_mesh == null:
		var pine_scene = load("res://assets/pineTree.glb")
		if pine_scene:
			var instance = pine_scene.instantiate()
			for child in instance.get_children():
				if child is MeshInstance3D:
					_pine_mesh = child.mesh
					break
			instance.free()
	if _oak_mesh == null:
		var oak_scene = load("res://assets/oakTree.glb")
		if oak_scene:
			var instance = oak_scene.instantiate()
			for child in instance.get_children():
				if child is MeshInstance3D:
					_oak_mesh = child.mesh
					break
			instance.free()

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
		
		# Local transform relative to chunk origin
		var pos := Vector3(lx * ChunkData.TILE_SIZE, y, lz * ChunkData.TILE_SIZE)
		# Add a bit of random rotation based on position
		var rot := float(hash(pos)) / 2147483647.0 * TAU
		var t := Transform3D().rotated(Vector3.UP, rot).translated(pos).scaled(Vector3(3.0, 3.0, 3.0))
		
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
		
	mmi.multimesh = mm
