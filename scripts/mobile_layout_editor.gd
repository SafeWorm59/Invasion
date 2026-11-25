class_name MobileLayoutEditor
extends Control

signal closed
signal layout_saved(layout: Dictionary)

const MobileControls := preload("res://scenes/mobile_controls.gd")
const UISafeArea := preload("res://scripts/ui_safe_area.gd")
const CONTROL_NAMES: Array[String] = ["joystick", "infect", "follow", "capture", "defend"]

var _layout: Dictionary
var _selected := "joystick"
var _dragging := false
var _drag_touch := -1
var _preview: MobileControls
var _panel: PanelContainer
var _selection_label: Label
var _size_slider: HSlider
var _opacity_slider: HSlider
var _size_value: Label
var _opacity_value: Label
var _suspended_controls: Array[Node] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layout = GameManager.get_mobile_control_layout()
	for gameplay_controls in get_tree().get_nodes_in_group("mobile_controls"):
		if is_instance_valid(gameplay_controls) and gameplay_controls.has_method("suspend_input"):
			gameplay_controls.suspend_input(true)
			_suspended_controls.append(gameplay_controls)
	_preview = MobileControls.new()
	_preview.name = "GameplayControlsPreview"
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.configure_preview(_layout, _selected)
	add_child(_preview)
	_panel = PanelContainer.new()
	_panel.name = "EditorPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.offset_left = -265
	_panel.offset_right = 265
	_panel.offset_top = 18
	_panel.offset_bottom = 244
	_panel.add_theme_stylebox_override("panel", UIThemeHelper.create_panel_style(Color(0.07, 0.04, 0.09, 0.96), Color(0.35, 0.9, 0.7, 0.9), 10))
	add_child(_panel)
	_build_panel()
	resized.connect(_on_editor_resized)
	_fit_panel()


func _build_panel() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var title := Label.new()
	title.text = "CUSTOMIZE TOUCH CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "Drag any control in the gameplay preview below. Select one to resize or fade it."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	column.add_child(hint)
	_selection_label = Label.new()
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_selection_label)
	_size_slider = _make_slider_row(column, "Size", 0.65, 1.5, "_size_value")
	_opacity_slider = _make_slider_row(column, "Opacity", 0.3, 1.0, "_opacity_value")
	_size_slider.value_changed.connect(_on_size_changed)
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	var actions: BoxContainer
	if UISafeArea.get_safe_rect(get_viewport_rect().size).size.x < 480.0:
		actions = VBoxContainer.new()
	else:
		actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_add_button(actions, "SAVE", _save)
	_add_button(actions, "CANCEL", _cancel)
	_add_button(actions, "RESET TO DEFAULT", _reset)
	_refresh_selection_ui()


func _make_slider_row(parent: VBoxContainer, title: String, minimum: float, maximum: float, value_field: String) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 70
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.05
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 45
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	set(value_field, value_label)
	parent.add_child(row)
	return slider


func _add_button(parent: BoxContainer, title: String, action: Callable) -> void:
	var button := Button.new()
	button.text = title
	var safe_width := UISafeArea.get_safe_rect(get_viewport_rect().size).size.x
	var button_width := minf(220.0, safe_width - 64.0) if parent is VBoxContainer else minf(130.0, (safe_width - 80.0) / 3.0)
	button.custom_minimum_size = Vector2(maxf(100.0, button_width), 48.0)
	button.add_theme_font_size_override("font_size", 11)
	UIThemeHelper.style_button(button, title == "SAVE")
	button.pressed.connect(action)
	parent.add_child(button)


func _on_editor_resized() -> void:
	_fit_panel()
	_refresh_preview()


func _fit_panel() -> void:
	if not is_instance_valid(_panel):
		return
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	var panel_width := minf(530.0, maxf(280.0, safe_rect.size.x - 20.0))
	var center_delta_x := safe_rect.get_center().x - viewport_size.x * 0.5
	var panel_height := minf(320.0, maxf(244.0, safe_rect.size.y - 36.0))
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_right = panel_width * 0.5
	_panel.offset_left += center_delta_x
	_panel.offset_right += center_delta_x
	_panel.offset_top = safe_rect.position.y + 18.0
	_panel.offset_bottom = _panel.offset_top + panel_height


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_drag(touch.position, touch.index)
		elif _dragging and touch.index == _drag_touch:
			_dragging = false
			_drag_touch = -1
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _dragging and drag.index == _drag_touch:
			_move_selected(drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position, -2)
		elif _dragging and _drag_touch == -2:
			_dragging = false
			_drag_touch = -1
	elif event is InputEventMouseMotion and _dragging and _drag_touch == -2:
		_move_selected(event.position)
		get_viewport().set_input_as_handled()


func _begin_drag(point: Vector2, touch_index: int) -> void:
	if _panel.get_global_rect().has_point(point):
		return
	var hit := ""
	for control_name in CONTROL_NAMES:
		var center: Vector2 = _preview._centers.get(control_name, Vector2.ZERO)
		var radius: float = float(_preview._radii.get(control_name, 42.0)) + 10.0
		if point.distance_to(center) <= radius:
			hit = control_name
			break
	if hit.is_empty():
		return
	_selected = hit
	_dragging = true
	_drag_touch = touch_index
	_refresh_selection_ui()
	get_viewport().set_input_as_handled()


