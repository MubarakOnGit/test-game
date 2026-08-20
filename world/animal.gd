extends CharacterBody3D
class_name Animal

# ─── Tuning ───────────────────────────────────────────────────────────────────
const MAX_STEP_HEIGHT := 1.2   # Max height delta between tiles before rejecting direction
const TURN_SPEED      := 3.0   # Radians/sec for smooth rotation lerp

# ─── Per-animal Config ────────────────────────────────────────────────────────
@export var animal_type: String = "" # e.g., "blocky_rabbit" or "wolf"
@export var move_anim: String = "walk"  # Override per animal type (e.g. "run" for rabbit)

# ─── AI Stats ─────────────────────────────────────────────────────────────────
var hunger: float = 100.0
var max_hunger: float = 100.0
var hunger_decay_rate: float = 2.0 # Hunger lost per second

# ─── State ────────────────────────────────────────────────────────────────────
enum State { IDLE, WALK, RUN, FLEE, SEEK_FOOD, EAT, ATTACK }

var current_state: State = State.IDLE
var state_timer: float = 0.0
var _think_timer: float = 0.0

var wander_direction: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO # For SEEK_FOOD / EAT
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
var _chunk_manager = null # Assigned dynamically in _ready

# ─── Crocodile-specific state ─────────────────────────────────────────────────
var _land_chase_timer: float = 0.0  # How long croc has been chasing on land
var _water_return_pos: Vector3 = Vector3.ZERO  # Last known water position to return to
var _is_retreating_to_water: bool = false # Cooldown flag to prevent re-targeting during retreat
const MAX_LAND_CHASE_TIME := 1.5  # Seconds croc will pursue on land before giving up

# ─── Deep River Ambush State ──────────────────────────────────────────────────
enum AmbushPhase { NONE, STALK, LUNGE, RETREAT, DIVE }
var is_ambush_croc: bool = false
var ambush_target: Node3D = null
var ambush_phase: AmbushPhase = AmbushPhase.NONE
var _ambush_timer: float = 0.0
var _ambush_has_bitten: bool = false
var _ambush_retreat_dir: Vector3 = Vector3.ZERO
var _ripple_timer: float = 0.0

# ─── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	anim_player = _find_anim_player(self)

	var coll_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.65
	coll_shape.shape = sphere
	coll_shape.position = Vector3(0, 0.65, 0)
	add_child(coll_shape)
	
	# Prevent sinking at terrain tile step edges (not river dips)
	floor_snap_length = 0.2
	floor_max_angle   = deg_to_rad(50.0)
	safe_margin       = 0.02
	
	_ahead_ray = RayCast3D.new()
	_ahead_ray.target_position = Vector3(0, -20, 0)
	add_child(_ahead_ray)

	for child in get_children():
		if child is Node3D and not child is CollisionShape3D and not child is RayCast3D and not child is AnimationPlayer:
			_visual = child
			break
			
	_chunk_manager = get_tree().get_first_node_in_group("chunk_manager")

	# Per-species speed tuning
	if animal_type == "crocodile":
		walk_speed = 0.6   # Very slow — ambush predator, conserves energy
		run_speed  = 2.5   # Fast lunge when attacking
		current_speed = walk_speed
	elif animal_type == "wolf":
		# Add $\pm 10\%$ speed jitter so wolves stride dynamically
		var jitter = randf_range(0.9, 1.1)
		walk_speed = 2.5 * jitter
		run_speed  = 5.5 * jitter
		current_speed = walk_speed
	elif "rabbit" in animal_type:
		walk_speed = 2.2
		run_speed  = 5.0
		current_speed = walk_speed

	target_rotation_y = rotation.y
	_pick_new_state()

	# Debug: confirm what was found
	if anim_player:
		print("[Animal] AnimationPlayer found on: ", name, " | Anims: ", anim_player.get_animation_list())
	else:
		print("[Animal] NO AnimationPlayer found on: ", name, " — using Tween fallback")
		
	if animal_type == "wolf":
		add_to_group("predators")
		
	# Fix imported materials that might be glowing/unshaded (especially crocodile)
	_fix_materials(self)

