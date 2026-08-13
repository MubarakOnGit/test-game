extends Node3D

# ─── CONFIG ───
const CHUNK_SIZE: int = 16
const RENDER_DISTANCE: int = 4
const TILE_SIZE: float = 1.0
const SPACING: float = 1.0
const BOTTOM_Y: float = -2.0
const SEA_LEVEL: float = 0.0

# ─── TIME & DAY/NIGHT CYCLE ───
var time_of_day: float = 10.0 # 0.0 to 24.0, 12.0 = Noon
var time_speed: float = 1.0
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env_node: WorldEnvironment
var time_label: Label

# ─── NOISE LAYERS ───
var base_noise: FastNoiseLite
var mountain_noise: FastNoiseLite
var river_noise: FastNoiseLite
var detail_noise: FastNoiseLite
var color_noise: FastNoiseLite

# ─── CAMERA / PLAYER ───
var camera_pivot: Node3D
var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_speed: float = 22.0
var player_marker: MeshInstance3D

# ─── WORLD STATE ───
var loaded_chunks: Dictionary = {}
var chunk_queue: Array[Vector2i] = []
var water_plane: MeshInstance3D
var pine_tree_scene: PackedScene = preload("res://assets/pineTree.glb")
var oak_tree_scene: PackedScene = preload("res://assets/oakTree.glb")

# ─── PALETTES ───
var grass_colors := [
	Color("#7ec628"), Color("#6db520"), Color("#8dd430"),
	Color("#5ea018"), Color("#91d832"), Color("#72c024"), Color("#9be040"),
]
var dirt_colors := [
	Color("#8B5E3C"), Color("#7a5030"), Color("#9a6a48"), Color("#6e4428"),
]
var sand_colors := [
	Color("#d4b55a"), Color("#e6c86a"), Color("#c8a848"),
]
var rock_colors := [
	Color("#888890"), Color("#7c7c84"), Color("#94949c"), Color("#707078"),
]
var snow_color := Color("#EDEDF0")

func _ready():
	randomize()
	_init_noise()
	_setup_water()
	_setup_camera()
	_setup_lighting()
	_setup_ui()
	_setup_player_marker()

func _init_noise():
	base_noise = FastNoiseLite.new()
	base_noise.seed = 111
	base_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	base_noise.frequency = 0.012
	base_noise.fractal_octaves = 3

	mountain_noise = FastNoiseLite.new()
	mountain_noise.seed = 222
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	mountain_noise.frequency = 0.008
	mountain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	mountain_noise.fractal_octaves = 4

	river_noise = FastNoiseLite.new()
	river_noise.seed = 333
	river_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	river_noise.frequency = 0.005
	river_noise.fractal_octaves = 2

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 444
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.08
	detail_noise.fractal_octaves = 2

	color_noise = FastNoiseLite.new()
	color_noise.seed = 555
	color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	color_noise.frequency = 0.01
	color_noise.fractal_octaves = 2

func _process(delta):
	_handle_camera_input(delta)
	_update_chunks()
	_update_water_position()
	_update_time_and_lighting(delta)

# ─── TIME & LIGHTING UPDATE ───
func _update_time_and_lighting(delta: float):
	time_of_day += time_speed * delta * 0.1 # Real-time seconds multiplier
	if time_of_day >= 24.0:
		time_of_day -= 24.0

	# Map time of day (0-24) to sun rotation
	# 6:00 AM (6.0) = -180 deg (sunrise)
	# 12:00 PM (12.0) = -90 deg (noon)
	# 18:00 PM (18.0) = 0 deg (sunset)
	var sun_angle := ((time_of_day - 6.0) / 24.0) * TAU
	
	# The sun orbits perpendicular to the camera (-45 deg vs camera's +45 deg)
	# This makes shadows cast across the screen from left to right.
	sun.rotation = Vector3(-sun_angle, deg_to_rad(-45.0), 0)
	
	# The moon is exactly opposite the sun
	moon.rotation = Vector3(-sun_angle + PI, deg_to_rad(-45.0), 0)
	
	# Fade light energy based on whether they are above the horizon
	var sun_height := sin(sun_angle)
	var moon_height := sin(sun_angle + PI)
	
	sun.light_energy = clampf(sun_height * 2.0, 0.0, 1.5)
	moon.light_energy = clampf(moon_height * 2.0, 0.0, 0.4)

	# Update UI Label
	var hours := int(time_of_day)
	var minutes := int((time_of_day - hours) * 60)
	if time_label:
		time_label.text = "%02d:%02d" % [hours, minutes]

