class_name CameraScaler
extends Node

# ─── Reference Design Resolution ─────────────────────────────────────────────
# This is the screen height the camera size was designed for.
# camera.size = 38 looked correct at 1080p height.
# On any other screen height it will be scaled proportionally.
const REFERENCE_HEIGHT: float = 1080.0
var base_camera_size: float = 38.0   # World units visible at REFERENCE_HEIGHT

# ─── State ────────────────────────────────────────────────────────────────────
var _camera: Camera3D = null

func zoom(delta_amount: float) -> void:
	base_camera_size += delta_amount
	base_camera_size = clampf(base_camera_size, 10.0, 100.0) # Prevent zooming too far in or out
	_apply_scale()

func setup(camera: Camera3D) -> void:
	_camera = camera
	# Connect to viewport resize signal
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	# Apply immediately for the current screen size
	_apply_scale()

# ─── Core Scale Logic ─────────────────────────────────────────────────────────
#
# Orthographic camera.size = vertical world units visible on screen.
# To keep the same "zoom level" feel at any resolution:
#
#   camera.size = BASE_CAMERA_SIZE * (REFERENCE_HEIGHT / current_height)
#
# Examples:
#   1080p  → 38 * (1080/1080) = 38.0   ← original design
#   720p   → 38 * (1080/720)  = 57.0   ← fewer pixels, show fewer world units (zoom in)
#   1440p  → 38 * (1080/1440) = 28.5   ← more pixels, show more world units (zoom out)
#   4K     → 38 * (1080/2160) = 19.0   ← 4K display, crisp and zoomed out

func _apply_scale() -> void:
	if _camera == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return

	# Scale based on height — keeps the world-unit density consistent per pixel
	var scale_factor: float = REFERENCE_HEIGHT / viewport_size.y
	_camera.size = base_camera_size * scale_factor

func _on_viewport_size_changed() -> void:
	_apply_scale()
