class_name TutorialOverlay
extends Control

const UISafeArea := preload("res://scripts/ui_safe_area.gd")

signal continue_requested
signal skip_requested

var _dim: ColorRect
var _panel: PanelContainer
var _progress_label: Label
var _title_label: Label
var _body_label: Label
var _hint_label: Label
var _continue_button: Button
var _skip_button: Button
var _highlight_target: Node2D
var _highlight_hud: Node
var _highlight_control: String = ""
var _highlight_rect := Rect2()
var _highlight_radius: float = 0.0
var _highlight_offscreen_direction := Vector2.ZERO
var _is_modal: bool = false
var _is_waiting: bool = false
var _highlight_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_build_ui()
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		"panel",
		UIThemeHelper.create_panel_style(
			Color(0.08, 0.035, 0.075, 0.97),
			Color(0.95, 0.38, 0.52, 0.96),
			14
		)
	)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_color_override("font_color", Color("#e6b8ca"))
	layout.add_child(_progress_label)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_color_override("font_color", Color("#fff1f4"))
	layout.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_color_override("font_color", Color("#eee4eb"))
	layout.add_child(_body_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_color_override("font_color", Color("#ffd179"))
	layout.add_child(_hint_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	layout.add_child(actions)

	_continue_button = Button.new()
	_continue_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_button.custom_minimum_size.y = 48.0
	UIThemeHelper.style_button(_continue_button, true)
	_continue_button.pressed.connect(func(): continue_requested.emit())
	actions.add_child(_continue_button)

	_skip_button = Button.new()
	_skip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skip_button.custom_minimum_size.y = 48.0
	_skip_button.text = "SKIP TUTORIAL"
	UIThemeHelper.style_button(_skip_button, false)
	_skip_button.pressed.connect(func(): skip_requested.emit())
	actions.add_child(_skip_button)


func present_step(
	step: Dictionary,
	world_target: Node2D,
	hud: Node,
	level_id: int,
	step_number: int,
	step_count: int,
	highlight_control: String
) -> void:
	_highlight_target = world_target
	_highlight_hud = hud
	_highlight_control = highlight_control
	_is_modal = bool(step.get("pause", false))
	_is_waiting = false
	_dim.mouse_filter = (
		Control.MOUSE_FILTER_STOP if _is_modal else Control.MOUSE_FILTER_IGNORE
	)
	_progress_label.text = "LEVEL %d TUTORIAL  |  %d / %d" % [
		level_id,
		step_number,
		step_count,
	]
	_title_label.text = String(step.get("title", "TUTORIAL"))
	_body_label.text = String(step.get("body", ""))
	_hint_label.text = String(step.get("hint", ""))
	_hint_label.visible = not _hint_label.text.is_empty()
	_continue_button.text = String(step.get("button", "NEXT"))
	_continue_button.disabled = not bool(step.get("enabled", true))
	_continue_button.visible = bool(step.get("show_continue", true))
	_layout_panel()
	queue_redraw()


func present_waiting_for_exit(
	level_id: int,
	step_number: int,
	step_count: int
) -> void:
	_highlight_target = null
	_highlight_hud = null
	_highlight_control = ""
	_is_modal = false
	_is_waiting = true
	_progress_label.text = "LEVEL %d TUTORIAL  |  %d / %d" % [
		level_id,
		step_number,
		step_count,
	]
	_title_label.text = "KEEP PLAYING"
	_body_label.text = "Defeat every neutrophil to unlock the exit. We'll highlight it when it opens."
	_hint_label.text = ""
	_hint_label.visible = false
	_continue_button.visible = false
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_panel()
	queue_redraw()


func set_body_text(text: String) -> void:
	_body_label.text = text
	_layout_panel()


func set_hint_text(text: String) -> void:
	_hint_label.text = text
	_hint_label.visible = not text.is_empty()
	_layout_panel()


func set_highlight_control(control_name: String) -> void:
	_highlight_control = control_name
	_update_highlight()
	queue_redraw()


func _process(delta: float) -> void:
	_highlight_timer -= delta
	if _highlight_timer > 0.0:
		return
	_highlight_timer = 0.06
	_update_highlight()
	queue_redraw()


func _update_highlight() -> void:
	_highlight_rect = Rect2()
	_highlight_radius = 0.0
	_highlight_offscreen_direction = Vector2.ZERO
	if not _highlight_control.is_empty():
		if is_instance_valid(_highlight_hud) and _highlight_hud.has_method("get_tutorial_control_rect"):
			_highlight_rect = _highlight_hud.get_tutorial_control_rect(
				_highlight_control
			)
		return

	if not is_instance_valid(_highlight_target):
		return

	var target_transform := _highlight_target.get_global_transform_with_canvas()
	var center := target_transform.origin
	var scale_factor := target_transform.get_scale().x
	var target_radius := _target_radius(_highlight_target)
	_highlight_radius = maxf(target_radius * scale_factor + 10.0, 30.0)
	var viewport_size := get_viewport_rect().size
	var edge_rect := Rect2(Vector2(28.0, 28.0), viewport_size - Vector2(56.0, 56.0))
	if not edge_rect.has_point(center):
		var edge_center := center.clamp(edge_rect.position, edge_rect.end)
		_highlight_offscreen_direction = (center - edge_center).normalized()
		center = edge_center
	_highlight_rect = Rect2(
		center - Vector2.ONE * _highlight_radius,
		Vector2.ONE * _highlight_radius * 2.0
	)


func _target_radius(target: Node2D) -> float:
	for property_name in ["body_radius", "cell_radius"]:
		for property in target.get_property_list():
			if String(property.get("name", "")) == property_name:
				var property_value: Variant = target.get(property_name)
				if property_value is float or property_value is int:
					if float(property_value) > 0.0:
						return float(property_value)

	var collision := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		if collision.shape is CircleShape2D:
			return (collision.shape as CircleShape2D).radius
		if collision.shape is RectangleShape2D:
			return (collision.shape as RectangleShape2D).size.length() * 0.5
	return 34.0


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(
			0.015,
			0.025,
			0.06,
			0.0 if _is_waiting else (0.42 if _is_modal else 0.28)
		)
	)
	if _highlight_rect.size == Vector2.ZERO:
		return
	var center := _highlight_rect.get_center()
	var radius := maxf(_highlight_rect.size.x, _highlight_rect.size.y) * 0.5
	var pulse := 1.0 + 0.045 * sin(Time.get_ticks_msec() / 220.0)
	draw_arc(
		center,
		radius * pulse,
		0.0,
		TAU,
		48,
		Color(1.0, 0.78, 0.28, 0.98),
		4.0,
		true
	)
	if _highlight_offscreen_direction != Vector2.ZERO:
		var direction := _highlight_offscreen_direction
		var tip := center + direction * 16.0
		var base := center - direction * 10.0
		var side := direction.rotated(PI / 2.0) * 9.0
		draw_colored_polygon(
			PackedVector2Array([tip, base + side, base - side]),
			Color(1.0, 0.78, 0.28, 1.0)
		)
	draw_arc(
		center,
		radius * pulse + 7.0,
		0.0,
		TAU,
		48,
		Color(1.0, 0.78, 0.28, 0.42),
		2.0,
		true
	)


func _layout_panel() -> void:
	if not is_instance_valid(_panel) or not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var safe_rect: Rect2 = UISafeArea.get_safe_rect(viewport_size)
	var panel_width := maxf(200.0, minf(560.0, safe_rect.size.x - 24.0))
	_panel.custom_minimum_size.x = panel_width
	_panel.reset_size()
	var panel_height := minf(
		_panel.get_combined_minimum_size().y,
		maxf(180.0, safe_rect.size.y - 24.0)
	)
	_panel.size = Vector2(panel_width, panel_height)
	_panel.position = Vector2(
		safe_rect.get_center().x - panel_width * 0.5,
		safe_rect.position.y + 12.0
	)
