class_name SettingsMenu
extends PanelContainer

const UISafeArea := preload("res://scripts/ui_safe_area.gd")

signal closed
signal customize_controls_requested

@onready var master_slider: HSlider = $Margin/VBox/Grid/MasterSlider
@onready var master_label: Label = $Margin/VBox/Grid/MasterValue
@onready var music_slider: HSlider = $Margin/VBox/Grid/MusicSlider
@onready var music_label: Label = $Margin/VBox/Grid/MusicValue
@onready var sfx_slider: HSlider = $Margin/VBox/Grid/SFXSlider
@onready var sfx_label: Label = $Margin/VBox/Grid/SFXValue
@onready var fullscreen_check: CheckBox = $Margin/VBox/Grid/FullscreenCheck
@onready var mobile_preview_check: CheckBox = $Margin/VBox/Grid/MobilePreviewCheck
@onready var replay_tutorials_check: CheckBox = $Margin/VBox/Grid/ReplayTutorialsCheck
@onready var customize_controls_button: Button = $Margin/VBox/CustomizeControlsButton
@onready var save_button: Button = $Margin/VBox/Buttons/SaveButton
@onready var close_button: Button = $Margin/VBox/Buttons/CloseButton
@onready var settings_vbox: VBoxContainer = $Margin/VBox
@onready var buttons_container: HBoxContainer = $Margin/VBox/Buttons

var initial_master: float
var initial_music: float
var initial_sfx: float
var initial_fullscreen: bool
var initial_mobile_preview: bool


func _ready() -> void:
	add_theme_stylebox_override("panel", UIThemeHelper.create_panel_style(Color(0.11, 0.03, 0.06, 0.96), Color(0.85, 0.25, 0.38, 0.8), 12))

	UIThemeHelper.style_button(save_button, true)
	UIThemeHelper.style_button(close_button, false)
	UIThemeHelper.style_button(customize_controls_button, false)
	UIThemeHelper.style_button(replay_tutorials_check, false)

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	mobile_preview_check.toggled.connect(_on_mobile_preview_toggled)

	save_button.pressed.connect(_on_save_pressed)
	close_button.pressed.connect(_on_close_pressed)
	customize_controls_button.pressed.connect(func(): customize_controls_requested.emit())
	get_viewport().size_changed.connect(_fit_to_viewport)

	refresh_from_manager()
	_fit_to_viewport()


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	var panel_width := minf(560.0, maxf(280.0, safe_rect.size.x - 24.0))
	var panel_height := minf(520.0, maxf(420.0, safe_rect.size.y - 24.0))
	var center_delta := safe_rect.get_center() - viewport_size * 0.5
	custom_minimum_size = Vector2(panel_width, panel_height)
	offset_left = center_delta.x - panel_width * 0.5
	offset_right = center_delta.x + panel_width * 0.5
	offset_top = center_delta.y - panel_height * 0.5
	offset_bottom = center_delta.y + panel_height * 0.5
	var slider_min_width := clampf(panel_width - 320.0, 100.0, 240.0)
	master_slider.custom_minimum_size.x = slider_min_width
	music_slider.custom_minimum_size.x = slider_min_width
	sfx_slider.custom_minimum_size.x = slider_min_width
	settings_vbox.add_theme_constant_override("separation", maxi(10, roundi(minf(20.0, safe_rect.size.y * 0.028))))
	customize_controls_button.custom_minimum_size = Vector2(minf(280.0, panel_width - 56.0), 48.0)
	var action_width := maxf(120.0, (panel_width - 72.0) * 0.5)
	close_button.custom_minimum_size = Vector2(minf(160.0, action_width), 48.0)
	save_button.custom_minimum_size = Vector2(minf(180.0, action_width), 48.0)


func refresh_from_manager() -> void:
	initial_master = GameManager.master_volume
	initial_music = GameManager.music_volume
	initial_sfx = GameManager.sfx_volume
	initial_fullscreen = GameManager.is_fullscreen
	initial_mobile_preview = GameManager.mobile_controls_preview_on_desktop

	master_slider.value = initial_master * 100.0
	master_label.text = "%d%%" % int(master_slider.value)

	music_slider.value = initial_music * 100.0
	music_label.text = "%d%%" % int(music_slider.value)

	sfx_slider.value = initial_sfx * 100.0
	sfx_label.text = "%d%%" % int(sfx_slider.value)

	fullscreen_check.button_pressed = initial_fullscreen
	mobile_preview_check.button_pressed = initial_mobile_preview
	replay_tutorials_check.button_pressed = false


func _on_master_changed(val: float) -> void:
	master_label.text = "%d%%" % int(val)
	GameManager.set_master_volume(val / 100.0)


func _on_music_changed(val: float) -> void:
	music_label.text = "%d%%" % int(val)
	GameManager.set_music_volume(val / 100.0)


func _on_sfx_changed(val: float) -> void:
	sfx_label.text = "%d%%" % int(val)
	GameManager.set_sfx_volume(val / 100.0)


func _on_fullscreen_toggled(enabled: bool) -> void:
	GameManager.set_fullscreen_mode(enabled)


func _on_mobile_preview_toggled(enabled: bool) -> void:
	GameManager.mobile_controls_preview_on_desktop = enabled


func _on_save_pressed() -> void:
	if replay_tutorials_check.button_pressed:
		if not GameManager.reset_tutorial_progress():
			return
		replay_tutorials_check.button_pressed = false
	GameManager.save_settings()
	closed.emit()


func _on_close_pressed() -> void:
	# Revert changes if discarded
	GameManager.set_master_volume(initial_master)
	GameManager.set_music_volume(initial_music)
	GameManager.set_sfx_volume(initial_sfx)
	GameManager.set_fullscreen_mode(initial_fullscreen)
	GameManager.mobile_controls_preview_on_desktop = initial_mobile_preview
	replay_tutorials_check.button_pressed = false
	closed.emit()
