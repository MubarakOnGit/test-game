class_name WaterRenderer
extends Node3D

var water_plane: MeshInstance3D

func _init() -> void:
	name = "WaterRenderer"
	
	water_plane = MeshInstance3D.new()
	water_plane.name = "WaterPlane"
	
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000, 8000)   # larger — rivers & lakes stretch far
	water_plane.mesh = plane
	water_plane.position.y = ChunkData.SEA_LEVEL + 0.45

	var mat := ShaderMaterial.new()
	mat.shader = load("res://rendering/shaders/water.gdshader")
	
	# Generate noise textures for the wave surface
	var noise1 = FastNoiseLite.new()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise1.frequency = 0.2   # Coarser — visible at voxel scale
	var tex1 = NoiseTexture2D.new()
	tex1.noise = noise1
	tex1.seamless = true
	tex1.width = 256
	tex1.height = 256
	
	var noise2 = FastNoiseLite.new()
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise2.frequency = 0.35  # Slightly finer second layer
	var tex2 = NoiseTexture2D.new()
	tex2.noise = noise2
	tex2.seamless = true
	tex2.width = 256
	tex2.height = 256
	
	mat.set_shader_parameter("noise1", tex1)
	mat.set_shader_parameter("noise2", tex2)
	
	# Render after opaque terrain so alpha blending composites correctly
	mat.render_priority = 1
	water_plane.material_override = mat
	# Water plane never casts or receives shadows
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(water_plane)
	
	# Pre-initialise ripple arrays and push zeros to the material so
	# the shader never sees an unbound uniform on the first frame.
	_ripple_data_array.resize(MAX_RIPPLES)
	_ripple_params_array.resize(MAX_RIPPLES)
	for i in range(MAX_RIPPLES):
		_ripple_data_array[i] = Vector4.ZERO
		_ripple_params_array[i] = Vector4.ZERO
	mat.set_shader_parameter("ripple_data", _ripple_data_array)
	mat.set_shader_parameter("ripple_params", _ripple_params_array)
	mat.set_shader_parameter("global_time", 0.0)
	
	WorldEventBus.water_ripple_spawned.connect(_on_ripple_spawned)

var _ripple_data_array: Array[Vector4]
var _ripple_params_array: Array[Vector4]
var _next_ripple_idx := 0
const MAX_RIPPLES := 16

func _on_ripple_spawned(pos: Vector3, max_age: float, normal_strength: float, foam_strength: float, speed: float) -> void:
	# Add to cyclic buffer
	var idx = _next_ripple_idx
	_next_ripple_idx = (_next_ripple_idx + 1) % MAX_RIPPLES
	
	# Pack data
	# data: x, y, z (world pos), w (spawn time based on Time.get_ticks_msec)
	# params: x (max_age), y (normal_strength), z (foam_strength), w (speed)
	var current_time = Time.get_ticks_msec() / 1000.0
	_ripple_data_array[idx] = Vector4(pos.x, pos.y, pos.z, current_time)
	_ripple_params_array[idx] = Vector4(max_age, normal_strength, foam_strength, speed)
	
	# Update shader arrays
	var mat := water_plane.material_override as ShaderMaterial
	mat.set_shader_parameter("ripple_data", _ripple_data_array)
	mat.set_shader_parameter("ripple_params", _ripple_params_array)

func _process(delta: float) -> void:
	var mat := water_plane.material_override as ShaderMaterial
	mat.set_shader_parameter("global_time", Time.get_ticks_msec() / 1000.0)

## Snaps the water plane to the camera to ensure it covers the visible area
func update_position(camera_pos: Vector3) -> void:
	var snap := float(ChunkData.CHUNK_SIZE) * ChunkData.TILE_SIZE
	water_plane.position.x = snappedf(camera_pos.x, snap)
	water_plane.position.z = snappedf(camera_pos.z, snap)