# ─── CAMERA ───
func _setup_camera():
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 38
	camera.near = 0.1
	camera.far = 500

	camera_pivot.add_child(camera)
	camera.make_current()
	camera_pivot.rotation_degrees = Vector3(-35.264, 45, 0)
	camera.position = Vector3(0, 0, 60)
	camera_pivot.position = camera_target

func _handle_camera_input(delta):
	var input := Vector3.ZERO
	if Input.is_action_pressed("ui_left")  or Input.is_key_pressed(KEY_A): input.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D): input.x += 1
	if Input.is_action_pressed("ui_up")    or Input.is_key_pressed(KEY_W): input.z -= 1
	if Input.is_action_pressed("ui_down")  or Input.is_key_pressed(KEY_S): input.z += 1

	if input != Vector3.ZERO:
		var move: Vector3 = input.normalized() * camera_speed * float(delta)
		if player_marker:
			player_marker.position += move
			camera_target = player_marker.position
		else:
			camera_target += move
		camera_pivot.position = camera_target

# ─── WATER ───
func _setup_water():
	water_plane = MeshInstance3D.new()
	water_plane.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	water_plane.mesh = plane
	water_plane.position.y = SEA_LEVEL + 0.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.60, 0.90, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.08
	mat.metallic = 0.1
	water_plane.material_override = mat
	add_child(water_plane)

func _update_water_position():
	water_plane.position.x = snappedf(camera_target.x, TILE_SIZE)
	water_plane.position.z = snappedf(camera_target.z, TILE_SIZE)

# ─── CHUNK SYSTEM ───
func _update_chunks():
	var cam_cx := int(floor(camera_target.x / (CHUNK_SIZE * SPACING)))
	var cam_cz := int(floor(camera_target.z / (CHUNK_SIZE * SPACING)))

	for cx in range(cam_cx - RENDER_DISTANCE, cam_cx + RENDER_DISTANCE + 1):
		for cz in range(cam_cz - RENDER_DISTANCE, cam_cz + RENDER_DISTANCE + 1):
			var key := Vector2i(cx, cz)
			if not loaded_chunks.has(key) and not chunk_queue.has(key):
				chunk_queue.append(key)

	if chunk_queue.size() > 0:
		chunk_queue.sort_custom(func(a, b):
			return Vector2(a.x - cam_cx, a.y - cam_cz).length_squared() < \
				   Vector2(b.x - cam_cx, b.y - cam_cz).length_squared()
		)
		var k = chunk_queue.pop_front()
		_load_chunk(k.x, k.y)

	var to_remove: Array[Vector2i] = []
	for key in loaded_chunks.keys():
		if abs(key.x - cam_cx) > RENDER_DISTANCE + 1 or abs(key.y - cam_cz) > RENDER_DISTANCE + 1:
			to_remove.append(key)
	var i := chunk_queue.size() - 1
	while i >= 0:
		var key := chunk_queue[i]
		if abs(key.x - cam_cx) > RENDER_DISTANCE + 1 or abs(key.y - cam_cz) > RENDER_DISTANCE + 1:
			chunk_queue.remove_at(i)
		i -= 1
	if to_remove.size() > 0:
		loaded_chunks[to_remove[0]].queue_free()
		loaded_chunks.erase(to_remove[0])

func _load_chunk(cx: int, cz: int):
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [cx, cz]
	chunk.position = Vector3(cx * CHUNK_SIZE * SPACING, 0, cz * CHUNK_SIZE * SPACING)
	
	# First pass: terrain tiles
	for lx in range(CHUNK_SIZE):
		for lz in range(CHUNK_SIZE):
			var world_x := cx * CHUNK_SIZE + lx
			var world_z := cz * CHUNK_SIZE + lz
			var h := _get_height(world_x, world_z)
			
			if h < 1.0:
				continue
			
			var is_sand := _is_shore(world_x, world_z, h)
			var is_rock := h >= 4.0
			
			var nn := _get_height(world_x, world_z - 1)
			var ns := _get_height(world_x, world_z + 1)
			var ne := _get_height(world_x + 1, world_z)
			var nw := _get_height(world_x - 1, world_z)
			
			_create_tile(chunk, lx, lz, world_x, world_z, h, is_sand, is_rock, nn, ns, ne, nw)
	
	# Second pass: trees on suitable grass tiles
	var tree_noise := FastNoiseLite.new()
	tree_noise.seed = 200
	tree_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	tree_noise.frequency = 0.08
	
	for lx in range(CHUNK_SIZE):
		for lz in range(CHUNK_SIZE):
			var world_x := cx * CHUNK_SIZE + lx
			var world_z := cz * CHUNK_SIZE + lz
			var h := _get_height(world_x, world_z)
			
			# Only place trees on grass (height 2-3, not sand/rock/snow/water)
			if h < 2.0 or h > 3.0:
				continue
			if _is_shore(world_x, world_z, h):
				continue
			
			# 1. Jittered grid check (guarantees trees don't overlap without neighbor checking)
			if not _is_tree_tile(world_x, world_z):
				continue
			
			# 2. Are we in a forest biome?
			var t := tree_noise.get_noise_2d(float(world_x), float(world_z))
			if t < 0.0:  # 0.0 means roughly 50% of the world is forests
				continue
			
			# Pick tree type based on noise
			var tree: Node3D
			if t > 0.5:
				tree = _create_oak_tree()
			else:
				tree = _create_pine_tree()
			
			# Position on top of the terrain tile
			tree.position = Vector3(
				lx * SPACING + SPACING / 2.0,
				float(h),
				lz * SPACING + SPACING / 2.0
			)
			chunk.add_child(tree)
	
	add_child(chunk)
	loaded_chunks[Vector2i(cx, cz)] = chunk

