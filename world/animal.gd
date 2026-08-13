extends CharacterBody3D
class_name Animal

enum State { IDLE, WANDER }

var current_state: State = State.IDLE
var state_timer: float = 0.0
var wander_direction: Vector3 = Vector3.ZERO
var speed: float = 2.0
var is_water_animal: bool = false

var anim_player: AnimationPlayer

func _ready():
	anim_player = _find_anim_player(self)
	
	# Create a simple collision shape so we can stand on the ground
	var coll_shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 0.5
	coll_shape.shape = sphere
	coll_shape.position = Vector3(0, 0.5, 0)
	add_child(coll_shape)
	
	_pick_new_state()

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var ap = _find_anim_player(child)
		if ap: return ap
	return null

func _play_anim(keyword: String, fallback_keyword: String = ""):
	if not anim_player: return
	var anims = anim_player.get_animation_list()
	if anims.size() == 0: return
	
	# Try primary keyword
	for a in anims:
		if keyword.to_lower() in a.to_lower():
			anim_player.play(a)
			return
			
	# Try fallback
	if fallback_keyword != "":
		for a in anims:
			if fallback_keyword.to_lower() in a.to_lower():
				anim_player.play(a)
				return
				
	# Just play anything if we couldn't match (preferably not T-pose)
	anim_player.play(anims[0])

func _pick_new_state():
	if randf() < 0.5:
		current_state = State.IDLE
		state_timer = randf_range(2.0, 5.0)
		velocity = Vector3.ZERO
		_play_anim("Idle")
	else:
		current_state = State.WANDER
		state_timer = randf_range(3.0, 6.0)
		var angle = randf() * TAU
		wander_direction = Vector3(cos(angle), 0, sin(angle))
		
		# Rotate mesh towards target direction
		var look_target = global_position + wander_direction
		if global_position.distance_to(look_target) > 0.1:
			look_at(look_target, Vector3.UP)
			
		_play_anim("Walk", "Swim")

func _physics_process(delta):
	state_timer -= delta
	if state_timer <= 0:
		_pick_new_state()
		
	var is_in_water = global_position.y <= 0.0
	
	if current_state == State.WANDER:
		velocity.x = wander_direction.x * speed
		velocity.z = wander_direction.z * speed
		
		if is_water_animal:
			# Water animals bounce off terrain
			if not is_in_water:
				wander_direction *= -1.0
				velocity.x = wander_direction.x * speed
				velocity.z = wander_direction.z * speed
				var look_target = global_position + wander_direction
				if global_position.distance_to(look_target) > 0.1:
					look_at(look_target, Vector3.UP)
			else:
				# Slight vertical swimming
				velocity.y = sin(Time.get_ticks_msec() * 0.002) * 0.5
		else:
			# Land animals avoid water
			if is_in_water:
				wander_direction *= -1.0
				velocity.x = wander_direction.x * speed
				velocity.z = wander_direction.z * speed
				var look_target = global_position + wander_direction
				if global_position.distance_to(look_target) > 0.1:
					look_at(look_target, Vector3.UP)
			else:
				# Apply gravity for land animals
				if not is_on_floor():
					velocity.y -= 9.8 * delta
	else:
		# Idle
		velocity.x = move_toward(velocity.x, 0, speed * delta)
		velocity.z = move_toward(velocity.z, 0, speed * delta)
		if not is_water_animal and not is_on_floor():
			velocity.y -= 9.8 * delta
		elif is_water_animal:
			velocity.y = move_toward(velocity.y, 0, speed * delta)

	move_and_slide()