func _fix_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh = node.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				var mat = mesh.surface_get_material(i)
				if mat is StandardMaterial3D or mat is ORMMaterial3D:
					# If the model was relying on emission for its base color, copy it to albedo first
					if mat.emission_enabled:
						if mat.albedo_color == Color(0, 0, 0, 1) or mat.albedo_color == Color(1, 1, 1, 1):
							mat.albedo_color = mat.emission
						if mat.albedo_texture == null and mat.emission_texture != null:
							mat.albedo_texture = mat.emission_texture
							
					# Force material to respond to light properly
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					mat.emission_enabled = false
					
	for child in node.get_children():
		_fix_materials(child)

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
		
		if animal_type == "crocodile":
			_anim_tween.set_loops()
			if keyword.to_lower() == "idle":
				_anim_tween.tween_property(_visual, "scale", base_scale * Vector3(1.02, 0.98, 1.02), 2.0).set_trans(Tween.TRANS_SINE)
				_anim_tween.tween_property(_visual, "scale", base_scale, 2.0).set_trans(Tween.TRANS_SINE)
			elif keyword.to_lower() == "walk" or keyword.to_lower() == "run":
				# Wobble side to side
				_anim_tween.tween_property(_visual, "rotation:z", 0.1, 0.3).set_trans(Tween.TRANS_SINE)
				_anim_tween.tween_property(_visual, "rotation:z", -0.1, 0.3).set_trans(Tween.TRANS_SINE)
			elif keyword.to_lower() == "swim":
				# Slither side to side in water
				_anim_tween.tween_property(_visual, "rotation:y", 0.2, 0.4).set_trans(Tween.TRANS_SINE)
				_anim_tween.tween_property(_visual, "rotation:y", -0.2, 0.4).set_trans(Tween.TRANS_SINE)
			elif keyword.to_lower() == "attack":
				_anim_tween.set_loops(0) # Not looping
				_visual.position.z = 0
				_anim_tween.tween_property(_visual, "position:z", -0.8, 0.1).set_trans(Tween.TRANS_EXPO) # Lunge forward
				_anim_tween.tween_property(_visual, "position:z", 0.0, 0.4).set_trans(Tween.TRANS_SINE)  # Return
		else:
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
				_visual.position = Vector3.ZERO

# ─── Tile Look-Ahead & Shore Navigation ──────────────────────────────────────

func _is_tile_ok_ahead(direction: Vector3) -> bool:
	# Cast from high up, 2 units ahead
	_ahead_ray.global_position = global_position + Vector3(0, 5, 0) + direction * 2.0
	_ahead_ray.force_raycast_update()
	
	if _ahead_ray.is_colliding():
		var hit_y = _ahead_ray.get_collision_point().y
		# Land animals strictly avoid walking into water during regular wander
		if not is_water_animal and hit_y <= 0.3:
			return false
		if absf(hit_y - global_position.y) > MAX_STEP_HEIGHT:
			return false
		return true
	return false

func _find_nearest_shore() -> Vector3:
	var best_pos := Vector3.ZERO
	var min_dist := 999.0
	# Cast rays in 8 directions across increasing radii (3m, 6m, 10m, 16m)
	for dist in [3.0, 6.0, 10.0, 16.0]:
		for i in range(8):
			var angle = float(i) * (TAU / 8.0)
			var check_pos = global_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
			_ahead_ray.global_position = check_pos + Vector3(0, 8, 0)
			_ahead_ray.force_raycast_update()
			if _ahead_ray.is_colliding():
				var hit = _ahead_ray.get_collision_point()
				if hit.y > 0.4: # Above sea level = dry land
					var d = global_position.distance_to(hit)
					if d < min_dist:
						min_dist = d
						best_pos = hit
		if best_pos != Vector3.ZERO:
			break
	return best_pos

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

