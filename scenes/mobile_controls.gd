extends Control

const UISafeArea := preload("res://scripts/ui_safe_area.gd")
const CONTROL_NAMES: Array[String] = ["joystick", "infect", "follow", "capture", "defend"]
const FOLLOW_ICON: Texture2D = preload("res://assets/ui/follow.svg")
const CAPTURE_ICON: Texture2D = preload("res://assets/ui/capture.svg")
const DEFEND_ICON: Texture2D = preload("res://assets/ui/defend.svg")
const JOIN_ATTACK_ICON: Texture2D = preload("res://assets/ui/join_attack.svg")
const JOYSTICK_RADIUS: float = 72.0
const JOYSTICK_DEADZONE: float = 0.08
const JOYSTICK_SMOOTHING: float = 14.0
const MOVEMENT_ACTIONS: Array[String] = ["ui_left", "ui_right", "ui_up", "ui_down"]

var layout: Dictionary = {}
var enabled_for_preview: bool = false
var edit_mode: bool = false
var input_suspended: bool = false
var _was_visible_before_suspend: bool = true
var selected_control: String = ""
var _centers: Dictionary = {}
var _radii: Dictionary = {}
var _touch_controls: Dictionary = {}
var _joystick_offset := Vector2.ZERO
var _target_movement := Vector2.ZERO
var _smoothed_movement := Vector2.ZERO
var _action_is_pressed: Dictionary = {}
var _follow_button: Button
var _capture_button: Button
var _defend_button: Button
var _active_command: String = "follow"
var _join_attack_available: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("mobile_controls")
	layout = GameManager.get_mobile_control_layout()
	enabled_for_preview = OS.has_feature("mobile") or GameManager.mobile_controls_preview_on_desktop
	_update_layout()
	resized.connect(_update_layout)


func configure_preview(preview_layout: Dictionary, selection: String = "") -> void:
	layout = preview_layout.duplicate(true)
	selected_control = selection
	enabled_for_preview = true
	edit_mode = true
	_update_layout()


func bind_command_buttons(follow: Button, capture: Button, defend: Button) -> void:
	_follow_button = follow
	_capture_button = capture
	_defend_button = defend


func set_active_command(command: String) -> void:
	if command not in ["follow", "capture", "defend"]:
		return
	_active_command = command
	queue_redraw()


func set_context_action(join_attack_available: bool) -> void:
	if _join_attack_available == join_attack_available:
		return
	_join_attack_available = join_attack_available
	queue_redraw()


func get_control_rect(control_name: String) -> Rect2:
	if not _centers.has(control_name) or not _radii.has(control_name):
		return Rect2()
	var radius: float = float(_radii[control_name])
	var center: Vector2 = _centers[control_name]
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


func apply_layout(new_layout: Dictionary) -> void:
	layout = new_layout.duplicate(true)
	_update_layout()


func suspend_input(suspended: bool) -> void:
	input_suspended = suspended
	if suspended:
		_was_visible_before_suspend = visible
		visible = false
		_target_movement = Vector2.ZERO
		_smoothed_movement = Vector2.ZERO
		_release_movement_actions()
		for control_name in _touch_controls.values():
			if control_name == "infect":
				Input.action_release("interact")
		_touch_controls.clear()
	else:
		visible = _was_visible_before_suspend


func _physics_process(delta: float) -> void:
	if not enabled_for_preview or edit_mode or input_suspended:
		return
	var weight := 1.0 - exp(-JOYSTICK_SMOOTHING * delta)
	_smoothed_movement = _smoothed_movement.lerp(_target_movement, weight)
	_apply_movement_actions(_smoothed_movement)


