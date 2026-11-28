
extends CanvasLayer

const Minimap := preload("res://scenes/minimap.gd")
const MobileControls := preload("res://scenes/mobile_controls.gd")
const UISafeArea := preload("res://scripts/ui_safe_area.gd")
const EXIT_CONFIRMATION_TEXT: String = "Exit the current game and return to the main menu?"
const FOLLOW_ICON: Texture2D = preload("res://assets/ui/follow.svg")
const CAPTURE_ICON: Texture2D = preload("res://assets/ui/capture.svg")
const DEFEND_ICON: Texture2D = preload("res://assets/ui/defend.svg")
const JOIN_ATTACK_ICON: Texture2D = preload("res://assets/ui/join_attack.svg")
const ENEMY_GROUPS: Array[String] = ["immune_cells", "nkt_cells"]
const CONTEXT_SCAN_INTERVAL: float = 0.1
const DIAGNOSTICS_UPDATE_INTERVAL: float = 0.5

@export var performance_diagnostics_enabled: bool = false

@onready var follow_button: Button = $CommandButtons/VBoxContainer/FollowButton
@onready var capture_button: Button = $CommandButtons/VBoxContainer/CaptureButton
@onready var defend_button: Button = $CommandButtons/VBoxContainer/DefendButton
@onready var health_label: Label = $HealthPanel/HealthLayout/HealthLabel
@onready var health_bar: ProgressBar = $HealthPanel/HealthLayout/HealthBar
@onready var health_panel: PanelContainer = $HealthPanel
@onready var exit_button: Button = $ExitButton
@onready var pause_button: Button = $PauseButton

var objective_panel: PanelContainer
var objective_label: Label
var objective_bar: ProgressBar
var objective_status: Label

var context_action_button: Button
var _context_button_icon: TextureRect
var _context_button_label: Label
var nearby_target: Node2D = null
var _context_is_join_attack: bool = false
var _context_button_opacity: float = 0.85
var _join_target_lost_time: float = 0.0

var objective_name: String = "HOST CELLS"

