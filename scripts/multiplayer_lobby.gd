extends Control

const MenuBackground := preload("res://scripts/menu_background.gd")
const UISafeArea := preload("res://scripts/ui_safe_area.gd")

var _count_label: Label
var _host_address_label: Label
var _roster: VBoxContainer
var _level_option: OptionButton
var _start_button: Button
var _status_label: Label
var _center: CenterContainer
var _panel: PanelContainer
var _title_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_populate_levels()
	MultiplayerSession.roster_changed.connect(_refresh_roster)
	MultiplayerSession.status_changed.connect(_on_status_changed)
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()
	_refresh_roster()
	if MultiplayerSession.is_host:
		var host_addresses := MultiplayerSession.get_local_ipv4_addresses()
		if host_addresses.is_empty():
			_host_address_label.text = "No non-loopback IPv4 address found. Connect the PC to Wi-Fi or Ethernet."
			_status_label.text = "The server is listening, but clients need a reachable PC LAN IPv4 address."
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.38))
		else:
			_host_address_label.text = "PC IPv4 addresses (use one on the same LAN):\n%s\nUDP port %d." % [
				", ".join(host_addresses),
				MultiplayerSession.PORT,
			]
			_status_label.text = "Waiting for players. Allow inbound UDP %d in Windows Firewall." % MultiplayerSession.PORT
	else:
		_host_address_label.visible = false
		_status_label.text = "Connected. Waiting for the host to start."


func _build_ui() -> void:
	var background := MenuBackground.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(520.0, 0.0)
	_panel.add_theme_stylebox_override(
		"panel",
		UIThemeHelper.create_panel_style(Color(0.08, 0.025, 0.045, 0.97), Color(0.35, 0.9, 0.7, 0.85), 12)
	)
	_center.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)

	_title_label = Label.new()
	_title_label.text = "MULTIPLAYER LOBBY"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 25)
	column.add_child(_title_label)

	_count_label = Label.new()
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.add_theme_font_size_override("font_size", 18)
	column.add_child(_count_label)

	_host_address_label = Label.new()
	_host_address_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_host_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_host_address_label)

	var roster_panel := PanelContainer.new()
	roster_panel.add_theme_stylebox_override(
		"panel",
		UIThemeHelper.create_panel_style(Color(0.04, 0.06, 0.08, 0.78), Color(0.45, 0.62, 0.68, 0.55), 8)
	)
	column.add_child(roster_panel)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 5)
	roster_panel.add_child(_roster)

	_level_option = OptionButton.new()
	_level_option.custom_minimum_size.y = 48.0
	column.add_child(_level_option)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)

	_start_button = _make_button("START MATCH", true)
	_start_button.pressed.connect(_on_start_pressed)
	actions.add_child(_start_button)

	var leave_button := _make_button("LEAVE", false)
	leave_button.pressed.connect(MultiplayerSession.leave_session)
	actions.add_child(leave_button)


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	UISafeArea.fit_to_safe_rect(_center, safe_rect, viewport_size, 12.0)
	var panel_width := minf(520.0, maxf(300.0, safe_rect.size.x - 24.0))
	_panel.custom_minimum_size.x = panel_width
	_title_label.add_theme_font_size_override("font_size", maxi(20, roundi(25.0 * minf(panel_width / 520.0, 1.0))))


func _populate_levels() -> void:
	_level_option.clear()
	for level in GameManager.get_levels():
		if bool(level.get("locked", false)):
			continue
		var scene_path := String(level.get("scene_path", ""))
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			continue
		var level_id := int(level.get("id", 0))
		_level_option.add_item(String(level.get("name", "LEVEL %d" % level_id)), level_id)
		_level_option.set_item_metadata(_level_option.item_count - 1, scene_path)

	_level_option.disabled = not MultiplayerSession.is_host
	_start_button.disabled = not MultiplayerSession.is_host or _level_option.get_item_count() == 0


func _refresh_roster() -> void:
	if not is_instance_valid(_roster):
		return

	for child in _roster.get_children():
		_roster.remove_child(child)
		child.queue_free()

	var peer_ids := MultiplayerSession.get_lobby_peer_ids()
	_count_label.text = "Players: %d / %d" % [peer_ids.size(), MultiplayerSession.MAX_PLAYERS]
	for peer_id in peer_ids:
		var player_label := Label.new()
		player_label.text = "Player %d%s" % [
			peer_id,
			" (Host)" if peer_id == 1 else (" (You)" if peer_id == multiplayer.get_unique_id() else ""),
		]
		_roster.add_child(player_label)


func _on_start_pressed() -> void:
	if not MultiplayerSession.is_host or _level_option.get_item_count() == 0:
		return
	var selected_index := _level_option.get_selected()
	if selected_index < 0:
		return
	var scene_path := String(_level_option.get_item_metadata(selected_index))
	MultiplayerSession.start_match(scene_path)


func _on_status_changed(message: String, is_error: bool) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = message
	_status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.38, 0.38) if is_error else Color(0.82, 0.94, 0.88)
	)


func _make_button(text: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190.0, 48.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIThemeHelper.style_button(button, accent)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		MultiplayerSession.leave_session()
