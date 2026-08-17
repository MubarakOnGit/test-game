class_name DebugOverlay
extends Control

var chunk_manager: ChunkManager
var _bounds_visible := false

# Apple debug label
var _apple_label: Label

func _ready() -> void:
	name = "DebugOverlay"
	# Apple debug label — always visible
	_apple_label = Label.new()
	_apple_label.position = Vector2(16, 16)
	_apple_label.add_theme_font_size_override("font_size", 16)
	_apple_label.add_theme_color_override("font_color", Color(1, 1, 0.2))
	_apple_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_apple_label.add_theme_constant_override("shadow_offset_x", 2)
	_apple_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_apple_label)
	
func setup(cm: ChunkManager) -> void:
	chunk_manager = cm

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_bounds_visible = not _bounds_visible
			queue_redraw()

func _process(delta: float) -> void:
	# Count active apples and nearby apple trees across all chunks
	var active_apples := 0
	var apple_trees := 0
	if chunk_manager:
		for node: ChunkNode in chunk_manager._active_nodes.values():
			apple_trees += node.apple_tree_positions.size()
			for child in node.animals_container.get_children():
				if child is Apple:
					active_apples += 1
	_apple_label.text = "🍎 Apples Dropped: %d\n🌳 Apple Trees (loaded): %d\n🟡 Apples on ground: %d" % [
		ChunkNode.total_apples_dropped, apple_trees, active_apples
	]
	
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
