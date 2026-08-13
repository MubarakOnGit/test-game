class_name WorldManager
extends Node3D

# ─── Core Engine Subsystems ───────────────────────────────────────────────────
var database: WorldDatabase
var chunk_manager: ChunkManager
var profiler: Profiler
var water_renderer: WaterRenderer
var command_system: CommandSystem

# ─── Scene Elements ───────────────────────────────────────────────────────────
var camera_pivot: Node3D
var camera: Camera3D
var camera_scaler: CameraScaler
var camera_target := Vector3.ZERO
var camera_speed: float = 22.0

# ── Camera rotation (middle-mouse drag) ───────────────────────────────────────
var _is_rotating: bool = false
var _rotation_y: float = 45.0          # Current Y-angle in degrees
const _ROTATE_SENSITIVITY: float = 0.4 # Degrees per pixel dragged
var player: Player

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env_node: WorldEnvironment
var day_night_cycle: DayNightCycle

const WORLD_SEED := 12345
const ORIGIN_SHIFT_THRESHOLD := 8000.0

func _ready() -> void:
	# 1. Initialize core systems
	database = WorldDatabase.new()
	profiler = Profiler.new()
	command_system = CommandSystem.new()
	add_child(command_system)
	
	chunk_manager = ChunkManager.new(database, WORLD_SEED)
	add_child(chunk_manager)
	
	# 2. Setup rendering environment
	_setup_camera()
	_setup_lighting()
	_setup_player()
	
	water_renderer = WaterRenderer.new()
	add_child(water_renderer)
	
	# 3. Setup debug UI
	var hud_scene = load("res://debug/profiler_hud.gd")
	if hud_scene:
		var hud = hud_scene.new(profiler, database)
		hud.day_night_cycle = day_night_cycle
		add_child(hud)
		
	var debug_overlay = DebugOverlay.new()
	debug_overlay.setup(chunk_manager)
	add_child(debug_overlay)
		
	# Initial generate
	var center_chunk = _get_camera_chunk()
	chunk_manager.tick(center_chunk)
	
	# DEBUG: Scan the entire scene tree for rogue meshes
	print("DEBUG: SCENE TREE DUMP START")
	_debug_dump_tree(get_tree().root, 0)
	print("DEBUG: SCENE TREE DUMP END")
	
	# DEBUG: check first generated chunk for bad trees
	var data = database.get_chunk(center_chunk)
	if data:
		print("DEBUG: Checking center chunk trees...")
		var veg = data.vegetation
		for i in range(veg.count()):
			var lx = veg.local_xs[i]
			var lz = veg.local_zs[i]
			var hidx = ChunkData.hi(int(lx), int(lz))
			var h = data.heights[hidx]
			var w = data.water_levels[hidx]
			var biome = data.biomes[ChunkData.bi(int(lx), int(lz))]
			if h < 2.0:
				print("BAD TREE: h=", h, " w=", w, " biome=", biome, " lx=", lx, " lz=", lz)
	
	var sim_manager = SimulationManager.new()
	sim_manager.setup(database, chunk_manager)
	add_child(sim_manager)
	
	var scheduler = FrameScheduler.new()
	scheduler.setup(profiler, chunk_manager, sim_manager, self)
	add_child(scheduler)
	
	var region_manager = RegionManager.new(database)
	add_child(region_manager)
	


func _process(delta: float) -> void:
	_handle_camera_input(delta)
	
	if camera_target.length() > ORIGIN_SHIFT_THRESHOLD:
		_shift_world_origin(camera_target)
		
	water_renderer.update_position(camera_target)
		
	if player:
		player.camera_y_rotation = _rotation_y

func _shift_world_origin(offset: Vector3) -> void:
	# Shift the world origin to prevent floating-point precision issues
	for node in chunk_manager.get_children():
		if node is ChunkNode:
			node.position -= offset
			
	if player:
		player.position -= offset
	
	camera_target = Vector3.ZERO
	camera_pivot.position = camera_target

func _get_camera_chunk() -> Vector2i:
	var cx := floori(camera_target.x / (ChunkData.CHUNK_SIZE * ChunkData.TILE_SIZE))
	var cz := floori(camera_target.z / (ChunkData.CHUNK_SIZE * ChunkData.TILE_SIZE))
	return Vector2i(cx, cz)

func _debug_dump_tree(node: Node, depth: int) -> void:
	var indent = ""
	for i in range(depth): indent += "  "
	
	var node_type = node.get_class()
	if node is MultiMeshInstance3D:
		var count = 0
		if node.multimesh: count = node.multimesh.instance_count
		print(indent, node.name, " (", node_type, ") - Instances: ", count)
	elif node is MeshInstance3D:
		print(indent, node.name, " (", node_type, ")")
	elif depth < 3: # Only print non-meshes for top levels to save spam
		print(indent, node.name, " (", node_type, ")")
		
	for child in node.get_children():
		_debug_dump_tree(child, depth + 1)

# ─── Camera & Input ───────────────────────────────────────────────────────────

func _setup_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 38  # Base size — overridden immediately by CameraScaler
	camera.near = 0.1
	camera.far = 500

	camera_pivot.add_child(camera)
	camera.make_current()
	camera_pivot.rotation_degrees = Vector3(-35.264, _rotation_y, 0.0)
	camera.position = Vector3(0, 0, 60)
	camera_pivot.position = camera_target

	# Responsive scaling — adjusts camera.size to match any screen resolution
	camera_scaler = CameraScaler.new()
	camera_scaler.name = "CameraScaler"
	add_child(camera_scaler)
	camera_scaler.setup(camera)

func _handle_camera_input(_delta: float) -> void:
	if player:
		camera_target = player.position
		camera_pivot.position = camera_target

	# Apply live rotation to the pivot
	camera_pivot.rotation_degrees = Vector3(-35.264, _rotation_y, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	# ── Middle-mouse drag to rotate ───────────────────────────────────────────
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_is_rotating = event.pressed
			if not _is_rotating:
				# Snap to nearest 45° on release for clean isometric angles
				_rotation_y = roundf(_rotation_y / 45.0) * 45.0

	if event is InputEventMouseMotion and _is_rotating:
		_rotation_y -= event.relative.x * _ROTATE_SENSITIVITY

	# ── Keyboard shortcuts ────────────────────────────────────────────────────
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and Input.is_key_pressed(KEY_CTRL):
			command_system.undo()
		elif event.keycode == KEY_Y and Input.is_key_pressed(KEY_CTRL):
			command_system.redo()



# ─── Environment ──────────────────────────────────────────────────────────────

func _setup_lighting() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.directional_shadow_max_distance = 180
	add_child(sun)
	
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#8bb6f2")
	moon.shadow_enabled = false   # Moon only fills ambient, no hard shadows
	moon.shadow_bias = 0.03
	moon.directional_shadow_max_distance = 180
	add_child(moon)
	
	env_node = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	
	var sky_mat := ProceduralSkyMaterial.new()
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
	
	# ── Day/Night Cycle ───────────────────────────────────────────────────────
	day_night_cycle = DayNightCycle.new()
	day_night_cycle.sun     = sun
	day_night_cycle.moon    = moon
	day_night_cycle.sky_mat = sky_mat
	day_night_cycle.env     = env
	add_child(day_night_cycle)
	# Apply starting state immediately so first frame looks correct
	day_night_cycle._apply()

func _setup_player() -> void:
	player = Player.new()
	player.position = Vector3(0, 15.0, 0) # Start high and drop in
	add_child(player)
