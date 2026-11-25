extends Control

const MobileLayoutEditorScript := preload("res://scripts/mobile_layout_editor.gd")
const UISafeArea := preload("res://scripts/ui_safe_area.gd")

@onready var content_layer: CenterContainer = $ContentLayer
@onready var main_margin: MarginContainer = $ContentLayer/MainMargin
@onready var main_vbox: VBoxContainer = $ContentLayer/MainMargin/MainVBox
@onready var title_container: VBoxContainer = $ContentLayer/MainMargin/MainVBox/TitleContainer
@onready var status_badge: Label = $ContentLayer/MainMargin/MainVBox/TitleContainer/StatusBadge
@onready var button_container: VBoxContainer = $ContentLayer/MainMargin/MainVBox/ButtonContainer

@onready var play_button: Button = $ContentLayer/MainMargin/MainVBox/ButtonContainer/PlayButton
@onready var multiplayer_button: Button = $ContentLayer/MainMargin/MainVBox/ButtonContainer/MultiplayerButton
@onready var level_select_button: Button = $ContentLayer/MainMargin/MainVBox/ButtonContainer/LevelSelectButton
@onready var settings_button: Button = $ContentLayer/MainMargin/MainVBox/ButtonContainer/SettingsButton
@onready var credits_button: Button = $ContentLayer/MainMargin/MainVBox/ButtonContainer/CreditsButton
@onready var quit_button: Button = $ContentLayer/MainMargin/MainVBox/ButtonContainer/QuitButton

@onready var title_label: Label = $ContentLayer/MainMargin/MainVBox/TitleContainer/TitleLabel
@onready var subtitle_label: Label = $ContentLayer/MainMargin/MainVBox/TitleContainer/SubtitleLabel

@onready var modal_overlay: ColorRect = $ModalOverlay
@onready var settings_menu: SettingsMenu = $ModalOverlay/SettingsMenu
@onready var credits_menu: CreditsMenu = $ModalOverlay/CreditsMenu
var layout_editor: MobileLayoutEditor


func _ready() -> void:
	# Style buttons
	UIThemeHelper.style_button(play_button, true) # Prominent accent button
	UIThemeHelper.style_button(multiplayer_button, false)
	UIThemeHelper.style_button(level_select_button, false)
	UIThemeHelper.style_button(settings_button, false)
	UIThemeHelper.style_button(credits_button, false)
	UIThemeHelper.style_button(quit_button, false)

	# Connect button events
	play_button.pressed.connect(_on_play_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	level_select_button.pressed.connect(_on_level_select_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Connect modal events
	settings_menu.closed.connect(_close_modals)
	settings_menu.customize_controls_requested.connect(_open_layout_editor)
	credits_menu.closed.connect(_close_modals)

	get_viewport().size_changed.connect(_fit_menu_to_viewport)
	_fit_menu_to_viewport()
	_close_modals()
	start_title_pulse()


func _fit_menu_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	UISafeArea.fit_to_safe_rect(content_layer, safe_rect, viewport_size)

	var content_width := minf(560.0, maxf(240.0, safe_rect.size.x - 24.0))
	var ui_scale := clampf(minf(safe_rect.size.x / 1280.0, safe_rect.size.y / 720.0), 0.7, 1.0)
	main_margin.custom_minimum_size.x = content_width
	button_container.custom_minimum_size.x = 0.0
	button_container.add_theme_constant_override("separation", maxi(8, roundi(12.0 * ui_scale)))
	main_vbox.add_theme_constant_override("separation", maxi(14, roundi(28.0 * ui_scale)))
	title_container.add_theme_constant_override("separation", maxi(3, roundi(4.0 * ui_scale)))
	status_badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_badge.add_theme_font_size_override("font_size", maxi(10, roundi(12.0 * ui_scale)))
	title_label.add_theme_font_size_override("font_size", maxi(32, roundi(56.0 * ui_scale)))
	subtitle_label.add_theme_font_size_override("font_size", maxi(12, roundi(16.0 * ui_scale)))

	var button_width := minf(280.0, maxf(200.0, content_width - 64.0))
	var buttons: Array[Button] = [
		play_button,
		multiplayer_button,
		level_select_button,
		settings_button,
		credits_button,
		quit_button,
	]
	for index in range(buttons.size()):
		var button := buttons[index]
		var base_height := 50.0 if index == 0 else 48.0
		button.custom_minimum_size = Vector2(button_width, maxf(48.0, base_height * ui_scale))
		button.add_theme_font_size_override("font_size", maxi(14, roundi((18.0 if index == 0 else 16.0) * ui_scale)))


func start_title_pulse() -> void:
	# Subtle breathing glow on title
	var tw := create_tween().set_loops()
	tw.tween_property(title_label, "theme_override_colors/font_color", Color(1.0, 0.95, 0.96, 1.0), 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title_label, "theme_override_colors/font_color", Color(0.95, 0.70, 0.75, 1.0), 2.0).set_trans(Tween.TRANS_SINE)


func _on_play_pressed() -> void:
	GameManager.load_level_selection()


func _on_multiplayer_pressed() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/multiplayer_menu.tscn")
	if err != OK:
		push_error("Main menu: Failed to open multiplayer menu, error: %d" % err)


func _on_level_select_pressed() -> void:
	GameManager.load_level_selection()


func _on_settings_pressed() -> void:
	modal_overlay.visible = true
	settings_menu.visible = true
	credits_menu.visible = false
	settings_menu.refresh_from_manager()


func _on_credits_pressed() -> void:
	modal_overlay.visible = true
	settings_menu.visible = false
	credits_menu.visible = true


func _open_layout_editor() -> void:
	if is_instance_valid(layout_editor):
		layout_editor.queue_free()
	layout_editor = MobileLayoutEditorScript.new()
	layout_editor.name = "MobileLayoutEditor"
	modal_overlay.add_child(layout_editor)
	settings_menu.visible = false
	layout_editor.closed.connect(_on_layout_editor_closed)


func _on_layout_editor_closed() -> void:
	if is_instance_valid(layout_editor):
		layout_editor.queue_free()
	settings_menu.visible = true
	settings_menu.refresh_from_manager()


func _close_modals() -> void:
	modal_overlay.visible = false
	settings_menu.visible = false
	credits_menu.visible = false
	if is_instance_valid(layout_editor):
		layout_editor.queue_free()
		layout_editor = null


func _on_quit_pressed() -> void:
	print("INVASION: Quitting game...")
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal_overlay.visible:
			_close_modals()