func take_damage() -> void:
	queue_free()

func _process(delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	var dist_to_player = 0.0
	if player:
		dist_to_player = global_position.distance_to(player.global_position)
		
	if dist_to_player > 55.0:
		# Tier 3 (Distant): Sleeping state
		if is_physics_processing():
			set_physics_process(false)
			if _visual: _visual.hide()
		return
	elif not is_physics_processing():
		# Wake up
		set_physics_process(true)
		if _visual: _visual.show()
		
	var think_interval_min = 0.4
	var think_interval_max = 0.8
	if dist_to_player > 25.0:
		# Tier 2 (Perimeter): Throttled AI ticks
		think_interval_min = 1.2
		think_interval_max = 1.8
		
	hunger = maxf(0.0, hunger - hunger_decay_rate * delta)
	
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = randf_range(think_interval_min, think_interval_max)
		_think()
	state_timer -= delta
	if state_timer <= 0.0 and current_state in [State.IDLE, State.WALK, State.RUN]:
		_pick_new_state()

	var is_in_water := global_position.y <= 0.5
	
	if is_in_water:
		if not is_in_group("water_prey"):
			add_to_group("water_prey")
	else:
		if is_in_group("water_prey"):
			remove_from_group("water_prey")

	if animal_type == "crocodile":
		if is_in_water:
			if _is_retreating_to_water:
				_is_retreating_to_water = false
				_pick_new_state()
			_water_return_pos = global_position
			_land_chase_timer = 0.0
		else:
			_land_chase_timer += delta
			var dist_from_water = global_position.distance_to(_water_return_pos)
			if _land_chase_timer > MAX_LAND_CHASE_TIME or dist_from_water > 6.0:
				_land_chase_timer = 0.0
				_is_retreating_to_water = true
				current_state = State.WALK
				if _water_return_pos != Vector3.ZERO:
					wander_direction = (_water_return_pos - global_position)
					wander_direction.y = 0
					wander_direction = wander_direction.normalized()
					target_rotation_y = atan2(wander_direction.x, wander_direction.z)
					state_timer = 6.0

	# ─── Ambush Crocodile Lifecycle ───────────────────────────────────────────
	if is_ambush_croc:
		_handle_ambush_croc_physics(delta)
		return

	# ─── Standard Movement ───────────────────────────────────────────────────
	if current_state in [State.WALK, State.RUN, State.FLEE, State.SEEK_FOOD, State.ATTACK]:
		if current_state in [State.SEEK_FOOD, State.FLEE, State.ATTACK] or (not is_water_animal and is_in_water):
			var diff := target_position - global_position
			diff.y = 0
			if diff.length_squared() > 0.01:
				wander_direction = diff.normalized()
				if current_state == State.FLEE and not is_in_water:
					wander_direction = -wander_direction
			target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			
		velocity.x = wander_direction.x * current_speed
		velocity.z = wander_direction.z * current_speed

		if is_water_animal:
			var is_land_charging := animal_type == "crocodile" and \
				current_state in [State.SEEK_FOOD, State.ATTACK]
				
			if not is_in_water:
				if is_land_charging:
					# On land charge — grounded movement with gravity
					if not is_on_floor():
						velocity.y -= 9.8 * delta
					elif is_on_wall() and is_on_floor():
						# Controlled step jump up small ledges
						velocity.y = 3.5
				else:
					# Bounce back into water
					last_failed_direction = wander_direction
					wander_direction *= -1.0
					velocity.x = wander_direction.x * current_speed
					velocity.z = wander_direction.z * current_speed
					target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			else:
				# In water — smoothly float at water level (y = -0.5) without flying
				var target_y := -0.5
				velocity.y = (target_y - global_position.y) * 4.0
		else:
			if is_in_water:
				# Float submerged
				velocity.y = (-0.4 - global_position.y) * 4.0
				
				# If we hit the riverbank wall while swimming, hop up onto the dry land!
				if is_on_wall():
					velocity.y = 5.5
					
				# Fast swim toward shore
				velocity.x = wander_direction.x * current_speed
				velocity.z = wander_direction.z * current_speed
				target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			else:
				if not is_on_floor():
					velocity.y -= 9.8 * delta
				elif is_on_wall() and is_on_floor():
					velocity.y = 4.5
					if randf() < 0.02:
						_think_timer = -1.0
						last_failed_direction = wander_direction
	else:
		# IDLE or EAT state
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
		if not is_water_animal:
			if is_in_water:
				velocity.y = (-0.4 - global_position.y) * 4.0
			elif not is_on_floor():
				velocity.y -= 9.8 * delta
		elif is_water_animal:
			if is_in_water:
				velocity.y = (-0.5 - global_position.y) * 4.0
			elif not is_on_floor():
				velocity.y -= 9.8 * delta

	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * TURN_SPEED)

	match current_state:
		State.IDLE, State.EAT:
			if anim_player:
				anim_player.speed_scale = 1.0
			_play_anim("idle")
		State.WALK:
			if anim_player:
				anim_player.speed_scale = 1.0
			if animal_type == "crocodile":
				_play_anim("walk" if not is_in_water else "swim")
			else:
				_play_anim("swim" if is_in_water else (move_anim if move_anim != "" else "walk"))
		State.RUN, State.FLEE, State.SEEK_FOOD, State.ATTACK:
			if anim_player:
				anim_player.speed_scale = 1.5
			_play_anim("swim" if is_in_water else "run")

	move_and_slide()