var notification_box: VBoxContainer
var _notification_cooldowns: Dictionary = {}
var _exit_dialog: ConfirmationDialog
var _pause_overlay: Control
var _paused_by_hud: bool = false
var _last_pause_input_msec: int = -1000
var _mobile_controls: MobileControls
var _minimap: Minimap
var _active_command: String = "follow"
var _context_scan_timer: float = 0.0
var _performance_panel: PanelContainer
var _performance_label: Label
var _diagnostics_update_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud")

	follow_button.pressed.connect(_on_follow_button_pressed)
	capture_button.pressed.connect(_on_capture_button_pressed)
	defend_button.pressed.connect(_on_defend_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	pause_button.pressed.connect(_on_pause_button_pressed)
	_setup_command_button(follow_button, FOLLOW_ICON, "FOLLOW")
	_setup_command_button(capture_button, CAPTURE_ICON, "CAPTURE")
	_setup_command_button(defend_button, DEFEND_ICON, "DEFEND")
	_refresh_command_button_styles()
	UIThemeHelper.style_button(exit_button, false)
	exit_button.add_theme_font_size_override("font_size", 14)
	UIThemeHelper.style_button(pause_button, false)
	pause_button.add_theme_font_size_override("font_size", 14)

	update_player_health(100, 100)
	create_objective_display()
	create_notification_display()

	# Reusable level minimap, pinned to the top-right corner.
	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	add_child(_minimap)

	_mobile_controls = MobileControls.new()
	_mobile_controls.name = "MobileControls"
	add_child(_mobile_controls)
	_mobile_controls.bind_command_buttons(follow_button, capture_button, defend_button)
	var use_mobile_controls := OS.has_feature("mobile") or GameManager.mobile_controls_preview_on_desktop
	$CommandButtons.visible = not use_mobile_controls
	_mobile_controls.enabled_for_preview = use_mobile_controls
	_mobile_controls.visible = use_mobile_controls
	_mobile_controls.set_active_command(_active_command)
	_mobile_controls.set_context_action(false)
	if not use_mobile_controls:
		_create_context_action_button()
	_create_performance_diagnostics()
	get_viewport().size_changed.connect(_fit_to_safe_area)
	_fit_to_safe_area()
	call_deferred("_start_level_tutorial")


func _start_level_tutorial() -> void:
	TutorialManager.start_for_current_level(self)


func set_tutorial_input_suspended(suspended: bool) -> void:
	if is_instance_valid(_mobile_controls):
		_mobile_controls.suspend_input(suspended)


func get_tutorial_control_rect(control_name: String) -> Rect2:
	if is_instance_valid(_mobile_controls) and _mobile_controls.visible:
		return _mobile_controls.get_control_rect(control_name)
	if control_name == "infect" and is_instance_valid(context_action_button):
		return context_action_button.get_global_rect()
	return Rect2()


func _fit_to_safe_area() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	var health_width := minf(356.0, maxf(260.0, safe_rect.size.x - 40.0))
	health_panel.position = safe_rect.position + Vector2(20.0, 20.0)
	health_panel.size = Vector2(health_width, 80.0)
	health_bar.custom_minimum_size.x = minf(220.0, health_width - 32.0)

	exit_button.custom_minimum_size = Vector2(112.0, 48.0)
	exit_button.size = exit_button.custom_minimum_size
	exit_button.position = Vector2(
		safe_rect.position.x + 20.0,
		health_panel.position.y + health_panel.size.y + 8.0
	)
	pause_button.custom_minimum_size = Vector2(112.0, 48.0)
	pause_button.size = pause_button.custom_minimum_size
	var pause_position := Vector2(
		exit_button.position.x + exit_button.size.x + 8.0,
		exit_button.position.y
	)
	if pause_position.x + pause_button.size.x > safe_rect.end.x - 12.0:
		pause_position.x = exit_button.position.x
		pause_position.y += exit_button.size.y + 8.0
	pause_button.position = pause_position
	_position_context_action_button(safe_rect)

	if is_instance_valid(objective_panel):
		var objective_width := minf(360.0, maxf(280.0, safe_rect.size.x - 32.0))
		var center_delta_x := safe_rect.get_center().x - viewport_size.x * 0.5
		objective_panel.offset_left = center_delta_x - objective_width * 0.5
		objective_panel.offset_right = center_delta_x + objective_width * 0.5
		objective_panel.offset_top = safe_rect.position.y + 20.0
		objective_panel.offset_bottom = safe_rect.position.y + 115.0
		objective_bar.custom_minimum_size.x = objective_width - 40.0

	if is_instance_valid(_minimap):
		_minimap.apply_safe_area(safe_rect, viewport_size)

	if is_instance_valid(_performance_panel):
		_performance_panel.anchor_left = 1.0
		_performance_panel.anchor_right = 1.0
		_performance_panel.anchor_top = 0.0
		_performance_panel.anchor_bottom = 0.0
		_performance_panel.offset_right = (
			safe_rect.end.x - viewport_size.x - 16.0
		)
		_performance_panel.offset_left = (
			_performance_panel.offset_right - 260.0
		)
		_performance_panel.offset_top = safe_rect.position.y + 310.0
		_performance_panel.offset_bottom = (
			_performance_panel.offset_top + 96.0
		)

	if is_instance_valid(notification_box):
		var center_delta_x := safe_rect.get_center().x - viewport_size.x * 0.5
		notification_box.offset_left = center_delta_x - 280.0
		notification_box.offset_right = center_delta_x + 280.0
		notification_box.offset_top = safe_rect.end.y - viewport_size.y - 176.0
		notification_box.offset_bottom = safe_rect.end.y - viewport_size.y - 96.0


func _setup_command_button(button: Button, icon: Texture2D, label_text: String) -> void:
	button.text = ""
	button.tooltip_text = label_text
	button.custom_minimum_size = Vector2(108.0, 108.0)
	button.add_theme_font_size_override("font_size", 12)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4.0
	content.offset_top = 4.0
	content.offset_right = -4.0
	content.offset_bottom = -4.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var icon_rect := TextureRect.new()
	icon_rect.texture = icon
	icon_rect.custom_minimum_size = Vector2(32.0, 32.0)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_rect)

	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.98, 0.91, 0.93))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)


