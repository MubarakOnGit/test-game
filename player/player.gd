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
