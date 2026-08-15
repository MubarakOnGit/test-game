extends CharacterBody3D
class_name Animal

# ─── Tuning ───────────────────────────────────────────────────────────────────
const MAX_STEP_HEIGHT := 0.8   # Max height delta between tiles before rejecting direction
const TURN_SPEED      := 3.0   # Radians/sec for smooth rotation lerp

# ─── Per-animal Config ────────────────────────────────────────────────────────
@export var move_anim: String = "walk"  # Override per animal type (e.g. "run" for rabbit)

# ─── State ────────────────────────────────────────────────────────────────────
enum State { IDLE, WANDER }

var current_state: State = State.IDLE
var state_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var speed: float = 2.0
var is_water_animal: bool = false

# Memory: avoid immediately re-picking a blocked direction
var last_failed_direction: Vector3 = Vector3.ZERO

# Smooth rotation target (radians)
var target_rotation_y: float = 0.0

var anim_player: AnimationPlayer
var _ahead_ray: RayCast3D

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	anim_player = _find_anim_player(self)

	var coll_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	coll_shape.shape = sphere
	coll_shape.position = Vector3(0, 0.5, 0)
	add_child(coll_shape)
	
	_ahead_ray = RayCast3D.new()
	_ahead_ray.target_position = Vector3(0, -20, 0)
	add_child(_ahead_ray)

	target_rotation_y = rotation.y
	_pick_new_state()

# ─── Animation ────────────────────────────────────────────────────────────────

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var ap := _find_anim_player(child)
		if ap:
			return ap
	return null

func _play_anim(keyword: String) -> void:
	if not anim_player:
		return
	var anims := anim_player.get_animation_list()
	if anims.size() == 0:
		return
	for a in anims:
		if keyword.to_lower() in a.to_lower():
			if anim_player.current_animation != a:
				anim_player.play(a)
			return

# ─── Tile Look-Ahead ──────────────────────────────────────────────────────────

func _is_tile_ok_ahead(direction: Vector3) -> bool:
	# Cast from high up, 2 units ahead
	_ahead_ray.global_position = global_position + Vector3(0, 5, 0) + direction * 2.0
	_ahead_ray.force_raycast_update()
	
	if _ahead_ray.is_colliding():
		var hit_y = _ahead_ray.get_collision_point().y
		if hit_y <= 0.0:
			return false
		if absf(hit_y - global_position.y) > MAX_STEP_HEIGHT:
			return false
		return true
	return false

# ─── State Machine ────────────────────────────────────────────────────────────

func _pick_new_state() -> void:
	if randf() < 0.5:
		current_state = State.IDLE
		state_timer   = randf_range(2.0, 5.0)
		velocity      = Vector3.ZERO
	else:
		current_state = State.WANDER
		state_timer   = randf_range(3.0, 6.0)

		var chosen_dir := Vector3.ZERO
		for _i in range(4):
			var angle     := randf() * TAU
			var candidate := Vector3(cos(angle), 0.0, sin(angle))
			if last_failed_direction.length() > 0.1 and candidate.dot(last_failed_direction) > 0.9:
				continue
			if _is_tile_ok_ahead(candidate):
				chosen_dir = candidate
				break

		if chosen_dir == Vector3.ZERO:
			chosen_dir = -wander_direction if wander_direction.length() > 0.1 else Vector3(1.0, 0.0, 0.0)

		wander_direction  = chosen_dir
		target_rotation_y = atan2(wander_direction.x, wander_direction.z)

# ─── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		_pick_new_state()

	var is_in_water := global_position.y <= 0.0

	if current_state == State.WANDER:
		velocity.x = wander_direction.x * speed
		velocity.z = wander_direction.z * speed

		if is_water_animal:
			if not is_in_water:
				last_failed_direction = wander_direction
				wander_direction     *= -1.0
				velocity.x            = wander_direction.x * speed
				velocity.z            = wander_direction.z * speed
				target_rotation_y     = atan2(wander_direction.x, wander_direction.z)
			else:
				velocity.y = sin(Time.get_ticks_msec() * 0.002) * 0.5
		else:
			if is_in_water:
				last_failed_direction = wander_direction
				wander_direction     *= -1.0
				velocity.x            = wander_direction.x * speed
				velocity.z            = wander_direction.z * speed
				target_rotation_y     = atan2(wander_direction.x, wander_direction.z)
			else:
				if not is_on_floor():
					velocity.y -= 9.8 * delta
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * delta)
		if not is_water_animal and not is_on_floor():
			velocity.y -= 9.8 * delta
		elif is_water_animal:
			velocity.y = move_toward(velocity.y, 0.0, speed * delta)

	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * TURN_SPEED)

	if velocity.length() > 0.1:
		_play_anim(move_anim)
	else:
		_play_anim("idle")

	move_and_slide()