func _make_command_style(active: bool, state: String) -> StyleBoxFlat:
	var background := Color(0.55, 0.12, 0.20, 0.94)
	var border := Color(0.75, 0.88, 1.0, 0.9)
	var border_width := 2
	if active:
		background = Color(0.72, 0.16, 0.25, 1.0)
		border = Color(1.0, 0.78, 0.42, 1.0)
		border_width = 4
	if state == "hover":
		background = background.lightened(0.12)
	if state == "pressed":
		background = background.darkened(0.18)
	if state == "disabled":
		background = Color(0.16, 0.08, 0.10, 0.65)
		border = Color(0.35, 0.28, 0.30, 0.55)
		border_width = 2

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(54)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _refresh_command_button_styles() -> void:
	var buttons: Array[Button] = [follow_button, capture_button, defend_button]
	var commands: Array[String] = ["follow", "capture", "defend"]
	for index in range(buttons.size()):
		var button := buttons[index]
		var active := commands[index] == _active_command
		button.add_theme_stylebox_override("normal", _make_command_style(active, "normal"))
		button.add_theme_stylebox_override("hover", _make_command_style(active, "hover"))
		button.add_theme_stylebox_override("pressed", _make_command_style(active, "pressed"))
		button.add_theme_stylebox_override("disabled", _make_command_style(false, "disabled"))
		button.add_theme_stylebox_override("focus", _make_command_style(active, "hover"))


func _set_active_command(command: String) -> void:
	_active_command = command
	_refresh_command_button_styles()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.set_active_command(command)


func _create_context_action_button() -> void:
	context_action_button = Button.new()
	context_action_button.name = "ContextActionButton"
	context_action_button.text = ""
	context_action_button.custom_minimum_size = Vector2(108.0, 108.0)
	context_action_button.pressed.connect(_on_context_action_button_pressed)
	add_child(context_action_button)

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4.0
	content.offset_top = 4.0
	content.offset_right = -4.0
	content.offset_bottom = -4.0
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 1)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	context_action_button.add_child(content)

	_context_button_icon = TextureRect.new()
	_context_button_icon.texture = JOIN_ATTACK_ICON
	_context_button_icon.custom_minimum_size = Vector2(30.0, 30.0)
	_context_button_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_context_button_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_context_button_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_context_button_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_context_button_icon)

	_context_button_label = Label.new()
	_context_button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_button_label.add_theme_font_size_override("font_size", 12)
	_context_button_label.add_theme_color_override("font_color", Color(0.98, 0.91, 0.93))
	_context_button_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_context_button_label)
	_refresh_context_action_button()


func _position_context_action_button(safe_rect: Rect2) -> void:
	if not is_instance_valid(context_action_button):
		return

	var layout := GameManager.get_mobile_control_layout()
	var entry: Dictionary = layout.get("infect", GameManager.DEFAULT_CONTROL_LAYOUT["infect"])
	var scale_value: float = clampf(float(entry.get("scale", 1.0)), 0.65, 1.5)
	var button_size := Vector2(108.0, 108.0) * scale_value
	_context_button_opacity = clampf(float(entry.get("opacity", 0.85)), 0.3, 1.0)
	var normalized_position: Vector2 = entry.get("position", Vector2(0.9, 0.8))
	var center := safe_rect.position + normalized_position * safe_rect.size
	var half_size := button_size * 0.5
	center.x = clampf(center.x, safe_rect.position.x + half_size.x, safe_rect.end.x - half_size.x)
	center.y = clampf(center.y, safe_rect.position.y + half_size.y, safe_rect.end.y - half_size.y)
	context_action_button.position = center - half_size
	context_action_button.size = button_size
	_refresh_context_action_button()


func _make_context_action_style(
	join_attack: bool,
	state: String,
	radius: int,
	opacity: float
) -> StyleBoxFlat:
	var background := Color(0.55, 0.12, 0.20, opacity)
	var border := Color(0.95, 0.58, 0.64, 0.95)
	if join_attack:
		background = Color(0.78, 0.34, 0.06, opacity)
		border = Color(1.0, 0.76, 0.30, 1.0)
	if state == "hover":
		background = background.lightened(0.12)
	elif state == "pressed":
		background = background.darkened(0.18)
	elif state == "disabled":
		background = Color(0.16, 0.08, 0.10, 0.65)
		border = Color(0.35, 0.28, 0.30, 0.55)

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _refresh_context_action_button() -> void:
	if not is_instance_valid(context_action_button):
		return

	if is_instance_valid(_context_button_icon):
		_context_button_icon.visible = _context_is_join_attack
	if is_instance_valid(_context_button_label):
		_context_button_label.text = "JOIN ATTACK" if _context_is_join_attack else "INFECT"
		_context_button_label.add_theme_font_size_override(
			"font_size",
			10 if _context_is_join_attack else 12
		)
	context_action_button.tooltip_text = "JOIN ATTACK" if _context_is_join_attack else "INFECT"
	var radius: int = roundi(context_action_button.size.x * 0.5)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		context_action_button.add_theme_stylebox_override(
			state,
			_make_context_action_style(
				_context_is_join_attack,
				state,
				radius,
				_context_button_opacity
			)
		)