func _is_tree_tile(world_x: int, world_z: int) -> bool:
	# Divide world into 4x4 chunks. Each chunk gets exactly 1 candidate tree.
	var cell_x := floori(float(world_x) / 4.0)
	var cell_z := floori(float(world_z) / 4.0)
	
	# Procedural pseudo-random offset based on cell coordinates
	var h: int = abs(hash(Vector2i(cell_x, cell_z)))
	var offset_x: int = h % 4
	var offset_z: int = (h / 4) % 4
	
	var chosen_x := cell_x * 4 + offset_x
	var chosen_z := cell_z * 4 + offset_z
	
	return world_x == chosen_x and world_z == chosen_z

# ═══════════════════════════════════════════════
# ─── HEIGHT GENERATION (Established Voxel Style)
# ═══════════════════════════════════════════════
func _get_height(world_x: int, world_z: int) -> float:
	var fx := float(world_x)
	var fz := float(world_z)

	var base_val := base_noise.get_noise_2d(fx, fz)
	var h := remap(base_val, -1.0, 1.0, 0.5, 4.5)

	var mtn_val := mountain_noise.get_noise_2d(fx, fz)
	var mtn: float = 1.0 - mtn_val 
	if mtn > 0.4 and base_val > 0.2:
		h += (mtn - 0.4) * 5.0 

	var riv_val := river_noise.get_noise_2d(fx, fz)
	var river_depth: float = 1.0 - abs(riv_val)
	if river_depth > 0.85:
		h -= (river_depth - 0.85) * 15.0 

	h = floor(h)

	if h > SEA_LEVEL and h < 5.0:
		var d := detail_noise.get_noise_2d(fx, fz)
		if d > 0.6:
			var is_cliff := false
			var raw_self := _get_raw_height(world_x, world_z)
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if dx == 0 and dz == 0: continue
					if abs(_get_raw_height(world_x + dx, world_z + dz) - raw_self) > 0.5:
						is_cliff = true
						break
			if not is_cliff:
				h += 1.0

	return h

func _get_raw_height(world_x: int, world_z: int) -> float:
	var fx := float(world_x)
	var fz := float(world_z)

	var base_val := base_noise.get_noise_2d(fx, fz)
	var h := remap(base_val, -1.0, 1.0, 0.5, 4.5)

	var mtn_val := mountain_noise.get_noise_2d(fx, fz)
	var mtn: float = 1.0 - mtn_val 
	if mtn > 0.4 and base_val > 0.2:
		h += (mtn - 0.4) * 5.0 

	var riv_val := river_noise.get_noise_2d(fx, fz)
	var river_depth: float = 1.0 - abs(riv_val)
	if river_depth > 0.85:
		h -= (river_depth - 0.85) * 15.0

	return floor(h)

# ─── TILE TYPE CHECKS ───
func _is_shore(world_x: int, world_z: int, surface_y: float) -> bool:
	if surface_y == SEA_LEVEL + 1.0:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dz == 0: continue
				if _get_raw_height(world_x + dx, world_z + dz) <= SEA_LEVEL:
					return true
	return false

