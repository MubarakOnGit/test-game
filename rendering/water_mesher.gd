class_name WaterMesher

## Builds raw mesh arrays for dynamic water from ChunkData.
## Runs on background thread. No scene tree access.
static func build(data: ChunkData) -> TerrainMesher.MeshArrays:
	var out := TerrainMesher.MeshArrays.new()
	out.vertices = PackedVector3Array()
	out.normals  = PackedVector3Array()
	out.colors   = PackedColorArray()
	out.indices  = PackedInt32Array()

	var cs      := ChunkData.CHUNK_SIZE
	var spacing := ChunkData.TILE_SIZE

	for lz in range(cs):
		for lx in range(cs):
			var hidx := ChunkData.hi(lx, lz)
			var water: float = data.water_levels[hidx]

			# Only build mesh for tiles with water
			if water <= 0.0:
				continue

			var h: float = data.heights[hidx] + water
			
			var x0 := lx * spacing
			var x1 := x0 + spacing
			var z0 := lz * spacing
			var z1 := z0 + spacing

			# ── TOP FACE ──────────────────────────────────────────────────────
			var color = Color(0.18, 0.60, 0.90, 0.75) # Blue with some alpha
			_push_quad(out,
				Vector3(x0, h, z0),
				Vector3(x0, h, z1),
				Vector3(x1, h, z1),
				Vector3(x1, h, z0),
				Vector3.UP,
				color)

			# ── SIDE FACES ────────────────────────────────────────────────────
			var w_n: float = data.water_levels[ChunkData.hi(lx,     lz - 1)]
			var w_s: float = data.water_levels[ChunkData.hi(lx,     lz + 1)]
			var w_e: float = data.water_levels[ChunkData.hi(lx + 1, lz    )]
			var w_w: float = data.water_levels[ChunkData.hi(lx - 1, lz    )]

			var h_n: float = data.heights[ChunkData.hi(lx,     lz - 1)] + w_n
			var h_s: float = data.heights[ChunkData.hi(lx,     lz + 1)] + w_s
			var h_e: float = data.heights[ChunkData.hi(lx + 1, lz    )] + w_e
			var h_w: float = data.heights[ChunkData.hi(lx - 1, lz    )] + w_w
			
			var terrain_h: float = data.heights[hidx]

			if h > h_n:
				_push_quad(out,
					Vector3(x0, h,         z0),
					Vector3(x1, h,         z0),
					Vector3(x1, maxf(h_n, terrain_h), z0),
					Vector3(x0, maxf(h_n, terrain_h), z0),
					Vector3(0, 0, -1),
					color)

			if h > h_s:
				_push_quad(out,
					Vector3(x1, h,         z1),
					Vector3(x0, h,         z1),
					Vector3(x0, maxf(h_s, terrain_h), z1),
					Vector3(x1, maxf(h_s, terrain_h), z1),
					Vector3(0, 0, 1),
					color)

			if h > h_e:
				_push_quad(out,
					Vector3(x1, h,         z0),
					Vector3(x1, h,         z1),
					Vector3(x1, maxf(h_e, terrain_h), z1),
					Vector3(x1, maxf(h_e, terrain_h), z0),
					Vector3(1, 0, 0),
					color)

			if h > h_w:
				_push_quad(out,
					Vector3(x0, h,         z1),
					Vector3(x0, h,         z0),
					Vector3(x0, maxf(h_w, terrain_h), z0),
					Vector3(x0, maxf(h_w, terrain_h), z1),
					Vector3(-1, 0, 0),
					color)

	return out

static func _push_quad(out: TerrainMesher.MeshArrays, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var i := out.vertices.size()
	out.vertices.push_back(a)
	out.vertices.push_back(b)
	out.vertices.push_back(c)
	out.vertices.push_back(d)
	for _k in range(4):
		out.normals.push_back(normal)
		out.colors.push_back(color)
	# Clockwise winding
	out.indices.push_back(i)
	out.indices.push_back(i + 2)
	out.indices.push_back(i + 1)
	out.indices.push_back(i)
	out.indices.push_back(i + 3)
	out.indices.push_back(i + 2)