func _set_context_action_mode(join_attack: bool) -> void:
	if _context_is_join_attack == join_attack:
		return
	_context_is_join_attack = join_attack
	if is_instance_valid(_mobile_controls):
		_mobile_controls.set_context_action(join_attack)
	_refresh_context_action_button()


func _find_nearby_infectable_cell(player: Node2D) -> Node2D:
	for node in get_tree().get_nodes_in_group("host_cells"):
		if not is_instance_valid(node) or not node.has_method("can_player_enter"):
			continue
		if node.can_player_enter(player):
			return node as Node2D
	return null


func _find_nearest_join_target(player: Node2D) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = INF
	var visited: Dictionary = {}

	for group_name in ENEMY_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not node is Node2D:
				continue
			var instance_id: int = node.get_instance_id()
			if visited.has(instance_id):
				continue
			visited[instance_id] = true
			if (
				node.get("defeated") == true
				or not node.has_method("can_player_join")
				or not node.has_method("set_player_assisting")
				or not node.can_player_join()
			):
				continue

			var candidate := node as Node2D
			var distance := player.global_position.distance_to(candidate.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
	return nearest


func _can_keep_join_target(player: Node2D, target: Node2D) -> bool:
	return (
		is_instance_valid(target)
		and player.visible
		and target.get("defeated") != true
		and target.has_method("set_player_assisting")
		and target.has_method("is_restrained")
		and target.is_restrained()
	)


func update_context_action(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(player) or not player.visible:
		nearby_target = null
		_join_target_lost_time = 0.0
		_set_context_action_mode(false)
		return

	if is_instance_valid(_find_nearby_infectable_cell(player)):
		nearby_target = null
		_join_target_lost_time = 0.0
		_set_context_action_mode(false)
		return

	var current_target := _find_nearest_join_target(player)
	if is_instance_valid(current_target):
		nearby_target = current_target
		_join_target_lost_time = 0.0
		_set_context_action_mode(true)
		return

	if _can_keep_join_target(player, nearby_target):
		_join_target_lost_time += delta
		if _join_target_lost_time < 0.2:
			_set_context_action_mode(true)
			return

	nearby_target = null
	_join_target_lost_time = 0.0
	_set_context_action_mode(false)


func _on_context_action_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(player) and player.has_method("perform_context_interaction"):
		player.perform_context_interaction()


func perform_join_attack(player: Node2D) -> bool:
	if not is_instance_valid(player) or not player.visible:
		return false
	if is_instance_valid(_find_nearby_infectable_cell(player)):
		return false

	var target := _find_nearest_join_target(player)
	if not is_instance_valid(target) or not target.can_player_join():
		return false

	target.set_player_assisting(true)
	if target.get("player_assisting") != true:
		return false

	nearby_target = target
	_join_target_lost_time = 0.0
	_set_context_action_mode(true)
	return true


func _on_pause_button_pressed() -> void:
	_open_pause_menu()


func _open_pause_menu() -> void:
	if is_instance_valid(_pause_overlay) or is_instance_valid(_exit_dialog):
		return

	var in_multiplayer: bool = MultiplayerSession.is_session_active
	_pause_game_if_singleplayer()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.suspend_input(true)

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	var panel_width: float = minf(460.0, maxf(280.0, safe_rect.size.x - 32.0))
	var panel_height: float = minf(390.0, maxf(320.0, safe_rect.size.y - 32.0))
	var overlay := Control.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 100
	add_child(overlay)
	_pause_overlay = overlay

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.76)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(backdrop)

	var panel := PanelContainer.new()
	var panel_size := Vector2(panel_width, panel_height)
	panel.position = safe_rect.get_center() - panel_size * 0.5
	panel.size = panel_size
	panel.add_theme_stylebox_override(
		"panel",
		UIThemeHelper.create_panel_style(Color(0.10, 0.03, 0.06, 0.98), Color(0.78, 0.25, 0.36, 0.95), 14)
	)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 8)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)

	var message := Label.new()
	message.text = (
		"Multiplayer continues while this menu is open. Restart is unavailable."
		if in_multiplayer
		else "The current level is paused."
	)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.y = 42.0
	message.add_theme_font_size_override("font_size", 14)
	layout.add_child(message)

	var resume_button := _create_pause_menu_button("RESUME", true)
	resume_button.pressed.connect(_on_resume_button_pressed)
	layout.add_child(resume_button)

	var restart_button := _create_pause_menu_button("RESTART LEVEL")
	restart_button.disabled = in_multiplayer
	restart_button.pressed.connect(_on_restart_level_button_pressed)
	layout.add_child(restart_button)

	var main_menu_button := _create_pause_menu_button("MAIN MENU")
	main_menu_button.pressed.connect(_on_pause_main_menu_button_pressed)
	layout.add_child(main_menu_button)


