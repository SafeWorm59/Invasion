extends Control

const JOYSTICK_RADIUS: float = 72.0
const JOYSTICK_TOUCH_RADIUS: float = 102.0
const JOYSTICK_DEADZONE: float = 0.08
const JOYSTICK_SMOOTHING: float = 14.0
const INTERACT_RADIUS: float = 54.0
const MOVEMENT_ACTIONS: Array[String] = [
	"ui_left",
	"ui_right",
	"ui_up",
	"ui_down",
]

var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_offset: Vector2 = Vector2.ZERO
var _target_movement: Vector2 = Vector2.ZERO
var _smoothed_movement: Vector2 = Vector2.ZERO
var _interact_center: Vector2 = Vector2.ZERO
var _joystick_touch_index: int = -1
var _interact_touch_index: int = -1
var _action_is_pressed: Dictionary = {}
var _interact_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

	if not visible:
		return

	resized.connect(_update_layout)
	_update_layout()
	_create_interact_label()


func _physics_process(delta: float) -> void:
	if not visible:
		return

	var smoothing_weight := 1.0 - exp(-JOYSTICK_SMOOTHING * delta)
	_smoothed_movement = _smoothed_movement.lerp(
		_target_movement,
		smoothing_weight
	)
	_apply_movement_actions(_smoothed_movement)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch

		if touch.pressed:
			if (
				_interact_touch_index == -1
				and touch.position.distance_to(_interact_center)
				<= INTERACT_RADIUS
			):
				_interact_touch_index = touch.index
				Input.action_press("interact")
				get_viewport().set_input_as_handled()
			elif (
				_joystick_touch_index == -1
				and touch.position.distance_to(_joystick_center)
				<= JOYSTICK_TOUCH_RADIUS
			):
				_joystick_touch_index = touch.index
				_update_joystick(touch.position)
				get_viewport().set_input_as_handled()
		else:
			if touch.index == _interact_touch_index:
				_interact_touch_index = -1
				Input.action_release("interact")
				get_viewport().set_input_as_handled()

			if touch.index == _joystick_touch_index:
				_joystick_touch_index = -1
				_joystick_offset = Vector2.ZERO
				_target_movement = Vector2.ZERO
				_smoothed_movement = Vector2.ZERO
				_release_movement_actions()
				queue_redraw()
				get_viewport().set_input_as_handled()

	elif (
		event is InputEventScreenDrag
		and (event as InputEventScreenDrag).index == _joystick_touch_index
	):
		_update_joystick((event as InputEventScreenDrag).position)
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	_release_movement_actions()

	if _interact_touch_index != -1:
		Input.action_release("interact")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_update_layout()


func _update_layout() -> void:
	var viewport_size := get_viewport_rect().size
	_joystick_center = Vector2(108.0, viewport_size.y - 156.0)
	_interact_center = Vector2(viewport_size.x - 108.0, viewport_size.y - 156.0)

	if is_instance_valid(_interact_label):
		_interact_label.position = _interact_center - _interact_label.size * 0.5

	queue_redraw()


func _create_interact_label() -> void:
	_interact_label = Label.new()
	_interact_label.text = "USE"
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interact_label.custom_minimum_size = Vector2(100.0, 44.0)
	_interact_label.size = _interact_label.custom_minimum_size
	_interact_label.add_theme_font_size_override("font_size", 18)
	_interact_label.add_theme_color_override("font_color", Color.WHITE)
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_label)
	_update_layout()


func _update_joystick(touch_position: Vector2) -> void:
	_joystick_offset = (touch_position - _joystick_center).limit_length(
		JOYSTICK_RADIUS
	)

	var strength := _joystick_offset.length() / JOYSTICK_RADIUS

	if strength <= JOYSTICK_DEADZONE:
		_target_movement = Vector2.ZERO
	else:
		var normalized_strength := (
			(strength - JOYSTICK_DEADZONE) / (1.0 - JOYSTICK_DEADZONE)
		)
		_target_movement = (
			_joystick_offset.normalized()
			* pow(normalized_strength, 1.2)
		)

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
		return

	Input.action_press(action, strength)
	_action_is_pressed[action] = true


func _release_movement_actions() -> void:
	for action in MOVEMENT_ACTIONS:
		if _action_is_pressed.get(action, false):
			Input.action_release(action)
			_action_is_pressed[action] = false


func _draw() -> void:
	if not visible:
		return

	draw_circle(_joystick_center, JOYSTICK_RADIUS + 8.0, Color(0.03, 0.04, 0.08, 0.42))
	draw_arc(
		_joystick_center,
		JOYSTICK_RADIUS + 8.0,
		0.0,
		TAU,
		48,
		Color(0.85, 0.9, 1.0, 0.65),
		3.0,
		true
	)
	draw_arc(
		_joystick_center,
		JOYSTICK_RADIUS * JOYSTICK_DEADZONE,
		0.0,
		TAU,
		32,
		Color(0.85, 0.9, 1.0, 0.28),
		1.5,
		true
	)
	draw_circle(_joystick_center + _joystick_offset, 28.0, Color(0.8, 0.86, 0.96, 0.82))

	draw_circle(_interact_center, INTERACT_RADIUS, Color(0.55, 0.12, 0.2, 0.72))
	draw_arc(
		_interact_center,
		INTERACT_RADIUS,
		0.0,
		TAU,
		40,
		Color(1.0, 0.78, 0.82, 0.9),
		3.0,
		true
	)
