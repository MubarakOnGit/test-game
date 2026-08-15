extends CharacterBody3D
class_name Animal

# ─── Tuning ───────────────────────────────────────────────────────────────────
const MAX_STEP_HEIGHT := 0.8   # Max height delta between tiles before rejecting direction
const TURN_SPEED      := 3.0   # Radians/sec for smooth rotation lerp

# ─── Per-animal Config ────────────────────────────────────────────────────────
@export var move_anim: String = "walk"  # Override per animal type (e.g. "run" for rabbit)

# ─── State ────────────────────────────────────────────────────────────────────
enum State { IDLE, WALK, RUN }

var current_state: State = State.IDLE
var state_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var walk_speed: float = 2.0
var run_speed: float = 4.8
var current_speed: float = 2.0
var is_water_animal: bool = false

# Memory: avoid immediately re-picking a blocked direction
var last_failed_direction: Vector3 = Vector3.ZERO

# Smooth rotation target (radians)
var target_rotation_y: float = 0.0

var anim_player: AnimationPlayer
var _ahead_ray: RayCast3D
var _visual: Node3D
var _anim_tween: Tween

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

	for child in get_children():
		if child is Node3D and not child is CollisionShape3D and not child is RayCast3D and not child is AnimationPlayer:
			_visual = child
			break

	target_rotation_y = rotation.y
	_pick_new_state()

	# Debug: confirm what was found
	if anim_player:
		print("[Animal] AnimationPlayer found on: ", name, " | Anims: ", anim_player.get_animation_list())
	else:
		print("[Animal] NO AnimationPlayer found on: ", name, " — using Tween fallback")

# ─── Animation ────────────────────────────────────────────────────────────────

func _find_anim_player(node: Node) -> AnimationPlayer:
	# Depth-first search through the entire subtree
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null

func _play_anim(keyword: String) -> void:
	# ── AnimationPlayer path ─────────────────────────────────────────────────
	if anim_player:
		var anims := anim_player.get_animation_list()
		var best_match: String = ""
		var keyword_lower := keyword.to_lower()
		
		for a in anims:
			var anim_name_lower := a.to_lower()
			
			# Exact keyword match is best
			if keyword_lower in anim_name_lower:
				best_match = a
				break
			# Fallback for "run" to use "gallop", "fast", "hop", or "walk"
			elif keyword_lower == "run" and ("gallop" in anim_name_lower or "fast" in anim_name_lower or "hop" in anim_name_lower or "walk" in anim_name_lower):
				if best_match == "":
					best_match = a
			# Fallback for "walk" to use "swim", "fly", or "hop"
			elif keyword_lower == "walk" and ("swim" in anim_name_lower or "fly" in anim_name_lower or "hop" in anim_name_lower):
				if best_match == "":
					best_match = a
					
		if best_match != "":
			if anim_player.current_animation != best_match:
				anim_player.play(best_match)
				var anim := anim_player.get_animation(best_match)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
			return
			
		# No keyword match — play whatever animation exists
		if anims.size() > 0:
			var fallback = anims[0]
			if anim_player.current_animation != fallback:
				anim_player.play(fallback)
				var anim := anim_player.get_animation(fallback)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
		return  # Always stop here if AnimationPlayer exists

	# ── Programmatic Fallback (only when NO AnimationPlayer) ─────────────────
	if _visual:
		var current_keyword = _visual.get_meta("_tween_keyword", "")
		if current_keyword == keyword:
			return  # Already playing the right tween, don't restart it
		_visual.set_meta("_tween_keyword", keyword)
		
		if not _visual.has_meta("_base_scale"):
			_visual.set_meta("_base_scale", _visual.scale)
		var base_scale: Vector3 = _visual.get_meta("_base_scale", _visual.scale)
		
		if _anim_tween and _anim_tween.is_valid():
			_anim_tween.kill()
		_anim_tween = create_tween()
		
		if keyword.to_lower() == "idle":
			# Subtle breathing + look around
			_anim_tween.set_loops()
			_anim_tween.tween_property(_visual, "scale", base_scale * Vector3(1.03, 0.97, 1.03), 1.5).set_trans(Tween.TRANS_SINE)
			_anim_tween.tween_property(_visual, "scale", base_scale, 1.5).set_trans(Tween.TRANS_SINE)
			if randf() < 0.4:
				var look_angle = 0.4 if randf() < 0.5 else -0.4
				_anim_tween.parallel().tween_property(_visual, "rotation:y", look_angle, 0.4)
				_anim_tween.tween_property(_visual, "rotation:y", 0.0, 0.4).set_delay(1.2)
		else:
			# Moving: just reset to neutral, let movement speak for itself
			_visual.scale = base_scale
			_visual.rotation = Vector3.ZERO

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

func _pick_wander_direction() -> void:
	var chosen_dir := Vector3.ZERO
	for _i in range(5):
		var angle := randf() * TAU
		var candidate := Vector3(cos(angle), 0.0, sin(angle))
		if last_failed_direction.length() > 0.1 and candidate.dot(last_failed_direction) > 0.8:
			continue
		if _is_tile_ok_ahead(candidate):
			chosen_dir = candidate
			break

	if chosen_dir == Vector3.ZERO:
		chosen_dir = -wander_direction if wander_direction.length() > 0.1 else Vector3(1.0, 0.0, 0.0)

	wander_direction = chosen_dir
	target_rotation_y = atan2(wander_direction.x, wander_direction.z)

func _pick_new_state() -> void:
	var roll := randf()
	if roll < 0.40:
		# IDLE: stand still, breath/look around with loop animation
		current_state = State.IDLE
		state_timer = randf_range(2.5, 5.5)
		velocity = Vector3.ZERO
	elif roll < 0.75:
		# WALK: casual wandering
		current_state = State.WALK
		state_timer = randf_range(3.0, 6.5)
		current_speed = walk_speed
		_pick_wander_direction()
	else:
		# RUN: running sprint
		current_state = State.RUN
		state_timer = randf_range(2.0, 4.5)
		current_speed = run_speed
		_pick_wander_direction()

# ─── Physics ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		_pick_new_state()

	var is_in_water := global_position.y <= 0.0

	if current_state == State.WALK or current_state == State.RUN:
		velocity.x = wander_direction.x * current_speed
		velocity.z = wander_direction.z * current_speed

		if is_water_animal:
			if not is_in_water:
				last_failed_direction = wander_direction
				wander_direction *= -1.0
				velocity.x = wander_direction.x * current_speed
				velocity.z = wander_direction.z * current_speed
				target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			else:
				velocity.y = sin(Time.get_ticks_msec() * 0.002) * 0.5
		else:
			if is_in_water:
				last_failed_direction = wander_direction
				wander_direction *= -1.0
				velocity.x = wander_direction.x * current_speed
				velocity.z = wander_direction.z * current_speed
				target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			else:
				if not is_on_floor():
					velocity.y -= 9.8 * delta
	else:
		# IDLE state
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
		if not is_water_animal and not is_on_floor():
			velocity.y -= 9.8 * delta
		elif is_water_animal:
			velocity.y = move_toward(velocity.y, 0.0, walk_speed * delta)

	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * TURN_SPEED)

	# Animation selection based on state
	match current_state:
		State.IDLE:
			if anim_player:
				anim_player.speed_scale = 1.0
			_play_anim("idle")
		State.WALK:
			if anim_player:
				anim_player.speed_scale = 1.0
			_play_anim(move_anim if move_anim != "" else "walk")
		State.RUN:
			if anim_player:
				anim_player.speed_scale = 1.0
			_play_anim("run")

	move_and_slide()
