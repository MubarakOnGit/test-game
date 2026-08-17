class_name ChunkRenderer

static var _terrain_material: ShaderMaterial = null
static var _outline_material: StandardMaterial3D = null
static var _water_material: StandardMaterial3D = null

static func _ensure_init() -> void:
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = load("res://rendering/shaders/terrain.gdshader")
	if _outline_material == null:
		_outline_material = StandardMaterial3D.new()
		_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline_material.albedo_color = Color(0, 0, 0, 0.5) # Softer alpha looks much thinner
	if _water_material == null:
		_water_material = StandardMaterial3D.new()
		_water_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_material.roughness = 0.1
		_water_material.vertex_color_use_as_albedo = true

## Applies the built mesh arrays and vegetation to the ChunkNode.
## Must be called on the main thread.
static func commit(node: ChunkNode, data: ChunkData, terrain_arrays, water_arrays) -> void:
	_ensure_init()
	
	if data.metadata.terrain_version > node.rendered_terrain_version:
		if terrain_arrays != null:
			# 1. Build ArrayMesh from mesh_arrays
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = terrain_arrays.vertices
			arr[Mesh.ARRAY_NORMAL] = terrain_arrays.normals
			arr[Mesh.ARRAY_COLOR]  = terrain_arrays.colors
			arr[Mesh.ARRAY_INDEX]  = terrain_arrays.indices
			
			var mesh := ArrayMesh.new()
			if terrain_arrays.vertices.size() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			
			node.mesh_instance.mesh = mesh
			node.mesh_instance.material_override = _terrain_material
			node.mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

			# 1b. Build Outline Mesh
			var outline_mesh := ArrayMesh.new()
			if terrain_arrays.outline_vertices.size() > 0:
				var out_arr := []
				out_arr.resize(Mesh.ARRAY_MAX)
				out_arr[Mesh.ARRAY_VERTEX] = terrain_arrays.outline_vertices
				out_arr[Mesh.ARRAY_INDEX]  = terrain_arrays.outline_indices
				outline_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, out_arr)
			
			node.outline_mesh_instance.mesh = outline_mesh
			node.outline_mesh_instance.material_override = _outline_material
			node.outline_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			
			# 3. Collision — ConcavePolygonShape3D built from the ACTUAL mesh vertices.
			# 
			# WHY NOT HeightMapShape3D:
			# Godot's HeightMapShape3D bilinearly interpolates between height samples,
			# producing a smooth ramp at tile edges. Our visual mesh uses FLAT quads
			# (each tile is one height). At river banks and cliff edges the collision
			# surface ends up below or above the visual surface, causing sinking/floating.
			#
			# ConcavePolygonShape3D uses the exact triangles from the mesh, so collision
			# is guaranteed to match what the player sees — no interpolation gap.
			
			var trimesh_points := PackedVector3Array()
			var verts: PackedVector3Array = terrain_arrays.vertices
			var idxs: PackedInt32Array    = terrain_arrays.indices
			trimesh_points.resize(idxs.size())
			for ti in idxs.size():
				trimesh_points[ti] = verts[idxs[ti]]
			
			var trimesh := ConcavePolygonShape3D.new()
			trimesh.set_faces(trimesh_points)
			
			# Clear only terrain collision (not trunk colliders)
			for child in node.static_body.get_children():
				if not child.has_meta("trunk_collider"):
					child.queue_free()
			
			var collision_shape := CollisionShape3D.new()
			collision_shape.shape = trimesh
			node.static_body.add_child(collision_shape)
			
		node.rendered_terrain_version = data.metadata.terrain_version
	
	if data.metadata.water_version > node.rendered_water_version:
		if water_arrays != null:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = water_arrays.vertices
			arr[Mesh.ARRAY_NORMAL] = water_arrays.normals
			arr[Mesh.ARRAY_COLOR]  = water_arrays.colors
			arr[Mesh.ARRAY_INDEX]  = water_arrays.indices
			
			var mesh := ArrayMesh.new()
			if water_arrays.vertices.size() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				
			node.water_mesh_instance.mesh = mesh
			node.water_mesh_instance.material_override = _water_material
			# Water doesn't cast shadows for now to save perf and look better
			node.water_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			
		node.rendered_water_version = data.metadata.water_version
	
	# 4. Vegetation, Animals, Grass, Flowers
	if data.metadata.vegetation_version > node.rendered_vegetation_version:
		VegetationRenderer.commit(node, data)
		AnimalRenderer.commit(node, data)
		GrassRenderer.commit(node, data)
		FlowerRenderer.commit(node, data)
		node.rendered_vegetation_version = data.metadata.vegetation_version
