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
		walk_speed = 2.5
		run_speed  = 5.5
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

# ─── Tile Look-Ahead ──────────────────────────────────────────────────────────

func _is_tile_ok_ahead(direction: Vector3) -> bool:
	# Cast from high up, 2 units ahead
	_ahead_ray.global_position = global_position + Vector3(0, 5, 0) + direction * 2.0
	_ahead_ray.force_raycast_update()
	
	if _ahead_ray.is_colliding():
		var hit_y = _ahead_ray.get_collision_point().y
		if not is_water_animal and hit_y <= 0.0:
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
	hunger = maxf(0.0, hunger - hunger_decay_rate * delta)
	
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = randf_range(0.4, 0.8)
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
				# We made it back to the water! Force an immediate rethink so we don't 
				# keep blindly walking forward (which causes sliding into the opposite shore).
				_is_retreating_to_water = false
				_pick_new_state()
				
			# Remember last water position so we can return here if chase fails
			_water_return_pos = global_position
			_land_chase_timer = 0.0
		else:
			_land_chase_timer += delta
			var dist_from_water = global_position.distance_to(_water_return_pos)
			
			# Gave up: turn around and walk back to water
			if _land_chase_timer > MAX_LAND_CHASE_TIME or dist_from_water > 6.0:
				_land_chase_timer = 0.0
				_is_retreating_to_water = true
				current_state = State.WALK
				if _water_return_pos != Vector3.ZERO:
					wander_direction = (_water_return_pos - global_position)
					wander_direction.y = 0
					wander_direction = wander_direction.normalized()
					target_rotation_y = atan2(wander_direction.x, wander_direction.z)
					state_timer = 6.0  # Walk toward water for 6s

	if current_state in [State.WALK, State.RUN, State.FLEE, State.SEEK_FOOD, State.ATTACK]:
		if current_state == State.SEEK_FOOD or current_state == State.FLEE or current_state == State.ATTACK:
			var diff := target_position - global_position
			diff.y = 0
			if diff.length_squared() > 0.01:
				wander_direction = diff.normalized()
				if current_state == State.FLEE:
					wander_direction = -wander_direction
			target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			
		velocity.x = wander_direction.x * current_speed
		velocity.z = wander_direction.z * current_speed

		if is_water_animal:
			var is_land_charging := animal_type == "crocodile" and \
				current_state in [State.SEEK_FOOD, State.ATTACK]
				
			if not is_in_water:
				if is_land_charging:
					# On a land charge — use normal land physics so croc can run on ground
					if not is_on_floor():
						velocity.y -= 9.8 * delta
					elif is_on_wall():
						# Jump to climb terrain steps
						velocity.y = 4.5
				else:
					# Not chasing: bounce back into water
					last_failed_direction = wander_direction
					wander_direction *= -1.0
					velocity.x = wander_direction.x * current_speed
					velocity.z = wander_direction.z * current_speed
					target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			else:
				# In water
				if is_land_charging and is_on_wall():
					# If charging prey and hitting the riverbank, leap out of the water!
					velocity.y = 5.0
				else:
					# Float submerged
					var target_y := -0.8
					velocity.y = (target_y - global_position.y) * 5.0
		else:
			if is_in_water:
				# Float submerged
				velocity.y = (-0.4 - global_position.y) * 4.0
				
				# If we just hit water, force a rethink occasionally to find land
				if randf() < 0.05:
					_think_timer = -1.0
					
				# Slow swim
				velocity.x = wander_direction.x * current_speed * 0.4
				velocity.z = wander_direction.z * current_speed * 0.4
				target_rotation_y = atan2(wander_direction.x, wander_direction.z)
			else:
				if not is_on_floor():
					velocity.y -= 9.8 * delta
				elif is_on_wall():
					if is_on_floor():
						# Jump to climb blocky terrain steps
						velocity.y = 4.5
					
					# If we've been trying to jump over a wall and keep hitting it (too tall), turn around
					if randf() < 0.02:
						_think_timer = -1.0
						last_failed_direction = wander_direction
	else:
		# IDLE or EAT state
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 4.0 * delta)
		if not is_water_animal:
			if is_in_water:
				# Float even when idle
				velocity.y = (-0.4 - global_position.y) * 4.0
			elif not is_on_floor():
				velocity.y -= 9.8 * delta
		elif is_water_animal:
			velocity.y = move_toward(velocity.y, 0.0, walk_speed * delta)

	rotation.y = lerp_angle(rotation.y, target_rotation_y, delta * TURN_SPEED)

	match current_state:
		State.IDLE, State.EAT:
			if anim_player:
				anim_player.speed_scale = 1.0
			_play_anim("idle")
		State.WALK:
			if anim_player:
				anim_player.speed_scale = 1.0
			# Crocodiles walk if wandering slowly, swim if moving fast
			if animal_type == "crocodile":
				_play_anim("walk")
			else:
				_play_anim("swim" if is_water_animal else (move_anim if move_anim != "" else "walk"))
		State.RUN, State.FLEE, State.SEEK_FOOD, State.ATTACK:
			if anim_player:
				anim_player.speed_scale = 1.5
			_play_anim("swim" if is_water_animal else "run")

	move_and_slide()

func _think() -> void:
	if not _chunk_manager:
		return
		
	if animal_type == "blocky_rabbit":
		var wolf = _chunk_manager.find_nearest_animal(global_position, 15.0, "wolf")
		if wolf:
			current_state = State.FLEE
			current_speed = run_speed * 1.2
			target_position = wolf.global_position
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
		if hunger < 70.0:
			var prey = _chunk_manager.find_nearest_animal(global_position, 25.0, "blocky_rabbit")
			if prey:
				var dist = global_position.distance_to(prey.global_position)
				if dist < 1.8:
					prey.queue_free()
					hunger = max_hunger
					current_state = State.EAT
					state_timer = 3.0
				else:
					current_state = State.SEEK_FOOD
					current_speed = run_speed * 1.1
					target_position = prey.global_position
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
				if not target.is_in_group("player"):
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