func _input(event: InputEvent) -> void:
	if not enabled_for_preview or edit_mode or input_suspended:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_control_press(touch.index, touch.position)
		else:
			_finish_control_press(touch.index, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _touch_controls.get(drag.index, "") == "joystick":
			_update_joystick(drag.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_index: int = -2
		if event.pressed:
			_begin_control_press(mouse_index, event.position)
		else:
			_finish_control_press(mouse_index, event.position)
	elif event is InputEventMouseMotion and _touch_controls.get(-2, "") == "joystick":
		var motion := event as InputEventMouseMotion
		_update_joystick(motion.position)
		get_viewport().set_input_as_handled()


func _begin_control_press(pointer_index: int, position: Vector2) -> void:
	for control_name in CONTROL_NAMES:
		if _touch_controls.values().has(control_name):
			continue
		var is_pressed_area := _is_inside_control(control_name, position)
		if control_name == "joystick":
			is_pressed_area = position.distance_to(_centers[control_name]) <= _radii[control_name] + 30.0
		if not is_pressed_area:
			continue

		_touch_controls[pointer_index] = control_name
		if control_name == "infect":
			Input.action_press("interact")
		elif control_name == "joystick":
			_update_joystick(position)
		get_viewport().set_input_as_handled()
		return


func _finish_control_press(pointer_index: int, position: Vector2) -> void:
	if not _touch_controls.has(pointer_index):
		return

	var released_control: String = _touch_controls[pointer_index]
	_touch_controls.erase(pointer_index)
	if released_control == "infect":
		Input.action_release("interact")
	elif released_control == "joystick":
		_joystick_offset = Vector2.ZERO
		_target_movement = Vector2.ZERO
		_smoothed_movement = Vector2.ZERO
		_release_movement_actions()
	elif _is_inside_control(released_control, position):
		_emit_command(released_control)
	queue_redraw()
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_release_movement_actions()
	for control_name in _touch_controls.values():
		if control_name == "infect":
			Input.action_release("interact")
	_touch_controls.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()


func _update_layout() -> void:
	if not is_inside_tree():
		return
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	for control_name in CONTROL_NAMES:
		var entry: Dictionary = layout.get(control_name, GameManager.DEFAULT_CONTROL_LAYOUT[control_name])
		var scale_value := float(entry.get("scale", 1.0))
		var normalized_position: Vector2 = entry.get("position", Vector2(0.5, 0.8))
		var center := safe_rect.position + normalized_position * safe_rect.size
		var radius := _base_radius(control_name) * scale_value
		var half_size := _half_size(control_name, scale_value)
		center.x = clampf(center.x, safe_rect.position.x + half_size.x, safe_rect.end.x - half_size.x)
		center.y = clampf(center.y, safe_rect.position.y + half_size.y, safe_rect.end.y - half_size.y)
		_centers[control_name] = center
		_radii[control_name] = radius
	queue_redraw()


func _base_radius(control_name: String) -> float:
	return 72.0 if control_name == "joystick" else 54.0


func _half_size(control_name: String, scale_value: float) -> Vector2:
	if control_name == "joystick":
		return Vector2(80.0, 80.0) * scale_value
	return Vector2(56.0, 56.0) * scale_value


func _is_inside_control(control_name: String, point: Vector2) -> bool:
	return point.distance_to(_centers[control_name]) <= _radii[control_name]


func _emit_command(control_name: String) -> void:
	var target: Button
	match control_name:
		"follow": target = _follow_button
		"capture": target = _capture_button
		"defend": target = _defend_button
	if is_instance_valid(target) and not target.disabled:
		target.pressed.emit()


func _update_joystick(position: Vector2) -> void:
	_joystick_offset = (position - _centers["joystick"]).limit_length(JOYSTICK_RADIUS * float(layout["joystick"].get("scale", 1.0)))
	var strength := _joystick_offset.length() / (JOYSTICK_RADIUS * float(layout["joystick"].get("scale", 1.0)))
	if strength <= JOYSTICK_DEADZONE:
		_target_movement = Vector2.ZERO
	else:
		_target_movement = _joystick_offset.normalized() * pow((strength - JOYSTICK_DEADZONE) / (1.0 - JOYSTICK_DEADZONE), 1.2)
	queue_redraw()


func _apply_movement_actions(direction: Vector2) -> void:
	_set_movement_action("ui_left", maxf(0.0, -direction.x))
	_set_movement_action("ui_right", maxf(0.0, direction.x))
	_set_movement_action("ui_up", maxf(0.0, -direction.y))
	_set_movement_action("ui_down", maxf(0.0, direction.y))


func _set_movement_action(action: String, strength: float) -> void:
	if strength <= 0.01:
		if _action_is_pressed.get(action, false):
			Input.action_release(action)
			_action_is_pressed[action] = false
	else:
		Input.action_press(action, strength)
		_action_is_pressed[action] = true


func _release_movement_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		if _action_is_pressed.get(action, false):
			Input.action_release(action)
			_action_is_pressed[action] = false


func _draw() -> void:
	if not enabled_for_preview:
		return
	for control_name in CONTROL_NAMES:
		var entry: Dictionary = layout.get(control_name, GameManager.DEFAULT_CONTROL_LAYOUT[control_name])
		var center: Vector2 = _centers.get(control_name, Vector2.ZERO)
		var color := Color(0.04, 0.06, 0.12, float(entry.get("opacity", 0.85)))
		var outline := Color(0.75, 0.88, 1.0, minf(1.0, color.a + 0.15))
		if selected_control == control_name:
			outline = Color(0.35, 1.0, 0.72, 1.0)
		if control_name == "joystick":
			var radius: float = 72.0 * float(entry.get("scale", 1.0))
			draw_circle(center, radius, color)
			draw_arc(center, radius, 0.0, TAU, 48, outline, 3.0, true)
			draw_circle(center + _joystick_offset, 28.0 * float(entry.get("scale", 1.0)), Color(0.8, 0.86, 0.96, color.a))
			_draw_centered_text(center, "MOVE", 15, color.a)
		elif control_name == "infect":
			var scale_value: float = float(entry.get("scale", 1.0))
			var radius: float = 54.0 * scale_value
			var button_color := Color(0.55, 0.12, 0.2, color.a)
			var button_outline := outline
			if _join_attack_available:
				button_color = Color(0.78, 0.34, 0.06, color.a)
				button_outline = Color(1.0, 0.76, 0.30, 1.0)
			draw_circle(center, radius, button_color)
			draw_arc(center, radius, 0.0, TAU, 40, button_outline, 3.0, true)
			if _join_attack_available:
				var icon_size := 30.0 * scale_value
				draw_texture_rect(
					JOIN_ATTACK_ICON,
					Rect2(
						center + Vector2(-icon_size * 0.5, -icon_size * 0.88),
						Vector2.ONE * icon_size
					),
					false,
					Color(1.0, 1.0, 1.0, color.a)
				)
				_draw_centered_text(
					center + Vector2(0.0, 27.0 * scale_value),
					"JOIN ATTACK",
					10,
					color.a
				)
			else:
				_draw_centered_text(center, "INFECT", 15, color.a)
		else:
			var scale_value := float(entry.get("scale", 1.0))
			var radius := 54.0 * scale_value
			var command_color := Color(0.55, 0.12, 0.2, color.a)
			var command_outline := outline
			if control_name == _active_command and selected_control != control_name:
				command_color = Color(0.72, 0.16, 0.25, color.a)
				command_outline = Color(1.0, 0.78, 0.42, 1.0)
			draw_circle(center, radius, command_color)
			draw_arc(center, radius, 0.0, TAU, 40, command_outline, 3.0, true)
			var icon := _command_icon(control_name)
			if icon != null:
				var icon_size := 32.0 * scale_value
				var icon_rect := Rect2(
					center + Vector2(-icon_size * 0.5, -icon_size * 0.5 - 8.0 * scale_value),
					Vector2.ONE * icon_size
				)
				draw_texture_rect(icon, icon_rect, false, Color(1.0, 1.0, 1.0, color.a))
			_draw_centered_text(
				center + Vector2(0.0, 28.0 * scale_value),
				control_name.to_upper(),
				12,
				color.a
			)


func _command_icon(control_name: String) -> Texture2D:
	match control_name:
		"follow":
			return FOLLOW_ICON
		"capture":
			return CAPTURE_ICON
		"defend":
			return DEFEND_ICON
	return null


func _draw_centered_text(center: Vector2, text: String, font_size: int, opacity: float) -> void:
	var font := ThemeDB.fallback_font
	if font:
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 1.0, 1.0, opacity))
