class_name Apple
extends RigidBody3D

## Emitted when the apple settles on the ground.
## The chunk uses this position to bake it into a static MultiMesh.
signal settled(world_position: Vector3)

const SETTLE_SPEED   := 0.08   # m/s threshold to consider "at rest"
const SETTLE_TIME    := 1.2    # seconds at rest before converting
const MAX_FALL_TIME  := 8.0    # safety despawn if apple never lands

var _rest_timer: float = 0.0
var _alive_timer: float = 0.0

func _ready() -> void:
	# Add mesh
	var mi := MeshInstance3D.new()
	mi.mesh = _get_apple_mesh_static()

	mi.scale = Vector3(2.0, 2.0, 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)

	# Add physics shape
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)
	cs.shape = shape
	add_child(cs)
	
	# Physics properties
	mass = 0.5
	can_sleep = true
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = 0.35
	physics_material_override.friction = 0.9

func _physics_process(delta: float) -> void:
	_alive_timer += delta
	
	# Safety: despawn if it falls forever (e.g. off the edge of terrain)
	if _alive_timer > MAX_FALL_TIME:
		queue_free()
		return
	
	# Check if the apple has come to rest
	if linear_velocity.length() < SETTLE_SPEED and _alive_timer > 1.0:
		_rest_timer += delta
		if _rest_timer >= SETTLE_TIME:
			# Emit the settled signal with world position so the chunk
			# can bake this into the static MultiMesh
			settled.emit(global_position)
			queue_free()
	else:
		_rest_timer = 0.0

static var _cached_mesh: Mesh = null

static func _get_apple_mesh_static() -> Mesh:
	if _cached_mesh == null:
		var packed: PackedScene = load("res://assets/apple.glb")
		if packed != null:
			var scene = packed.instantiate()
			_cached_mesh = _find_first_mesh_static(scene)
			scene.queue_free()
		if _cached_mesh == null:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.3, 0.3)
			_cached_mesh = bm
			
		# Ensure vertex colors work
		for i in _cached_mesh.get_surface_count():
			var mat = _cached_mesh.surface_get_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
				_cached_mesh.surface_set_material(i, mat)
			if mat is StandardMaterial3D:
				mat.vertex_color_use_as_albedo = true
				mat.metallic = 0.0
				mat.roughness = 1.0
	return _cached_mesh

static func _find_first_mesh_static(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var m = _find_first_mesh_static(child)
		if m != null:
			return m
	return null
