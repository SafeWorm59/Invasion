extends Control

@onready var play_button: Button = $ContentLayer/MainVBox/ButtonContainer/PlayButton
@onready var level_select_button: Button = $ContentLayer/MainVBox/ButtonContainer/LevelSelectButton
@onready var settings_button: Button = $ContentLayer/MainVBox/ButtonContainer/SettingsButton
@onready var credits_button: Button = $ContentLayer/MainVBox/ButtonContainer/CreditsButton
@onready var quit_button: Button = $ContentLayer/MainVBox/ButtonContainer/QuitButton

@onready var title_label: Label = $ContentLayer/MainVBox/TitleContainer/TitleLabel
@onready var subtitle_label: Label = $ContentLayer/MainVBox/TitleContainer/SubtitleLabel

@onready var modal_overlay: ColorRect = $ModalOverlay
@onready var settings_menu: SettingsMenu = $ModalOverlay/SettingsMenu
@onready var credits_menu: CreditsMenu = $ModalOverlay/CreditsMenu


func _ready() -> void:
	# Style buttons
	UIThemeHelper.style_button(play_button, true) # Prominent accent button
	UIThemeHelper.style_button(level_select_button, false)
	UIThemeHelper.style_button(settings_button, false)
	UIThemeHelper.style_button(credits_button, false)
	UIThemeHelper.style_button(quit_button, false)

	# Connect button events
	play_button.pressed.connect(_on_play_pressed)
	level_select_button.pressed.connect(_on_level_select_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Connect modal events
	settings_menu.closed.connect(_close_modals)
	credits_menu.closed.connect(_close_modals)

	_close_modals()
	start_title_pulse()


func start_title_pulse() -> void:
	# Subtle breathing glow on title
	var tw := create_tween().set_loops()
	tw.tween_property(title_label, "theme_override_colors/font_color", Color(1.0, 0.95, 0.96, 1.0), 2.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title_label, "theme_override_colors/font_color", Color(0.95, 0.70, 0.75, 1.0), 2.0).set_trans(Tween.TRANS_SINE)


func _on_play_pressed() -> void:
	GameManager.load_level_selection()


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


func _close_modals() -> void:
	modal_overlay.visible = false
	settings_menu.visible = false
	credits_menu.visible = false


func _on_quit_pressed() -> void:
	print("INVASION: Quitting game...")
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal_overlay.visible:
			_close_modals()
