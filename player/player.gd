class_name Player
extends CharacterBody3D

const SPEED = 12.0
const JUMP_VELOCITY = 15.0

var camera_y_rotation: float = 45.0 # Updated by WorldManager

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * 2.5

func _init() -> void:
	name = "Player"
	
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape
	collision.position = Vector3(0, 0.9, 0)
	add_child(collision)
	
	var mesh_instance = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.8
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0, 0.9, 0)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("#FF5252") # Keep the red player color!
	mesh_instance.material_override = mat
	
	add_child(mesh_instance)

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var input_x := Input.get_axis("ui_left", "ui_right")
	var input_y := Input.get_axis("ui_up", "ui_down")
	
	if Input.is_physical_key_pressed(KEY_A): input_x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input_x += 1.0
	if Input.is_physical_key_pressed(KEY_W): input_y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input_y += 1.0
	
	var input_dir := Vector2(clamp(input_x, -1.0, 1.0), clamp(input_y, -1.0, 1.0))
	
	# Rotate the input vector by the camera's Y rotation so W is always "up/forward" relative to the screen.
	var direction = (Vector3(input_dir.x, 0, input_dir.y)).rotated(Vector3.UP, deg_to_rad(camera_y_rotation)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
	_handle_water_ripples(direction != Vector3.ZERO)

enum WaterState { LAND, IN_WATER }
var _water_state := WaterState.LAND
var _distance_since_last_ripple := 0.0
var _idle_ripple_timer := 0.0
const PLAYER_HEIGHT := 1.8  # Capsule height

func _handle_water_ripples(is_moving: bool) -> void:
	var water_level = ChunkData.SEA_LEVEL + 0.45
	var feet_in_water = global_position.y <= water_level
	# Partially submerged = feet in water but head still above surface
	var head_y = global_position.y + PLAYER_HEIGHT
	var partially_submerged = feet_in_water and head_y > water_level
	
	if feet_in_water:
		if _water_state == WaterState.LAND:
			# ENTERING WATER -> Large Splash
			_water_state = WaterState.IN_WATER
			WorldEventBus.water_ripple_spawned.emit(global_position, 1.5, 0.8, 1.0, 4.0)
			_distance_since_last_ripple = 0.0
			_idle_ripple_timer = 0.0
		elif is_moving and partially_submerged:
			# IN WATER + MOVING -> Small walking ripples
			var step_dist = Vector2(velocity.x, velocity.z).length() * get_physics_process_delta_time()
			_distance_since_last_ripple += step_dist
			_idle_ripple_timer = 0.0  # Reset idle timer while moving
			
			if _distance_since_last_ripple > 1.2: # Spawn ripple every 1.2 meters
				_distance_since_last_ripple = 0.0
				WorldEventBus.water_ripple_spawned.emit(global_position, 0.8, 0.3, 0.2, 2.0)
		elif partially_submerged:
			# IN WATER + STANDING + PARTIALLY SUBMERGED -> Gentle idle ripples
			# Simulates the body displacing water even while still
			_idle_ripple_timer += get_physics_process_delta_time()
			if _idle_ripple_timer >= 2.5:
				_idle_ripple_timer = 0.0
				# Very subtle: low strength, slow expansion
				WorldEventBus.water_ripple_spawned.emit(global_position, 1.2, 0.15, 0.08, 1.2)
	else:
		if _water_state == WaterState.IN_WATER:
			# EXITING WATER
			_water_state = WaterState.LAND
			_idle_ripple_timer = 0.0
			WorldEventBus.water_ripple_spawned.emit(global_position, 1.0, 0.4, 0.3, 3.0)

