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
var grass_multimesh:       MultiMeshInstance3D  # Grass variation A - short/young
var grass_multimesh_b:     MultiMeshInstance3D  # Grass variation B - medium/thick
var grass_multimesh_c:     MultiMeshInstance3D  # Grass variation C - tall/old
var flower_multimesh:      MultiMeshInstance3D  # Pixel flowers
var apple_ground_multimesh: MultiMeshInstance3D # Static settled apples (cheap MultiMesh)
var animals_container:     Node3D               # Container for dynamic animals
var static_body:           StaticBody3D         # merged terrain collision

var apple_tree_positions:  Array[Vector3] = []  # World positions of apple trees for spawning apples
var apple_tree_index:      int = 0               # Cycles through trees in order — no tree is skipped
var apple_spawn_timer:     float = -1.0
var apple_ground_positions: PackedVector3Array = PackedVector3Array()
var apple_ground_times: PackedFloat32Array = PackedFloat32Array()

## Global counter incremented every time any chunk drops an apple (used by DebugOverlay)
static var total_apples_dropped: int = 0

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
	grass_multimesh      = MultiMeshInstance3D.new()
	grass_multimesh_b    = MultiMeshInstance3D.new()
	grass_multimesh_c    = MultiMeshInstance3D.new()
	flower_multimesh     = MultiMeshInstance3D.new()
	apple_ground_multimesh = MultiMeshInstance3D.new()
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
	grass_multimesh.name      = "GrassTuftsA"
	grass_multimesh_b.name    = "GrassTuftsB"
	grass_multimesh_c.name    = "GrassTuftsC"
	flower_multimesh.name         = "Flowers"
	apple_ground_multimesh.name   = "AppleGround"
	animals_container.name        = "Animals"
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
	add_child(grass_multimesh)
	add_child(grass_multimesh_b)
	add_child(grass_multimesh_c)
	add_child(flower_multimesh)
	add_child(apple_ground_multimesh)
	add_child(animals_container)
	add_child(static_body)
	
	# Spawning handled in _process

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
	grass_multimesh.multimesh     = null
	grass_multimesh_b.multimesh   = null
	grass_multimesh_c.multimesh   = null
	flower_multimesh.multimesh      = null
	apple_ground_multimesh.multimesh = null
	apple_tree_positions.clear()
	apple_ground_positions.clear()
	apple_ground_times.clear()
	apple_spawn_timer = -1.0

	# Free any collision shapes from previous use
	for child in static_body.get_children():
		child.queue_free()
	
	# Free dynamic animals
	for child in animals_container.get_children():
		child.queue_free()

	chunk_key = Vector2i.ZERO
	rendered_terrain_version = -1
	rendered_vegetation_version = -1
	rendered_water_version = -1
	visible   = false

## Called by VegetationRenderer after apple_tree_positions is filled.
func begin_apple_drops() -> void:
	if apple_tree_positions.is_empty():
		return
	# Stagger start per chunk so all chunks don't tick at the same frame
	apple_spawn_timer = randf_range(0.5, 4.0)

func _spawn_apple() -> void:
	if apple_tree_positions.is_empty():
		return
	
	# Limit to max 3 ACTIVE FALLING physics apples per chunk at once.
	# Settled apples become free MultiMesh instances — unlimited!
	const MAX_FALLING := 3
	var falling_count := 0
	for child in animals_container.get_children():
		if child is Apple:
			falling_count += 1
	
	if falling_count < MAX_FALLING:
		# Cycle through trees in order so EVERY tree drops apples eventually
		var origin: Vector3 = apple_tree_positions[apple_tree_index % apple_tree_positions.size()]
		apple_tree_index += 1
		
		var apple := Apple.new()
		var offset := Vector3(randf_range(-1.5, 1.5), randf_range(3.0, 5.0), randf_range(-1.5, 1.5))
		apple.position = origin + offset
		apple.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		# When the apple settles, bake it into the static MultiMesh
		apple.settled.connect(_on_apple_settled)
		animals_container.add_child(apple)
		
		ChunkNode.total_apples_dropped += 1
	
	# We want exactly 3 apples per tree per in-game day (300 seconds)
	var trees_count: float = maxf(1.0, float(apple_tree_positions.size()))
	# Time between drops for the ENTIRE chunk = Total Day Time / Total Apples for Chunk
	var next_wait: float = 300.0 / (trees_count * 3.0)
	
	# Add slight randomization (+/- 10%) so it doesn't feel mechanical
	apple_spawn_timer = next_wait * randf_range(0.9, 1.1)

## Called when a falling Apple physics object comes to rest.
## Destroys the expensive RigidBody3D and adds the position to the
## static MultiMesh — so thousands of settled apples cost almost nothing.
func _on_apple_settled(world_pos: Vector3) -> void:
	# Convert to local position relative to this chunk node
	apple_ground_positions.append(world_pos - global_position)
	apple_ground_times.append(DayNightCycle.game_time)
	_rebuild_ground_apple_mesh()

func _rebuild_ground_apple_mesh() -> void:
	var count := apple_ground_positions.size()
	if count == 0:
		return
	
	# Load mesh once
	var apple_mesh: Mesh = null
	var packed: PackedScene = load("res://assets/apple.glb")
	if packed != null:
		var scene = packed.instantiate()
		apple_mesh = _find_first_mesh_static(scene)
		scene.queue_free()
	if apple_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.3, 0.3)
		apple_mesh = bm
	
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count   = count
	mm.mesh             = apple_mesh
	
	for i in count:
		var p: Vector3 = apple_ground_positions[i]
		var rot_y := float(i * 137) * 0.01  # deterministic rotation variety
		
		var now := DayNightCycle.game_time
		var age := now - apple_ground_times[i]
		var scale := 2.0
		if age > 270.0:
			# Rot starts after 270 seconds, fully rotted and disappeared at 300 seconds (1 in-game day)
			scale = maxf(0.0, 2.0 * (1.0 - (age - 270.0) / 30.0))
			
		var b := Basis.from_euler(Vector3(0, rot_y, 0)).scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, Transform3D(b, p))
	
	apple_ground_multimesh.multimesh = mm
	apple_ground_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	apple_ground_multimesh.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))

static func _find_first_mesh_static(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m = _find_first_mesh_static(child)
		if m != null:
			return m
	return null

func _process(delta: float) -> void:
	if not visible:
		return
		
	# Process apple spawning manually tied to game time speed
	if apple_spawn_timer >= 0.0:
		apple_spawn_timer -= delta * DayNightCycle.current_speed
		if apple_spawn_timer <= 0.0:
			_spawn_apple()

	# Periodically process apple rotting
	if apple_ground_positions.is_empty():
		return
		
	var now := DayNightCycle.game_time
	var needs_rebuild := false
	
	# Iterate backwards to safely remove elements
	for i in range(apple_ground_positions.size() - 1, -1, -1):
		var age := now - apple_ground_times[i]
		if age > 300.0:
			# Fully rotted, despawn it (1 in-game day = 300s)
			apple_ground_positions.remove_at(i)
			apple_ground_times.remove_at(i)
			needs_rebuild = true
		elif age > 270.0:
			# In the process of rotting, just mark for visual update (last 30s)
			needs_rebuild = true
			
	if needs_rebuild:
		_rebuild_ground_apple_mesh()