# ─── TILE CREATION ───
func _create_tile(chunk: Node3D, lx: int, lz: int, world_x: int, world_z: int,
		surface_y: float, is_sand: bool, is_rock: bool,
		nn: float, ns: float, ne: float, nw: float):
	var mesh := MeshInstance3D.new()

	var thickness := surface_y - BOTTOM_Y
	thickness = max(thickness, 1.0)
	var center_y := (surface_y + BOTTOM_Y) / 2.0

	var box := BoxMesh.new()
	box.size = Vector3(TILE_SIZE, thickness, TILE_SIZE)
	mesh.mesh = box
	mesh.position = Vector3(
		lx * SPACING + SPACING * 0.5,
		center_y,
		lz * SPACING + SPACING * 0.5
	)

	var c := color_noise.get_noise_2d(float(world_x), float(world_z))
	var grass_idx := clampi(int(remap(c, -1.0, 1.0, 0.0, float(grass_colors.size()))), 0, grass_colors.size() - 1)
	var dirt_idx  := clampi(int(remap(c, -1.0, 1.0, 0.0, float(dirt_colors.size()))),  0, dirt_colors.size()  - 1)
	var sand_idx  := clampi(int(remap(c, -1.0, 1.0, 0.0, float(sand_colors.size()))),  0, sand_colors.size()  - 1)
	var rock_idx  := clampi(int(remap(c, -1.0, 1.0, 0.0, float(rock_colors.size()))),  0, rock_colors.size()  - 1)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://tile_shader.gdshader")
	mat.set_shader_parameter("grass_color", grass_colors[grass_idx])
	mat.set_shader_parameter("dirt_color",  dirt_colors[dirt_idx])
	mat.set_shader_parameter("rock_color",  rock_colors[rock_idx])
	mat.set_shader_parameter("sand_color",  sand_colors[sand_idx])
	mat.set_shader_parameter("snow_color",  snow_color)
	mat.set_shader_parameter("surface_y",   surface_y)
	mat.set_shader_parameter("neighbor_n",  nn)
	mat.set_shader_parameter("neighbor_s",  ns)
	mat.set_shader_parameter("neighbor_e",  ne)
	mat.set_shader_parameter("neighbor_w",  nw)
	mat.set_shader_parameter("is_sand",     is_sand)
	mat.set_shader_parameter("is_rock",     is_rock)

	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	chunk.add_child(mesh)

# ─── LIGHTING & ENVIRONMENT ───
func _setup_lighting():
	# Sun
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#FFF5E0")
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 180
	add_child(sun)
	
	# Moon
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#8bb6f2")
	moon.shadow_enabled = true
	moon.shadow_bias = 0.03
	moon.directional_shadow_max_distance = 180
	add_child(moon)

	# Procedural Sky Environment
	env_node = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#3779c4")
	sky_mat.sky_horizon_color = Color("#87ceeb")
	sky_mat.ground_bottom_color = Color("#1e2c3a")
	sky_mat.ground_horizon_color = Color("#4b6278")
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.15
	
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	
	env_node.environment = env
	add_child(env_node)

# ─── UI ───
func _setup_ui():
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	
	time_label = Label.new()
	time_label.text = "12:00"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var label_settings = LabelSettings.new()
	label_settings.font_size = 24
	time_label.label_settings = label_settings
	vbox.add_child(time_label)
	
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)
	
	var btn_pause = Button.new()
	btn_pause.text = "⏸️ Pause"
	btn_pause.pressed.connect(func(): time_speed = 0.0)
	hbox.add_child(btn_pause)
	
	var btn_play = Button.new()
	btn_play.text = "▶️ 1x"
	btn_play.pressed.connect(func(): time_speed = 1.0)
	hbox.add_child(btn_play)
	
	var btn_fast = Button.new()
	btn_fast.text = "⏩ 10x"
	btn_fast.pressed.connect(func(): time_speed = 10.0)
	hbox.add_child(btn_fast)
	
	var btn_super = Button.new()
	btn_super.text = "🚀 60x"
	btn_super.pressed.connect(func(): time_speed = 60.0)
	hbox.add_child(btn_super)

# ─── PLAYER MARKER ───
func _setup_player_marker():
	player_marker = MeshInstance3D.new()
	player_marker.name = "PlayerMarker"
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.8, 0.4)
	player_marker.mesh = box
	player_marker.position = Vector3(0, 2.0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#FF5252")
	player_marker.material_override = mat
	add_child(player_marker)

# ─── TREE GENERATION ───

func _create_pine_tree() -> Node3D:
	var tree: Node3D = pine_tree_scene.instantiate()
	tree.name = "PineTree"
	tree.scale = Vector3(3.0, 3.0, 3.0)
	return tree

func _create_oak_tree() -> Node3D:
	var tree: Node3D = oak_tree_scene.instantiate()
	tree.name = "OakTree"
	tree.scale = Vector3(3.0, 3.0, 3.0)
	return tree
