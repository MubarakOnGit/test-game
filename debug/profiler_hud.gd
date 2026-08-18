class_name ProfilerHUD
extends CanvasLayer

var profiler: Profiler
var database: WorldDatabase
var label: Label

# Day/Night controls
var day_night_cycle: DayNightCycle
var time_label: Label
var _paused: bool = false
var _base_day_length: float = 240.0  # matches DayNightCycle default

func _init(p: Profiler, db: WorldDatabase) -> void:
	profiler = p
	database = db
	
	name = "ProfilerHUD"
	layer = 100
	
	# ── Stats panel (top-left) ────────────────────────────────────────────────
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_left", 10)
	add_child(margin)
	
	var panel = PanelContainer.new()
	margin.add_child(panel)
	
	label = Label.new()
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	panel.add_child(label)
	
	# ── Day/Night controls panel (top-right) ─────────────────────────────────
	var ctrl_anchor = Control.new()
	ctrl_anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ctrl_anchor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(ctrl_anchor)
	
	var ctrl_margin = MarginContainer.new()
	ctrl_margin.add_theme_constant_override("margin_top", 10)
	ctrl_margin.add_theme_constant_override("margin_right", 10)
	ctrl_margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ctrl_margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ctrl_margin.grow_vertical   = Control.GROW_DIRECTION_END
	add_child(ctrl_margin)
	
	var ctrl_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	ctrl_panel.add_theme_stylebox_override("panel", style)
	ctrl_margin.add_child(ctrl_panel)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	ctrl_panel.add_child(vbox)
	
	# Large centered time of day label
	time_label = Label.new()
	time_label.text = "12:00"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var label_settings = LabelSettings.new()
	label_settings.font_size = 24
	time_label.label_settings = label_settings
	vbox.add_child(time_label)
	
	var speed_row = HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	vbox.add_child(speed_row)
	
	_add_speed_btn(speed_row, "⏸️ Pause", 0.0)
	_add_speed_btn(speed_row, "▶️ 1x",   1.0)
	_add_speed_btn(speed_row, "⏩ 10x",  10.0)
	_add_speed_btn(speed_row, "🚀 60x",  60.0)
	
	# ── Render toggles ────────────────────────────────────────────────────────
	var sep = HSeparator.new()
	vbox.add_child(sep)
	
	var toggle_label = Label.new()
	toggle_label.text = "Render Toggles (FPS test)"
	toggle_label.add_theme_color_override("font_color", Color(1, 1, 0.5))
	vbox.add_child(toggle_label)
	
	_add_render_toggle(vbox, "🌿 Grass",      func(n): return [n.grass_multimesh, n.grass_multimesh_b, n.grass_multimesh_c])
	_add_render_toggle(vbox, "🌸 Flowers",    func(n): return [n.flower_multimesh])
	_add_render_toggle(vbox, "🌲 Trees",      func(n): return [n.pine_multimesh, n.birch_multimesh, n.simple_multimesh, n.stylized_multimesh])
	_add_render_toggle(vbox, "🌿 Bushes",     func(n): return [n.bush_a_multimesh, n.rose_bush_multimesh, n.berry_full_multimesh, n.berry_empty_multimesh])
	_add_render_toggle(vbox, "🍎 Apples",     func(n): return [n.apple_ground_multimesh])
	_add_render_toggle(vbox, "💧 Water",      func(n): return [n.water_mesh_instance])
	_add_render_toggle(vbox, "🦊 Animals",    func(n): return [n.animals_container])
	_add_render_toggle(vbox, "🗺️ Terrain",    func(n): return [n.mesh_instance])
	_add_render_toggle(vbox, "📐 Outlines",   func(n): return [n.outline_mesh_instance])

# ─── Helpers ──────────────────────────────────────────────────────────────────

func _add_speed_btn(parent: HBoxContainer, label_text: String, speed: float) -> void:
	var btn = Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(40, 0)
	btn.pressed.connect(func():
		if day_night_cycle:
			day_night_cycle.time_speed = speed
	)
	parent.add_child(btn)

## Creates a checkbox that toggles visibility of nodes returned by [getter] on each ChunkNode.
## [getter] is a lambda: func(node: ChunkNode) -> Array[Node3D]
func _add_render_toggle(parent: VBoxContainer, label_text: String, getter: Callable) -> void:
	var cb = CheckBox.new()
	cb.text = label_text
	cb.button_pressed = true
	cb.toggled.connect(func(on: bool):
		var wm = get_parent()
		if not wm or wm.get("chunk_manager") == null:
			return
		for chunk_node in wm.chunk_manager._active_nodes.values():
			for target in getter.call(chunk_node):
				if target != null:
					target.visible = on
	)
	parent.add_child(cb)

# ─── Per-frame update ─────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not profiler or not database:
		return
		
	var fps := Engine.get_frames_per_second()
	var chunks := database.chunk_count()
	
	var text := "FPS: %d\n" % fps
	text += "Chunks: %d\n\n" % chunks
	text += profiler.format_all()
	
	label.text = text
	
	# Update time display
	if day_night_cycle and time_label:
		var t := day_night_cycle.time_of_day
		var hours := int(t)
		var minutes := int((t - hours) * 60.0)
		time_label.text = "%02d:%02d" % [hours, minutes]