func _create_pause_menu_button(label: String, is_accent: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.style_button(button, is_accent)
	return button


func _pause_game_if_singleplayer() -> void:
	if MultiplayerSession.is_session_active:
		return
	get_tree().paused = true
	_paused_by_hud = true


func _resume_game_if_paused_by_hud() -> void:
	if not _paused_by_hud:
		return
	get_tree().paused = false
	_paused_by_hud = false


func _close_pause_menu() -> void:
	if not is_instance_valid(_pause_overlay):
		return
	var overlay := _pause_overlay
	_pause_overlay = null
	_resume_game_if_paused_by_hud()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.suspend_input(false)
	overlay.queue_free()


func _on_resume_button_pressed() -> void:
	_close_pause_menu()


func _on_restart_level_button_pressed() -> void:
	if MultiplayerSession.is_session_active or not is_instance_valid(_pause_overlay):
		return
	_close_pause_menu()
	if not GameManager.reload_current_level():
		push_error("HUD: Could not restart the current level.")


func _on_pause_main_menu_button_pressed() -> void:
	if not is_instance_valid(_pause_overlay):
		return
	_close_pause_menu()
	if MultiplayerSession.is_session_active:
		MultiplayerSession.cancel_session()
	GameManager.load_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_F3
	):
		performance_diagnostics_enabled = not performance_diagnostics_enabled
		if is_instance_valid(_performance_panel):
			_performance_panel.visible = performance_diagnostics_enabled
		_diagnostics_update_timer = 0.0
		get_viewport().set_input_as_handled()
		return

	if not event.is_action_pressed("ui_cancel"):
		return
	_handle_pause_input()
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_pause_input()


func _handle_pause_input() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_pause_input_msec < 200:
		return
	_last_pause_input_msec = now_msec

	if is_instance_valid(_exit_dialog):
		_on_exit_cancelled()
	elif is_instance_valid(_pause_overlay):
		_close_pause_menu()
	elif TutorialManager.is_tutorial_active():
		TutorialManager.skip_tutorial()
	else:
		_open_pause_menu()


func _on_exit_button_pressed() -> void:
	if is_instance_valid(_exit_dialog) or is_instance_valid(_pause_overlay):
		return

	_pause_game_if_singleplayer()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.suspend_input(true)
	_exit_dialog = ConfirmationDialog.new()
	_exit_dialog.title = "Confirm Exit"
	_exit_dialog.dialog_text = EXIT_CONFIRMATION_TEXT
	_exit_dialog.ok_button_text = "EXIT"
	_exit_dialog.cancel_button_text = "CANCEL"
	_exit_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_exit_dialog.confirmed.connect(_on_exit_confirmed)
	_exit_dialog.canceled.connect(_on_exit_cancelled)
	_exit_dialog.close_requested.connect(_on_exit_cancelled)

	var cancel_button := _exit_dialog.get_cancel_button()
	cancel_button.custom_minimum_size = Vector2(112.0, 48.0)
	UIThemeHelper.style_button(cancel_button, false)

	var confirm_button := _exit_dialog.get_ok_button()
	confirm_button.custom_minimum_size = Vector2(112.0, 48.0)
	UIThemeHelper.style_button(confirm_button, true)

	get_tree().root.add_child(_exit_dialog)
	_exit_dialog.popup_centered(Vector2i(460, 190))


