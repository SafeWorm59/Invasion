extends Control

const MenuBackground := preload("res://scripts/menu_background.gd")
const UISafeArea := preload("res://scripts/ui_safe_area.gd")

var _ip_input: LineEdit
var _status_label: Label
var _center: CenterContainer
var _panel: PanelContainer
var _title_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	MultiplayerSession.status_changed.connect(_on_status_changed)
	var previous_error := MultiplayerSession.consume_last_connection_error()
	if previous_error.is_empty():
		_status_label.text = "Host a LAN game or enter the PC host's LAN IPv4 address."
	else:
		_on_status_changed(previous_error, true)
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


func _build_ui() -> void:
	var background := MenuBackground.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(460.0, 0.0)
	_panel.add_theme_stylebox_override(
		"panel",
		UIThemeHelper.create_panel_style(Color(0.08, 0.025, 0.045, 0.97), Color(0.85, 0.25, 0.38, 0.9), 12)
	)
	_center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)

	_title_label = Label.new()
	_title_label.text = "MULTIPLAYER"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 26)
	column.add_child(_title_label)

	var help := Label.new()
	help.text = "LAN games use UDP port %d." % MultiplayerSession.PORT
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.add_theme_font_size_override("font_size", 14)
	column.add_child(help)

	var host_button := _make_button("HOST GAME", true)
	host_button.pressed.connect(_on_host_pressed)
	column.add_child(host_button)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	column.add_child(join_row)

	_ip_input = LineEdit.new()
	_ip_input.placeholder_text = "PC host LAN IPv4, e.g. 192.168.1.25"
	_ip_input.text = ""
	_ip_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_input.custom_minimum_size.y = 48.0
	join_row.add_child(_ip_input)

	var join_button := _make_button("JOIN", false)
	join_button.custom_minimum_size.x = 100.0
	join_button.pressed.connect(_on_join_pressed)
	join_row.add_child(join_button)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	var back_button := _make_button("BACK", false)
	back_button.pressed.connect(_on_back_pressed)
	column.add_child(back_button)


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	UISafeArea.fit_to_safe_rect(_center, safe_rect, viewport_size, 12.0)
	var panel_width := minf(460.0, maxf(280.0, safe_rect.size.x - 24.0))
	_panel.custom_minimum_size.x = panel_width
	_title_label.add_theme_font_size_override("font_size", maxi(20, roundi(26.0 * minf(panel_width / 460.0, 1.0))))


func _make_button(text: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48.0
	UIThemeHelper.style_button(button, accent)
	return button


func _on_host_pressed() -> void:
	var err := MultiplayerSession.host_game()
	if err != OK:
		_on_status_changed("Could not start host (error %d)." % err, true)


func _on_join_pressed() -> void:
	MultiplayerSession.join_game(_ip_input.text.strip_edges())


func _on_back_pressed() -> void:
	MultiplayerSession.cancel_session()
	GameManager.load_main_menu()


func _on_status_changed(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.38, 0.38) if is_error else Color(0.82, 0.94, 0.88)
	)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
