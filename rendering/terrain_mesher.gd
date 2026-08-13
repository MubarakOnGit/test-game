class_name TerrainMesher

class MeshArrays:
	var vertices: PackedVector3Array
	var normals:  PackedVector3Array
	var colors:   PackedColorArray
	var indices:  PackedInt32Array
	
	var outline_vertices: PackedVector3Array
	var outline_indices:  PackedInt32Array

## Builds raw mesh arrays from ChunkData.
## Runs on background thread. No scene tree access.
static func build(data: ChunkData) -> MeshArrays:
	var out := MeshArrays.new()
	out.vertices = PackedVector3Array()
	out.normals  = PackedVector3Array()
	out.colors   = PackedColorArray()
	out.indices  = PackedInt32Array()
	out.outline_vertices = PackedVector3Array()
	out.outline_indices  = PackedInt32Array()

	var cs      := ChunkData.CHUNK_SIZE  # 16
	var spacing := ChunkData.TILE_SIZE   # 1.0
	var bottom  := ChunkData.BOTTOM_Y    # -2.0

	var edges := {} # Dictionary for Feature Edge Extraction

	# ── Flat inline loop — no sub-functions, no PackedByteArray-by-value bugs ──
	for lz in range(cs):
		for lx in range(cs):
			var bidx := ChunkData.bi(lx, lz)
			var hidx := ChunkData.hi(lx, lz)

			var h     : float = data.heights[hidx]
			var biome : int   = data.biomes[bidx]

			var cr := float(biome) / 4.0
			var cg := h

			var x0 := lx * spacing
			var x1 := x0 + spacing
			var z0 := lz * spacing
			var z1 := z0 + spacing

			# ── TOP FACE ──────────────────────────────────────────────────────
			# Only draw if tile above sea level OR draw all (we always draw)
			# CCW from above (+Y normal): (x0,z0)→(x0,z1)→(x1,z1)→(x1,z0)
			_push_quad(out, null,
				Vector3(x0, h, z0),  # A
				Vector3(x0, h, z1),  # B
				Vector3(x1, h, z1),  # C
				Vector3(x1, h, z0),  # D
				Vector3.UP,
				Color(cr, cg, 1.0, 0.0))

			# ── SIDE FACES ────────────────────────────────────────────────────
			# North (-Z): draw if neighbor to the north is lower
			var h_n : float = data.heights[ChunkData.hi(lx,     lz - 1)]
			var h_s : float = data.heights[ChunkData.hi(lx,     lz + 1)]
			var h_e : float = data.heights[ChunkData.hi(lx + 1, lz    )]
			var h_w : float = data.heights[ChunkData.hi(lx - 1, lz    )]

			if h > h_n:
				# North face: normal -Z. CCW from north: (x0,z0)→(x1,z0)→(x1,bot)→(x0,bot)
				var drop := clampf((h - h_n) / 5.0, 0.0, 1.0)
				_push_quad(out, edges,
					Vector3(x0, h,      z0),
					Vector3(x1, h,      z0),
					Vector3(x1, bottom, z0),
					Vector3(x0, bottom, z0),
					Vector3(0, 0, -1),
					Color(cr, cg, 0.0, drop))

			if h > h_s:
				# South face: normal +Z. CCW from south: (x1,z1)→(x0,z1)→(x0,bot)→(x1,bot)
				var drop := clampf((h - h_s) / 5.0, 0.0, 1.0)
				_push_quad(out, edges,
					Vector3(x1, h,      z1),
					Vector3(x0, h,      z1),
					Vector3(x0, bottom, z1),
					Vector3(x1, bottom, z1),
					Vector3(0, 0, 1),
					Color(cr, cg, 0.0, drop))

			if h > h_e:
				# East face: normal +X. CCW from east: (x1,z0)→(x1,z1)→(x1,bot,z1)→(x1,bot,z0)
				var drop := clampf((h - h_e) / 5.0, 0.0, 1.0)
				_push_quad(out, edges,
					Vector3(x1, h,      z0),
					Vector3(x1, h,      z1),
					Vector3(x1, bottom, z1),
					Vector3(x1, bottom, z0),
					Vector3(1, 0, 0),
					Color(cr, cg, 0.0, drop))

			if h > h_w:
				# West face: normal -X. CCW from west: (x0,z1)→(x0,z0)→(x0,bot,z0)→(x0,bot,z1)
				var drop := clampf((h - h_w) / 5.0, 0.0, 1.0)
				_push_quad(out, edges,
					Vector3(x0, h,      z1),
					Vector3(x0, h,      z0),
					Vector3(x0, bottom, z0),
					Vector3(x0, bottom, z1),
					Vector3(-1, 0, 0),
					Color(cr, cg, 0.0, drop))

	# ── Feature Edge Extraction ───────────────────────────────────────────────
	for key in edges:
		var info = edges[key]
		var count = info[2]
		var all_same_normal = info[1]
		
		# Draw the edge if it's used by only 1 face (silhouette)
		# OR if it's used by multiple faces that have different normals (sharp corner)
		if count == 1 or not all_same_normal:
			var a : Vector3 = key[0]
			var b : Vector3 = key[1]
			
			var sum_n : Vector3 = info[3]
			var push_dir := sum_n.normalized()
			if push_dir.length_squared() < 0.01:
				push_dir = Vector3.UP # Fallback for perfectly opposite faces (rare in voxels)
			
			# Push slightly outwards to prevent Z-fighting
			var eps := push_dir * 0.005
			
			var li := out.outline_vertices.size()
			out.outline_vertices.push_back(a + eps)
			out.outline_vertices.push_back(b + eps)
			out.outline_indices.push_back(li)
			out.outline_indices.push_back(li + 1)

	return out

## Pushes a quad (A→B→C→D, CCW from outside) into the mesh arrays.
## Normal and color are uniform across all 4 vertices.
static func _push_quad(out: MeshArrays, edges, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	var i := out.vertices.size()
	out.vertices.push_back(a)
	out.vertices.push_back(b)
	out.vertices.push_back(c)
	out.vertices.push_back(d)
	for _k in range(4):
		out.normals.push_back(normal)
		out.colors.push_back(color)
	# Two triangles: A-C-B and A-D-C (Clockwise for Godot)
	out.indices.push_back(i)
	out.indices.push_back(i + 2)
	out.indices.push_back(i + 1)
	out.indices.push_back(i)
	out.indices.push_back(i + 3)
	out.indices.push_back(i + 2)

	if edges != null:
		_add_edge(edges, a, b, normal)
		_add_edge(edges, b, c, normal)
		_add_edge(edges, c, d, normal)
		_add_edge(edges, d, a, normal)

static func _get_edge_key(a: Vector3, b: Vector3) -> Array:
	# Deterministic sorting so (A,B) and (B,A) map to the same key
	if a.x < b.x: return [a, b]
	if a.x > b.x: return [b, a]
	if a.y < b.y: return [a, b]
	if a.y > b.y: return [b, a]
	if a.z < b.z: return [a, b]
	return [b, a]

static func _add_edge(edges: Dictionary, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var key = _get_edge_key(a, b)
	if edges.has(key):
		var info = edges[key]
		info[3] += normal # sum_normal
		if info[0].distance_squared_to(normal) > 0.01:
			info[1] = false # all_same_normal = false
		info[2] += 1 # count
	else:
		# info = [first_normal, all_same_normal, count, sum_normal]
		edges[key] = [normal, true, 1, normal]
