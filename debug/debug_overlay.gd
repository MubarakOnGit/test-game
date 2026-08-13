class_name DebugOverlay
extends Control

var chunk_manager: ChunkManager
var _bounds_visible := false

func _ready() -> void:
	name = "DebugOverlay"
	
func setup(cm: ChunkManager) -> void:
	chunk_manager = cm

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_bounds_visible = not _bounds_visible
			queue_redraw()

func _process(delta: float) -> void:
	if _bounds_visible:
		queue_redraw()

func _draw() -> void:
	if not _bounds_visible or not chunk_manager:
		return
		
	# Draw simple 2D overlays for chunks if needed.
	# For actual 3D chunk bounds, we might want ImmediateMesh,
	# but for a simple 2D map/text overlay, this works.
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	for key in chunk_manager._active_nodes.keys():
		var node: ChunkNode = chunk_manager._active_nodes[key]
		var pos3d = node.position + Vector3(ChunkData.CHUNK_SIZE * ChunkData.TILE_SIZE * 0.5, 0, ChunkData.CHUNK_SIZE * ChunkData.TILE_SIZE * 0.5)
		if cam.is_position_behind(pos3d): continue
		
		var pos2d = cam.unproject_position(pos3d)
		draw_circle(pos2d, 5.0, Color.RED)
		var text = "Chunk %d, %d\nT_Ver: %d\nV_Ver: %d" % [
			key.x, key.y, 
			node.rendered_terrain_version, 
			node.rendered_vegetation_version
		]
		draw_string(ThemeDB.fallback_font, pos2d + Vector2(10, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