func _on_exit_cancelled() -> void:
	_close_exit_dialog()


func _on_exit_confirmed() -> void:
	_close_exit_dialog()
	if MultiplayerSession.is_session_active:
		MultiplayerSession.cancel_session()
	GameManager.load_main_menu()


func _close_exit_dialog() -> void:
	_resume_game_if_paused_by_hud()
	if is_instance_valid(_mobile_controls):
		_mobile_controls.suspend_input(false)
	if is_instance_valid(_exit_dialog):
		_exit_dialog.queue_free()
	_exit_dialog = null


func _exit_tree() -> void:
	if _paused_by_hud:
		get_tree().paused = false
		_paused_by_hud = false
	if is_instance_valid(_exit_dialog):
		_exit_dialog.queue_free()
		_exit_dialog = null


func _process(delta: float) -> void:
	_context_scan_timer += delta
	if _context_scan_timer >= CONTEXT_SCAN_INTERVAL:
		var elapsed: float = _context_scan_timer
		_context_scan_timer = 0.0
		update_context_action(elapsed)

	if not performance_diagnostics_enabled:
		return

	_diagnostics_update_timer -= delta
	if _diagnostics_update_timer <= 0.0:
		_diagnostics_update_timer = DIAGNOSTICS_UPDATE_INTERVAL
		_update_performance_diagnostics()


func _create_performance_diagnostics() -> void:
	_performance_panel = PanelContainer.new()
	_performance_panel.name = "PerformanceDiagnostics"
	_performance_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_performance_panel.visible = performance_diagnostics_enabled

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.025, 0.045, 0.88)
	panel_style.border_color = Color(0.68, 0.33, 0.50, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(5)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_top = 5.0
	panel_style.content_margin_bottom = 5.0
	_performance_panel.add_theme_stylebox_override("panel", panel_style)

	_performance_label = Label.new()
	_performance_label.name = "Readout"
	_performance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_performance_label.add_theme_font_size_override("font_size", 12)
	_performance_label.add_theme_color_override(
		"font_color",
		Color(0.94, 0.91, 0.95)
	)
	_performance_panel.add_child(_performance_label)
	add_child(_performance_panel)


func _update_performance_diagnostics() -> void:
	if not is_instance_valid(_performance_label):
		return

	var enemy_count: int = (
		get_tree().get_nodes_in_group("immune_cells").size()
		+ get_tree().get_nodes_in_group("nkt_cells").size()
	)
	var minion_count: int = get_tree().get_nodes_in_group("minions").size()
	var particle_count: int = (
		get_tree().get_nodes_in_group("cytokine_particles").size()
	)
	var frame_time_ms: float = (
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	)
	var memory_mb: float = (
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	)

	_performance_label.text = (
		"FPS: %d  Frame: %.2f ms\n"
		+ "Enemies: %d  Minions: %d\n"
		+ "Cytokine particles: %d\n"
		+ "Memory: %.1f MB"
	) % [
		Engine.get_frames_per_second(),
		frame_time_ms,
		enemy_count,
		minion_count,
		particle_count,
		memory_mb,
	]


func update_player_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

	health_label.text = "VIRUS HEALTH: %d / %d" % [
		current,
		maximum
	]


# FOLLOW COMMAND
func _on_follow_button_pressed() -> void:
	_set_active_command("follow")
	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(0)

	print("Follow command issued to %d minions." % minions.size())


# CAPTURE COMMAND
func _on_capture_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		print("Cannot capture: Player not found.")
		return

	var selected_target := _find_nearest_active_target(player)

	if not is_instance_valid(selected_target):
		print("No available enemies to capture.")
		return

	_set_active_command("capture")
	var minions := get_tree().get_nodes_in_group("minions")
	var assigned_count: int = 0

	# Assign the exact same target to every minion.
	for minion in minions:
		if not is_instance_valid(minion):
			continue

		if minion.has_method("set_capture_target"):
			minion.set_capture_target(selected_target)
			assigned_count += 1

	var target_kind := (
		"Neutrophil"
		if selected_target.is_in_group("neutrophils")
		else ("NKT cell" if selected_target.is_in_group("nkt_cells") else "immune cell")
	)
	print(
		"Capture command: %d minions assigned to %s (%s)."
		% [assigned_count, selected_target.name, target_kind]
	)


func _find_nearest_active_target(player: Node2D) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = INF

	for group_name in ENEMY_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node) or not node is Node2D:
				continue
			if node.get("defeated") == true or not node.has_method("take_damage"):
				continue

			var candidate := node as Node2D
			var distance := player.global_position.distance_to(
				candidate.global_position
			)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = candidate

	return nearest