func _handle_ambush_croc_physics(delta: float) -> void:
	_ambush_timer += delta
	_ripple_timer += delta
	
	match ambush_phase:
		AmbushPhase.STALK:
			if not is_instance_valid(ambush_target):
				ambush_phase = AmbushPhase.RETREAT
				_ambush_timer = 0.0
				_ambush_retreat_dir = -wander_direction if wander_direction.length_squared() > 0.01 else Vector3.FORWARD
				return
				
			var diff := ambush_target.global_position - global_position
			diff.y = 0
			var dist = diff.length()
			if dist > 0.1:
				wander_direction = diff.normalized()
				target_rotation_y = atan2(wander_direction.x, wander_direction.z)
				
			# Smooth ascent from depths based on distance to prey
			var target_y := -0.45
			if dist > 10.0:
				target_y = -1.2 # Deep approach
				if _ripple_timer > 1.2:
					_ripple_timer = 0.0
					WorldEventBus.water_ripple_spawned.emit(Vector3(global_position.x, -0.1, global_position.z), 1.2, 0.4, 0.4, 2.0)
			else:
				target_y = -0.40 # Surface swim
				if _ripple_timer > 0.45:
					_ripple_timer = 0.0
					WorldEventBus.water_ripple_spawned.emit(Vector3(global_position.x, -0.1, global_position.z), 1.0, 0.7, 0.8, 3.0)
					
			velocity.y = (target_y - global_position.y) * 4.0
			
			current_speed = 5.2 # Ominous pursuit speed (gives player 2.5-3.5s to reach shore!)
			velocity.x = wander_direction.x * current_speed
			velocity.z = wander_direction.z * current_speed
			_play_anim("swim")
			
			# Dynamic scale & pitch (emerging from deep murky water)
			if _visual:
				var target_scale = Vector3(1.3, 1.3, 1.3)
				var depth_ratio = clampf((global_position.y - (-2.5)) / 1.7, 0.05, 1.0)
				_visual.scale = target_scale * depth_ratio
				var pitch_target = deg_to_rad(15.0) if global_position.y < -0.6 else 0.0
				_visual.rotation.x = lerp_angle(_visual.rotation.x, pitch_target, delta * 3.0)
			
			# Check if target escaped onto dry land!
			var target_in_water := ambush_target.global_position.y <= 0.5 and ambush_target.is_in_group("water_prey")
			if not target_in_water and dist < 5.0:
				# Prey escaped to dry shore! Lunge once at bank and retreat
				ambush_phase = AmbushPhase.LUNGE
				_ambush_timer = 0.0
				_ambush_has_bitten = true # Don't bite escaped prey
				_ambush_retreat_dir = -wander_direction
				_play_anim("attack")
				return
				
			# Strike if in range
			if dist < 2.2 and target_in_water:
				ambush_phase = AmbushPhase.LUNGE
				_ambush_timer = 0.0
				_play_anim("attack")
				
			# Safety: if chasing too long (> 8.0s), turn around
			if _ambush_timer > 8.0:
				ambush_phase = AmbushPhase.RETREAT
				_ambush_timer = 0.0
				_ambush_retreat_dir = -wander_direction
				
		AmbushPhase.LUNGE:
			# Jaw snap / thrash at water surface
			velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)
			velocity.y = (-0.35 - global_position.y) * 4.0
			
			if _visual:
				_visual.scale = Vector3(1.3, 1.3, 1.3)
				_visual.rotation.x = lerp_angle(_visual.rotation.x, 0.0, delta * 6.0)
			
			if not _ambush_has_bitten and is_instance_valid(ambush_target):
				var target_in_water := ambush_target.global_position.y <= 0.5 and ambush_target.is_in_group("water_prey")
				if target_in_water and global_position.distance_to(ambush_target.global_position) < 3.0:
					_ambush_has_bitten = true
					WorldEventBus.water_ripple_spawned.emit(global_position, 2.0, 1.2, 1.2, 4.5)
					if ambush_target.has_method("take_damage"):
						ambush_target.take_damage()
					elif not ambush_target.is_in_group("player"):
						ambush_target.queue_free()
				else:
					_ambush_has_bitten = true # Missed / escaped onto shore!
					
			if _ambush_timer > 1.2:
				ambush_phase = AmbushPhase.RETREAT
				_ambush_timer = 0.0
				if _ambush_retreat_dir == Vector3.ZERO:
					_ambush_retreat_dir = -wander_direction if wander_direction.length_squared() > 0.01 else Vector3.FORWARD
					
		AmbushPhase.RETREAT:
			# Turn around smoothly and swim back toward open water / river channel
			target_rotation_y = atan2(_ambush_retreat_dir.x, _ambush_retreat_dir.z)
			current_speed = 3.5
			velocity.x = _ambush_retreat_dir.x * current_speed
			velocity.z = _ambush_retreat_dir.z * current_speed
			
			# Gradually slope downward
			var target_y := -0.4 - (_ambush_timer * 0.7)
			velocity.y = (target_y - global_position.y) * 3.0
			_play_anim("swim")
			
			if _visual:
				var target_scale = Vector3(1.3, 1.3, 1.3)
				if global_position.y < -0.8:
					var depth_ratio = clampf(1.0 - ((-0.8 - global_position.y) / 1.8), 0.05, 1.0)
					_visual.scale = target_scale * depth_ratio
				_visual.rotation.x = lerp_angle(_visual.rotation.x, deg_to_rad(-18.0), delta * 2.5)
			
			if _ripple_timer > 0.8:
				_ripple_timer = 0.0
				WorldEventBus.water_ripple_spawned.emit(Vector3(global_position.x, -0.1, global_position.z), 1.0, 0.4, 0.4, 2.0)
				
			if _ambush_timer > 2.5 or global_position.y < -1.8:
				ambush_phase = AmbushPhase.DIVE
				_ambush_timer = 0.0
				
		AmbushPhase.DIVE:
			# Deep dive into the abyss before despawning
			velocity.x = _ambush_retreat_dir.x * 2.0
			velocity.z = _ambush_retreat_dir.z * 2.0
			velocity.y = -2.5 # Dive deep under riverbed
			_play_anim("swim")
			
			if _visual:
				var depth_ratio = clampf(1.0 - ((-0.8 - global_position.y) / 2.0), 0.01, 1.0)
				_visual.scale = Vector3(1.3, 1.3, 1.3) * depth_ratio
				_visual.rotation.x = lerp_angle(_visual.rotation.x, deg_to_rad(-25.0), delta * 2.5)
			
			if global_position.y <= -3.0 or _ambush_timer > 3.0:
				queue_free()
				return
				
	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * TURN_SPEED)
	move_and_slide()


