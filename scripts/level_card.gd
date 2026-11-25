class_name LevelCard
extends PanelContainer

signal level_selected(level_data: Dictionary)
signal level_launched(level_id: int)

var level_data: Dictionary = {}
var is_active_selection: bool = false

@onready var number_label: Label = $VBoxContainer/HeaderBox/NumberLabel
@onready var status_badge: Label = $VBoxContainer/HeaderBox/StatusBadge
@onready var preview_container: MarginContainer = $VBoxContainer/PreviewContainer
@onready var preview_rect: Control = $VBoxContainer/PreviewContainer/PreviewDraw
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var desc_label: Label = $VBoxContainer/DescLabel
@onready var action_button: Button = $VBoxContainer/ActionButton


func _ready() -> void:
	custom_minimum_size = Vector2(230, 420)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_button.pressed.connect(_on_action_button_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

	if not level_data.is_empty():
		refresh_ui()


func setup(data: Dictionary) -> void:
	level_data = data
	if is_inside_tree():
		refresh_ui()


func set_responsive_size(card_width: float, card_height: float) -> void:
	custom_minimum_size = Vector2(card_width, card_height)
	preview_container.custom_minimum_size.x = maxf(120.0, card_width - 32.0)
	action_button.custom_minimum_size.y = 48.0


func refresh_ui() -> void:
	if level_data.is_empty():
		return

	var lvl_id: int = level_data.get("id", 0)
	var lvl_name: String = level_data.get("name", "LEVEL")
	var lvl_desc: String = level_data.get("description", "")
	var is_locked: bool = level_data.get("locked", true)
	var accent: Color = level_data.get("accent_color", Color(0.8, 0.3, 0.4))

	number_label.text = "PHASE %02d" % lvl_id
	title_label.text = lvl_name
	desc_label.text = lvl_desc

	if is_locked:
		status_badge.text = "LOCKED"
		status_badge.add_theme_color_override("font_color", Color(0.65, 0.50, 0.50, 0.8))
		action_button.text = "LOCKED"
		action_button.disabled = true
		UIThemeHelper.style_button(action_button, false)
		modulate = Color(0.7, 0.65, 0.70, 0.65)
	else:
		status_badge.text = "AVAILABLE"
		status_badge.add_theme_color_override("font_color", Color(0.35, 0.95, 0.60, 1.0))
		action_button.text = "INFILTRATE"
		action_button.disabled = false
		UIThemeHelper.style_button(action_button, true)
		modulate = Color.WHITE

	update_card_style()
	preview_rect.queue_redraw()


func update_card_style() -> void:
	var is_locked: bool = level_data.get("locked", true)
	var bg_color := Color(0.12, 0.04, 0.07, 0.92) if not is_locked else Color(0.08, 0.04, 0.06, 0.75)
	var border_color: Color

	if is_active_selection and not is_locked:
		border_color = Color(1.0, 0.45, 0.60, 1.0)
	elif not is_locked:
		border_color = Color(0.65, 0.20, 0.30, 0.8)
	else:
		border_color = Color(0.30, 0.18, 0.22, 0.5)

	var style := UIThemeHelper.create_panel_style(bg_color, border_color, 10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	if is_active_selection:
		style.set_border_width_all(3)
		style.shadow_color = Color(0.9, 0.2, 0.4, 0.4)
		style.shadow_size = 12

	add_theme_stylebox_override("panel", style)


func set_selected(selected: bool) -> void:
	is_active_selection = selected
	update_card_style()


func _on_action_button_pressed() -> void:
	if not level_data.get("locked", true):
		level_selected.emit(level_data)
		level_launched.emit(level_data.get("id", 0))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		level_selected.emit(level_data)
		if not level_data.get("locked", true):
			set_selected(true)


func _on_mouse_entered() -> void:
	if not level_data.get("locked", true):
		var tw := create_tween()
		tw.tween_property(self, "position:y", position.y - 6, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_mouse_exited() -> void:
	if not level_data.get("locked", true):
		var tw := create_tween()
		tw.tween_property(self, "position:y", position.y + 6, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
