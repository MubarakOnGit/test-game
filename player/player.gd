class_name Player
extends CharacterBody3D

const WALK_SPEED = 6.0
const RUN_SPEED = 12.0
const JUMP_VELOCITY = 15.0

var camera_y_rotation: float = 45.0 # Updated by WorldManager
var water_renderer: WaterRenderer = null  # Assigned by WorldManager after init

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * 2.5

var _model: Node3D
var _anim: AnimationPlayer
var _current_anim: String = ""

func _init() -> void:
	name = "Player"
	
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.8
	collision.shape = shape
	collision.position = Vector3(0, 0.9, 0)
	add_child(collision)
	
	# Prevent sinking at terrain step edges but don't snap into water dips
	floor_snap_length  = 0.2
	floor_max_angle    = deg_to_rad(50.0)
	safe_margin        = 0.02
	
func _ready() -> void:
	add_to_group("player")
	var glb = load("res://assets/man.glb").instantiate()
	glb.scale = Vector3(2.5, 2.5, 2.5) # Scale up the tiny model
	add_child(glb)
	_model = glb
	_anim = glb.get_node("AnimationPlayer")
	if _anim:
		# Force looping for movement animations (GLB imports often default to no loop)
		var loop_anims = ["CharacterArmature|Idle", "CharacterArmature|Walk", "CharacterArmature|Run"]
		for a in loop_anims:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
				
		# Enable blending between animations
		_anim.set_blend_time("CharacterArmature|Idle", "CharacterArmature|Walk", 0.2)
		_anim.set_blend_time("CharacterArmature|Walk", "CharacterArmature|Idle", 0.2)
		_anim.set_blend_time("CharacterArmature|Walk", "CharacterArmature|Run", 0.2)
		_anim.set_blend_time("CharacterArmature|Run", "CharacterArmature|Walk", 0.2)
		_anim.set_blend_time("CharacterArmature|Idle", "CharacterArmature|Run", 0.2)
		_anim.set_blend_time("CharacterArmature|Run", "CharacterArmature|Idle", 0.2)
		_play_anim("CharacterArmature|Idle")

func _play_anim(anim_name: String) -> void:
	if _anim and _current_anim != anim_name:
		_anim.play(anim_name)
		_current_anim = anim_name

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
	
	var is_running = Input.is_physical_key_pressed(KEY_SHIFT)
	var current_speed = RUN_SPEED if is_running else WALK_SPEED
	
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
		# Rotate model to face direction of movement (inverted Z to face forwards)
		var target_rotation = atan2(direction.x, direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_rotation, 10.0 * delta)
		
		if is_running:
			_play_anim("CharacterArmature|Run")
		else:
			_play_anim("CharacterArmature|Walk")
	else:
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED)
		_play_anim("CharacterArmature|Idle")

	move_and_slide()
	
	# Push our position to the grass shader so nearby tufts bend away
	GrassRenderer.update_entities([global_position])
	
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
			if not is_in_group("water_prey"):
				add_to_group("water_prey")
			if water_renderer:
				water_renderer.set_player_in_water(true)
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
			_idle_ripple_timer += get_physics_process_delta_time()
			if _idle_ripple_timer > 2.0: # Every 2 seconds while idle
				_idle_ripple_timer = 0.0
				WorldEventBus.water_ripple_spawned.emit(global_position, 0.5, 0.15, 0.1, 3.0)
	else:
		if _water_state == WaterState.IN_WATER:
			# LEAVING WATER -> Medium Splash
			_water_state = WaterState.LAND
			if is_in_group("water_prey"):
				remove_from_group("water_prey")
			if water_renderer:
				water_renderer.set_player_in_water(false)
			WorldEventBus.water_ripple_spawned.emit(global_position, 1.2, 0.5, 0.8, 3.0)
