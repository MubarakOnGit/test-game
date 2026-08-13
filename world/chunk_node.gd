class_name ChunkNode
extends Node3D

# ─── Scene Presence (exactly 4 nodes) ─────────────────────────────────────────
# All other nodes (1200+/chunk) are gone. The GPU does the work.
var mesh_instance:         MeshInstance3D       # merged terrain mesh (1 draw call)
var outline_mesh_instance: MeshInstance3D       # merged block outlines (1 draw call)
var water_mesh_instance:   MeshInstance3D       # merged water mesh (1 draw call)
var pine_multimesh:        MultiMeshInstance3D  # all pine trees  (1 draw call)
var oak_multimesh:         MultiMeshInstance3D  # all oak trees   (1 draw call)
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
	oak_multimesh        = MultiMeshInstance3D.new()
	static_body          = StaticBody3D.new()

	mesh_instance.name        = "TerrainMesh"
	outline_mesh_instance.name = "OutlineMesh"
	water_mesh_instance.name  = "WaterMesh"
	pine_multimesh.name       = "PineTrees"
	oak_multimesh.name        = "OakTrees"
	static_body.name          = "Collision"

	add_child(mesh_instance)
	add_child(outline_mesh_instance)
	add_child(water_mesh_instance)
	add_child(pine_multimesh)
	add_child(oak_multimesh)
	add_child(static_body)

## Reset for pool reuse — does NOT free or remove from scene tree.
func reset() -> void:
	mesh_instance.mesh            = null
	outline_mesh_instance.mesh    = null
	water_mesh_instance.mesh      = null
	pine_multimesh.multimesh      = null
	oak_multimesh.multimesh       = null

	# Free any collision shapes from previous use
	for child in static_body.get_children():
		child.free()

	chunk_key = Vector2i.ZERO
	rendered_terrain_version = -1
	rendered_vegetation_version = -1
	rendered_water_version = -1
	visible   = false