# DEFEND COMMAND
func _on_defend_button_pressed() -> void:
	_set_active_command("defend")
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		return

	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(2, player.global_position)

	print("Defend command issued to %d minions." % minions.size())


# OBJECTIVE DISPLAY
func create_objective_display() -> void:
	objective_panel = PanelContainer.new()
	objective_panel.name = "ObjectivePanel"

	objective_panel.anchor_left = 0.5
	objective_panel.anchor_right = 0.5
	objective_panel.anchor_top = 0.0
	objective_panel.anchor_bottom = 0.0

	objective_panel.offset_left = -180
	objective_panel.offset_right = 180
	objective_panel.offset_top = 20
	objective_panel.offset_bottom = 115

	add_child(objective_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	objective_panel.add_child(layout)

	objective_label = Label.new()
	objective_label.text = "MISSION OBJECTIVE"
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(objective_label)

	objective_bar = ProgressBar.new()
	objective_bar.min_value = 0
	objective_bar.max_value = 1
	objective_bar.value = 0
	objective_bar.show_percentage = false
	objective_bar.custom_minimum_size = Vector2(320, 14)
	layout.add_child(objective_bar)

	objective_status = Label.new()
	objective_status.text = "Exit locked: eliminate all " + objective_name + "."
	objective_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(objective_status)


# General objective display: an explicit title line, a status line, and a
# progress bar. Lets a level drive a multi-stage objective (see Level 2).
func set_objective(title: String, status: String, current: int, total: int) -> void:
	if not is_instance_valid(objective_panel):
		return

	objective_bar.max_value = maxi(total, 1)
	objective_bar.value = current
	objective_label.text = title
	objective_status.text = status


func update_level_objective(defeated_count: int, total_count: int, custom_name: String = "NEUTROPHILS") -> void:
	var title := "%s: %d / %d" % [custom_name, defeated_count, total_count]

	if defeated_count >= total_count:
		set_objective(title, "EXIT UNLOCKED! Reach the exit.", defeated_count, total_count)
	else:
		set_objective(title, "Exit locked: eliminate all " + custom_name + ".", defeated_count, total_count)


# --------------------------------------------------------------------------
# Brief gameplay notifications (Level 4 NKT feedback)
# --------------------------------------------------------------------------

func create_notification_display() -> void:
	notification_box = VBoxContainer.new()
	notification_box.name = "Notifications"
	notification_box.anchor_left = 0.5
	notification_box.anchor_right = 0.5
	notification_box.anchor_top = 1.0
	notification_box.anchor_bottom = 1.0
	notification_box.offset_left = -280.0
	notification_box.offset_right = 280.0
	notification_box.offset_top = -176.0
	notification_box.offset_bottom = -96.0
	notification_box.alignment = BoxContainer.ALIGNMENT_END
	notification_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_box.add_theme_constant_override("separation", 2)
	add_child(notification_box)


## Short, throttled message near the bottom of the screen. Reusing the same
## text within a few seconds is dropped so several NKT cells cannot spam it.
func show_notification(text: String, color: Color = Color(1.0, 0.85, 0.45)) -> void:
	if not is_instance_valid(notification_box):
		create_notification_display()

	if not is_instance_valid(notification_box):
		return

	var now := float(Time.get_ticks_msec()) / 1000.0
	if _notification_cooldowns.has(text):
		if now - float(_notification_cooldowns[text]) < 3.0:
			return
	_notification_cooldowns[text] = now

	# Keep at most four messages alive at once.
	while notification_box.get_child_count() >= 4:
		var oldest := notification_box.get_child(0)
		notification_box.remove_child(oldest)
		oldest.queue_free()

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_box.add_child(label)

	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)
