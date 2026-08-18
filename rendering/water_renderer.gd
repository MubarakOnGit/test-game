class_name WaterRenderer
extends Node3D

var water_plane: MeshInstance3D

# ─── Two materials ────────────────────────────────────────────────────────────
# Cheap: flat blue — used when player is NOT in water (default, 99% of the time)
# Fancy: depth + waves + ripples — only when player steps in water
var _mat_cheap: ShaderMaterial
var _mat_fancy: ShaderMaterial
var _player_in_water := false

func _init() -> void:
	name = "WaterRenderer"
	
	water_plane = MeshInstance3D.new()
	water_plane.name = "WaterPlane"
	
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000, 8000)
	water_plane.mesh = plane
	water_plane.position.y = ChunkData.SEA_LEVEL + 0.45
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# ── Cheap material (default) ──────────────────────────────────────────────
	_mat_cheap = ShaderMaterial.new()
	_mat_cheap.shader = load("res://rendering/shaders/water.gdshader")
	_mat_cheap.render_priority = 1
	
	# ── Fancy material (player in water) ─────────────────────────────────────
	_mat_fancy = ShaderMaterial.new()
	_mat_fancy.shader = load("res://rendering/shaders/water_fancy.gdshader")
	_mat_fancy.render_priority = 1
	
	# Generate noise textures (shared idea, but fancy needs them)
	var noise1 = FastNoiseLite.new()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise1.frequency = 0.2
	var tex1 = NoiseTexture2D.new()
	tex1.noise = noise1
	tex1.seamless = true
	tex1.width = 256
	tex1.height = 256
	
	var noise2 = FastNoiseLite.new()
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise2.frequency = 0.35
	var tex2 = NoiseTexture2D.new()
	tex2.noise = noise2
	tex2.seamless = true
	tex2.width = 256
	tex2.height = 256
	
	_mat_fancy.set_shader_parameter("noise1", tex1)
	_mat_fancy.set_shader_parameter("noise2", tex2)
	
	# Pre-initialise ripple arrays
	_ripple_data_array.resize(MAX_RIPPLES)
	_ripple_params_array.resize(MAX_RIPPLES)
	for i in range(MAX_RIPPLES):
		_ripple_data_array[i] = Vector4.ZERO
		_ripple_params_array[i] = Vector4.ZERO
	_mat_fancy.set_shader_parameter("ripple_data", _ripple_data_array)
	_mat_fancy.set_shader_parameter("ripple_params", _ripple_params_array)
	_mat_fancy.set_shader_parameter("global_time", 0.0)
	
	# Start with the cheap material
	water_plane.material_override = _mat_cheap
	
	add_child(water_plane)
	
	WorldEventBus.water_ripple_spawned.connect(_on_ripple_spawned)

var _ripple_data_array: Array[Vector4]
var _ripple_params_array: Array[Vector4]
var _next_ripple_idx := 0
const MAX_RIPPLES := 16

## Called by player when entering or leaving water.
## Swaps the entire water plane to fancy or cheap shader instantly.
func set_player_in_water(in_water: bool) -> void:
	if _player_in_water == in_water:
		return
	_player_in_water = in_water
	water_plane.material_override = _mat_fancy if in_water else _mat_cheap

func _on_ripple_spawned(pos: Vector3, max_age: float, normal_strength: float, foam_strength: float, speed: float) -> void:
	var idx = _next_ripple_idx
	_next_ripple_idx = (_next_ripple_idx + 1) % MAX_RIPPLES
	var current_time = Time.get_ticks_msec() / 1000.0
	_ripple_data_array[idx] = Vector4(pos.x, pos.y, pos.z, current_time)
	_ripple_params_array[idx] = Vector4(max_age, normal_strength, foam_strength, speed)
	_mat_fancy.set_shader_parameter("ripple_data", _ripple_data_array)
	_mat_fancy.set_shader_parameter("ripple_params", _ripple_params_array)

func _process(_delta: float) -> void:
	# Only update time on the fancy material — cheap material doesn't need it
	if _player_in_water:
		_mat_fancy.set_shader_parameter("global_time", Time.get_ticks_msec() / 1000.0)

## Snaps the water plane to the camera to ensure it covers the visible area
func update_position(camera_pos: Vector3) -> void:
	var snap := float(ChunkData.CHUNK_SIZE) * ChunkData.TILE_SIZE
	water_plane.position.x = snappedf(camera_pos.x, snap)
	water_plane.position.z = snappedf(camera_pos.z, snap)
