class_name ChunkNode
extends Node3D

# ─── Scene Presence (exactly 6 nodes) ─────────────────────────────────────────
# All other nodes (1200+/chunk) are gone. The GPU does the work.
var mesh_instance:         MeshInstance3D       # merged terrain mesh (1 draw call)
var outline_mesh_instance: MeshInstance3D       # merged block outlines (1 draw call)
var water_mesh_instance:   MeshInstance3D       # merged water mesh (1 draw call)
var pine_multimesh:        MultiMeshInstance3D  # Pine Tree.glb    (1 draw call)
var birch_multimesh:       MultiMeshInstance3D  # Birch Tree.glb   (1 draw call)
var simple_multimesh:      MultiMeshInstance3D  # Simple Tree.glb  (1 draw call)
var stylized_multimesh:    MultiMeshInstance3D  # Stylized Tree.glb(1 draw call)
var bush_a_multimesh:      MultiMeshInstance3D  # Bush A
var rose_bush_multimesh:   MultiMeshInstance3D  # Rose Bush
var rock_a_multimesh:      MultiMeshInstance3D  # Rock A
var rock_b_multimesh:      MultiMeshInstance3D  # Rock B
var rock_c_multimesh:      MultiMeshInstance3D  # Rock C
var animals_container:     Node3D               # Container for dynamic animals
var static_body:           StaticBody3D         # merged terrain collision

# ─── Pool State ───────────────────────────────────────────────────────────────
var chunk_key: Vector2i = Vector2i.ZERO
var rendered_terrain_version: int = -1
var rendered_vegetation_version: int = -1
var rendered_water_version: int = -1

func _init() -> void:
	name = "ChunkNode"
	mesh_instance        = MeshInstance3D.new()
	outline_mesh_instance = MeshInstance3D.new()
	water_mesh_instance  = MeshInstance3D.new()
	pine_multimesh       = MultiMeshInstance3D.new()
	birch_multimesh      = MultiMeshInstance3D.new()
	simple_multimesh     = MultiMeshInstance3D.new()
	stylized_multimesh   = MultiMeshInstance3D.new()
	bush_a_multimesh     = MultiMeshInstance3D.new()
	rose_bush_multimesh  = MultiMeshInstance3D.new()
	rock_a_multimesh     = MultiMeshInstance3D.new()
	rock_b_multimesh     = MultiMeshInstance3D.new()
	rock_c_multimesh     = MultiMeshInstance3D.new()
	animals_container    = Node3D.new()
	static_body          = StaticBody3D.new()

	mesh_instance.name        = "TerrainMesh"
	outline_mesh_instance.name = "OutlineMesh"
	water_mesh_instance.name  = "WaterMesh"
	pine_multimesh.name       = "PineTrees"
	birch_multimesh.name      = "BirchTrees"
	simple_multimesh.name     = "SimpleTrees"
	stylized_multimesh.name   = "StylizedTrees"
	bush_a_multimesh.name     = "BushesA"
	rose_bush_multimesh.name  = "RoseBushes"
	rock_a_multimesh.name     = "RocksA"
	rock_b_multimesh.name     = "RocksB"
	rock_c_multimesh.name     = "RocksC"
	animals_container.name    = "Animals"
	static_body.name          = "Collision"

	add_child(mesh_instance)
	add_child(outline_mesh_instance)
	add_child(water_mesh_instance)
	add_child(pine_multimesh)
	add_child(birch_multimesh)
	add_child(simple_multimesh)
	add_child(stylized_multimesh)
	add_child(bush_a_multimesh)
	add_child(rose_bush_multimesh)
	add_child(rock_a_multimesh)
	add_child(rock_b_multimesh)
	add_child(rock_c_multimesh)
	add_child(animals_container)
	add_child(static_body)

## Reset for pool reuse — does NOT free or remove from scene tree.
func reset() -> void:
	mesh_instance.mesh            = null
	outline_mesh_instance.mesh    = null
	water_mesh_instance.mesh      = null
	pine_multimesh.multimesh      = null
	birch_multimesh.multimesh     = null
	simple_multimesh.multimesh    = null
	stylized_multimesh.multimesh  = null
	bush_a_multimesh.multimesh    = null
	rose_bush_multimesh.multimesh = null
	rock_a_multimesh.multimesh    = null
	rock_b_multimesh.multimesh    = null
	rock_c_multimesh.multimesh    = null

	# Free any collision shapes from previous use
	for child in static_body.get_children():
		child.free()
	
	# Free dynamic animals
	for child in animals_container.get_children():
		child.queue_free()

	chunk_key = Vector2i.ZERO
	rendered_terrain_version = -1
	rendered_vegetation_version = -1
	rendered_water_version = -1
	visible   = false
