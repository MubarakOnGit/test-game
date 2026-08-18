class_name FlowerRenderer

static var _meshes: Array[Mesh] = []

static func _ensure_resources() -> void:
	if _meshes.is_empty():
		for c_name in ["red", "white", "blue", "pink"]:
			for height in [1, 2, 3]:
				_meshes.append(_load_mesh("res://assets/flower_%s_%d.glb" % [c_name, height]))

static func _load_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	if packed == null:
		return BoxMesh.new()
	var scene := packed.instantiate()
	var m := GrassRenderer._find_mesh(scene) # Reuse the material setup logic
	scene.queue_free()
	return m if m != null else BoxMesh.new()

## Scatter pixel flowers sparsely across grass tiles
static func commit(node: ChunkNode, data: ChunkData) -> void:
	if node.sim_zone >= 2:
		node.flower_multimesh.multimesh = null
		return

	_ensure_resources()

	var cs: int   = ChunkData.CHUNK_SIZE
	var ts: float = ChunkData.TILE_SIZE

	var positions: Array[Vector3] = []
	var variations: Array[int]    = []

	# Flowers are sparse — maybe 1 per 4x4 tiles area
	const CELL_TILES = 4

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

			var cell_x: int = int(world_x / (ts * CELL_TILES))
			var cell_z: int = int(world_z / (ts * CELL_TILES))
			var cseed: int  = abs(hash(Vector2i(cell_x * 11, cell_z * 23)))

			var chosen_lx: int = cseed % CELL_TILES
			var chosen_lz: int = (cseed / CELL_TILES) % CELL_TILES
			if (lx % CELL_TILES) != chosen_lx or (lz % CELL_TILES) != chosen_lz:
				continue
			
			# Ensure we only place flowers in grassy areas (use the same noise logic)
			var grass_noise = GrassRenderer._patch_noise(world_x, world_z)
			if grass_noise < 0.2:
				# Maybe occasionally allow a flower outside dense grass?
				if (cseed % 100) > 10:
					continue

			if data.slopes[hidx] > 0.6:
				continue

			var jx: float = (float(cseed % 100) / 100.0 - 0.5) * ts * 0.7
			var jz: float = (float((cseed / 100) % 100) / 100.0 - 0.5) * ts * 0.7
			
			positions.append(Vector3(lx * ts + ts * 0.5 + jx, h, lz * ts + ts * 0.5 + jz))
			variations.append(cseed % _meshes.size())

	var count := positions.size()
	if count == 0:
		node.flower_multimesh.multimesh = null
		return

	# Build a single MultiMesh by grouping the sub-meshes into surfaces, OR since MultiMesh 
	# can only hold ONE mesh, we need a MultiMesh per variation if they are different meshes.
	# Actually, to keep it simple, we can randomly pick ONE mesh variation for the whole chunk,
	# OR we can build 4 MultiMeshes (one for each color).
	# Wait, `ChunkNode` only has one `flower_multimesh` slot. Let's just pick one color per chunk 
	# for now, or just use vertex colors to tint a single white flower mesh!
	# Ah, I exported 4 separate GLBs, but we only have 1 MultiMesh slot in ChunkNode.
	# It's better to pick one random mesh per chunk, or add 4 slots. I'll pick one random mesh per chunk based on chunk coordinate to keep the node simple.
	
	var chunk_flower_seed = abs(hash(Vector2i(data.cx, data.cz)))
	var chosen_mesh = _meshes[chunk_flower_seed % _meshes.size()]

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count   = count
	mm.mesh             = chosen_mesh

	for i in count:
		var p: Vector3 = positions[i]
		# Random rotation
		var rot_y: float = float((abs(hash(p))) % 628) / 100.0
		var basis := Basis.from_euler(Vector3(0, rot_y, 0))
		mm.set_instance_transform(i, Transform3D(basis, p))

	node.flower_multimesh.multimesh   = mm
	node.flower_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Real chunk footprint AABB — enables proper frustum culling.
	node.flower_multimesh.custom_aabb = AABB(Vector3(-1, -5, -1), Vector3(50, 35, 50))