func _move_selected(point: Vector2) -> void:
	var safe_rect := _safe_rect()
	var half: Vector2 = _preview._half_size(_selected, float(_layout[_selected].get("scale", 1.0)))
	var center := point.clamp(safe_rect.position + half, safe_rect.end - half)
	var proposed := (center - safe_rect.position) / safe_rect.size
	for other_name in CONTROL_NAMES:
		if other_name == _selected:
			continue
		var other_center: Vector2 = _preview._centers.get(other_name, Vector2.ZERO)
		var other_half: Vector2 = _preview._half_size(other_name, float(_layout[other_name].get("scale", 1.0)))
		var separation := half + other_half
		if absf(center.x - other_center.x) < separation.x and absf(center.y - other_center.y) < separation.y:
			return
	_layout[_selected]["position"] = proposed.clamp(Vector2.ZERO, Vector2.ONE)
	_refresh_preview()


func _safe_rect() -> Rect2:
	return UISafeArea.get_safe_rect(get_viewport_rect().size)


func _on_size_changed(value: float) -> void:
	var candidate_half: Vector2 = _preview._half_size(_selected, value)
	var center: Vector2 = _preview._centers.get(_selected, Vector2.ZERO)
	for other_name in CONTROL_NAMES:
		if other_name == _selected:
			continue
		var other_half: Vector2 = _preview._half_size(other_name, float(_layout[other_name].get("scale", 1.0)))
		var other_center: Vector2 = _preview._centers.get(other_name, Vector2.ZERO)
		var separation := candidate_half + other_half
		if absf(center.x - other_center.x) < separation.x and absf(center.y - other_center.y) < separation.y:
			_size_slider.value = float(_layout[_selected].get("scale", 1.0))
			return
	_layout[_selected]["scale"] = value
	_refresh_selection_ui(false)
	_refresh_preview()


func _on_opacity_changed(value: float) -> void:
	_layout[_selected]["opacity"] = value
	_refresh_selection_ui(false)
	_refresh_preview()


func _refresh_selection_ui(update_sliders: bool = true) -> void:
	if not is_instance_valid(_selection_label):
		return
	_selection_label.text = "Selected: %s" % _selected.to_upper()
	if update_sliders:
		_size_slider.value = float(_layout[_selected].get("scale", 1.0))
		_opacity_slider.value = float(_layout[_selected].get("opacity", 0.85))
	_size_value.text = "%d%%" % int(_size_slider.value * 100.0)
	_opacity_value.text = "%d%%" % int(_opacity_slider.value * 100.0)


func _refresh_preview() -> void:
	if is_instance_valid(_preview):
		_preview.configure_preview(_layout, _selected)
		_preview.queue_redraw()
	queue_redraw()


func _save() -> void:
	if not GameManager.save_mobile_control_layout(_layout):
		return
	for mobile_controls in get_tree().get_nodes_in_group("mobile_controls"):
		if is_instance_valid(mobile_controls) and mobile_controls.has_method("apply_layout"):
			mobile_controls.apply_layout(_layout)
	layout_saved.emit(_layout.duplicate(true))
	_restore_gameplay_controls()
	closed.emit()


func _cancel() -> void:
	_restore_gameplay_controls()
	closed.emit()


func _exit_tree() -> void:
	_restore_gameplay_controls()


func _restore_gameplay_controls() -> void:
	for gameplay_controls in _suspended_controls:
		if is_instance_valid(gameplay_controls) and gameplay_controls.has_method("suspend_input"):
			gameplay_controls.suspend_input(false)
	_suspended_controls.clear()


func _reset() -> void:
	_layout = GameManager.reset_mobile_control_layout()
	_refresh_selection_ui()
	_refresh_preview()


func _draw() -> void:
	var viewport_size := size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.01, 0.04, 0.06, 1.0), true)
	# Lightweight gameplay context behind the touch layout preview.
	for i in range(9):
		var p := Vector2(viewport_size.x * (0.12 + float((i * 17) % 73) / 100.0), viewport_size.y * (0.30 + float((i * 13) % 46) / 100.0))
		draw_circle(p, 22.0 + float(i % 3) * 6.0, Color(0.15, 0.55, 0.48, 0.18))
		draw_arc(p, 27.0 + float(i % 3) * 6.0, 0.0, TAU, 24, Color(0.37, 0.84, 0.7, 0.22), 2.0)
	draw_rect(Rect2(Vector2(18, 18), Vector2(245, 70)), Color(0.03, 0.05, 0.1, 0.55), true)
	draw_string(ThemeDB.fallback_font, Vector2(28, 45), "VIRUS HEALTH  100 / 100", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 1.0, 0.94, 0.8))
	draw_string(ThemeDB.fallback_font, Vector2(28, 70), "HOST CELLS  8 / 20", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 1.0, 0.94, 0.7))
	draw_rect(Rect2((viewport_size.x - 320.0) * 0.5, 258, 320, 42), Color(0.03, 0.05, 0.1, 0.5), true)
	draw_string(ThemeDB.fallback_font, Vector2((viewport_size.x - 250.0) * 0.5, 284), "OBJECTIVE  INFECT ALL HOST CELLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.9, 1.0, 0.94, 0.7))
	draw_rect(Rect2(viewport_size.x - 185, 22, 160, 105), Color(0.03, 0.05, 0.1, 0.6), true)
	draw_circle(Vector2(viewport_size.x - 104, 74), 5, Color(0.25, 0.9, 0.52, 0.95))
	draw_circle(Vector2(viewport_size.x - 63, 96), 5, Color(0.95, 0.26, 0.24, 0.95))