func _think() -> void:
	if not _chunk_manager or is_ambush_croc:
		return
		
	# ─── Land Animal Emergency Water Escape ────────────────────────────────────
	if not is_water_animal and global_position.y <= 0.5:
		var shore := _find_nearest_shore()
		if shore != Vector3.ZERO:
			current_state = State.RUN
			current_speed = run_speed * 1.2
			target_position = shore
			return
		
	if animal_type == "blocky_rabbit":
		var predators = get_tree().get_nodes_in_group("predators")
		var closest_predator: Node3D = null
		var min_dist := 15.0
		
		for p in predators:
			if p == self: continue
			var d = global_position.distance_to(p.global_position)
			if d < min_dist:
				min_dist = d
				closest_predator = p
				
		if closest_predator:
			current_state = State.FLEE
			current_speed = run_speed
			target_position = closest_predator.global_position
			return
			
		if hunger < 50.0:
			var food = _chunk_manager.find_nearest_food(global_position, 20.0)
			if food:
				var dist = global_position.distance_to(food.position)
				if dist < 1.5:
					_chunk_manager.consume_food(food)
					hunger = max_hunger
					current_state = State.EAT
					state_timer = 2.0
				else:
					current_state = State.SEEK_FOOD
					current_speed = run_speed
					target_position = food.position
				return
				
	elif animal_type == "wolf":
		var target: Node3D = null
		
		# 1. Target player if too close (Aggressive)
		var player = get_tree().get_first_node_in_group("player")
		if player and global_position.distance_to(player.global_position) < 12.0:
			target = player
			
		# 2. Target rabbit if hungry
		if not target and hunger < 70.0:
			var rabbit = _chunk_manager.find_nearest_animal(global_position, 25.0, "blocky_rabbit")
			if rabbit:
				target = rabbit
				
		if target:
			var dist = global_position.distance_to(target.global_position)
			
			# Alert the pack!
			var pack_members = _chunk_manager.find_all_animals_in_radius(global_position, 15.0, "wolf")
			for wolf in pack_members:
				if wolf != self and wolf.current_state != State.ATTACK and wolf.current_state != State.EAT:
					wolf.current_state = State.SEEK_FOOD
					wolf.target_position = target.global_position
					# Add a tiny delay so they don't all snap perfectly simultaneously
					wolf._think_timer = randf_range(0.2, 0.5) 
			
			if dist < 1.8:
				if target.has_method("take_damage"):
					target.take_damage()
				elif not target.is_in_group("player"):
					target.queue_free()
				hunger = max_hunger
				current_state = State.EAT
				state_timer = 3.0
			else:
				current_state = State.SEEK_FOOD
				current_speed = run_speed * 1.1
				
				# Flanking Target Force: Add an angular offset based on our instance ID so we surround prey
				var flank_angle = float(get_instance_id() % 3 - 1) * (PI / 4.0) # -45, 0, or +45 degrees
				var diff = target.global_position - global_position
				var rotated_diff = diff.rotated(Vector3.UP, flank_angle)
				target_position = global_position + rotated_diff
			return
			
		# 3. Emergent Flocking (Boids: Cohesion + Separation)
		if not target:
			var pack_members = _chunk_manager.find_all_animals_in_radius(global_position, 20.0, "wolf")
			var center_of_mass = Vector3.ZERO
			var separation_vec = Vector3.ZERO
			var neighbor_count = 0
			
			for wolf in pack_members:
				if wolf == self: continue
				var d = global_position.distance_to(wolf.global_position)
				center_of_mass += wolf.global_position
				neighbor_count += 1
				
				# Separation force (push away if < 1.8m)
				if d < 1.8 and d > 0.1:
					var push = (global_position - wolf.global_position).normalized() / d
					separation_vec += push
					
			if neighbor_count > 0:
				center_of_mass /= float(neighbor_count)
				
				var target_vec = Vector3.ZERO
				var d_center = global_position.distance_to(center_of_mass)
				
				# Cohesion force (pull toward center if > 4.5m)
				if d_center > 4.5:
					target_vec += (center_of_mass - global_position).normalized() * 0.5
					
				# Apply separation heavily
				target_vec += separation_vec * 1.5
				
				# If we need to steer, wander in that direction
				if target_vec.length_squared() > 0.1:
					current_state = State.WALK
					current_speed = walk_speed
					target_position = global_position + target_vec.normalized() * 3.0
					return

	elif animal_type == "crocodile":
		if _is_retreating_to_water:
			return # Ignore prey until we reach the water!
			
		# ── Crocodile AI: Ambush predator ─────────────────────────────────────
		var croc_in_water := global_position.y <= 0.5
		var target: Node3D = null
		
		# Iterate over the global water_prey registry instead of chunk searching.
		# This guarantees we never miss a valid target.
		var potential_targets = get_tree().get_nodes_in_group("water_prey")
		
		var best_player: Node3D = null
		var best_wolf: Node3D = null
		var best_rabbit: Node3D = null
		
		var min_dist_player := 25.0
		var min_dist_wolf := 25.0
		var min_dist_rabbit := 25.0
		
		for p in potential_targets:
			# Skip self
			if p == self:
				continue
				
			var dist = global_position.distance_to(p.global_position)
			if dist > 25.0:
				continue
				
			# On land chase, allow targeting slightly higher up the beach (y<=3.0).
			# In water, only target things in water or just on the edge (y<=1.0).
			var max_y = 1.0 if croc_in_water else 3.0
			if p.global_position.y > max_y:
				continue
				
			if p.is_in_group("player") and dist < min_dist_player:
				min_dist_player = dist
				best_player = p
			elif p is Animal and p.animal_type == "wolf" and dist < min_dist_wolf:
				min_dist_wolf = dist
				best_wolf = p
			elif p is Animal and p.animal_type == "blocky_rabbit" and dist < min_dist_rabbit:
				min_dist_rabbit = dist
				best_rabbit = p
				
		# Assign target based on priority
		if best_player:
			target = best_player
		elif best_wolf:
			target = best_wolf
		elif best_rabbit:
			target = best_rabbit
			
		if target:
			var dist := global_position.distance_to(target.global_position)
			if dist < 4.0 and current_state != State.ATTACK:
				# Lunge and bite!
				current_state = State.ATTACK
				current_speed = run_speed * 3.5  # Fast lunge!
				target_position = target.global_position
				state_timer = 2.0
				_play_anim("attack")
				
				# Eat the animal (player survives for now)
				if target.has_method("take_damage"):
					target.take_damage()
				elif not target.is_in_group("player"):
					target.queue_free()
				hunger = max_hunger
				return
			elif dist < 25.0 and dist >= 4.0:
				# Pursue prey (swim fast!)
				current_state = State.SEEK_FOOD
				current_speed = run_speed * 2.0
				target_position = target.global_position
				return
				
		# Prey escaped or none found, go back to normal
		if current_state == State.ATTACK or current_state == State.SEEK_FOOD:
			_pick_new_state()
			return

	if current_state in [State.FLEE, State.SEEK_FOOD, State.ATTACK]:
		_pick_new_state()
