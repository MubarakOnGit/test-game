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
	
	# Generate noise textures for the foam
	var noise1 = FastNoiseLite.new()
	noise1.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise1.frequency = 0.05
	var tex1 = NoiseTexture2D.new()
	tex1.noise = noise1
	tex1.seamless = true
	
	var noise2 = FastNoiseLite.new()
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise2.frequency = 0.08
	var tex2 = NoiseTexture2D.new()
	tex2.noise = noise2
	tex2.seamless = true
	
	mat.set_shader_parameter("noise1", tex1)
	mat.set_shader_parameter("noise2", tex2)
	
	# Render after opaque terrain so alpha blending composites correctly
	mat.render_priority = 1
	water_plane.material_override = mat
	# Water plane never casts or receives shadows
	water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(water_plane)

## Snaps the water plane to the camera to ensure it covers the visible area
func update_position(camera_pos: Vector3) -> void:
	var snap := float(ChunkData.CHUNK_SIZE) * ChunkData.TILE_SIZE
	water_plane.position.x = snappedf(camera_pos.x, snap)
	water_plane.position.z = snappedf(camera_pos.z, snap)
