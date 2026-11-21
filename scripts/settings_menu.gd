class_name SettingsMenu
extends PanelContainer

signal closed

@onready var master_slider: HSlider = $Margin/VBox/Grid/MasterSlider
@onready var master_label: Label = $Margin/VBox/Grid/MasterValue
@onready var music_slider: HSlider = $Margin/VBox/Grid/MusicSlider
@onready var music_label: Label = $Margin/VBox/Grid/MusicValue
@onready var sfx_slider: HSlider = $Margin/VBox/Grid/SFXSlider
@onready var sfx_label: Label = $Margin/VBox/Grid/SFXValue
@onready var fullscreen_check: CheckBox = $Margin/VBox/Grid/FullscreenCheck
@onready var save_button: Button = $Margin/VBox/Buttons/SaveButton
@onready var close_button: Button = $Margin/VBox/Buttons/CloseButton

var initial_master: float
var initial_music: float
var initial_sfx: float
var initial_fullscreen: bool


func _ready() -> void:
	add_theme_stylebox_override("panel", UIThemeHelper.create_panel_style(Color(0.11, 0.03, 0.06, 0.96), Color(0.85, 0.25, 0.38, 0.8), 12))

	UIThemeHelper.style_button(save_button, true)
	UIThemeHelper.style_button(close_button, false)

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	save_button.pressed.connect(_on_save_pressed)
	close_button.pressed.connect(_on_close_pressed)

	refresh_from_manager()


func refresh_from_manager() -> void:
	initial_master = GameManager.master_volume
	initial_music = GameManager.music_volume
	initial_sfx = GameManager.sfx_volume
	initial_fullscreen = GameManager.is_fullscreen

	master_slider.value = initial_master * 100.0
	master_label.text = "%d%%" % int(master_slider.value)

	music_slider.value = initial_music * 100.0
	music_label.text = "%d%%" % int(music_slider.value)

	sfx_slider.value = initial_sfx * 100.0
	sfx_label.text = "%d%%" % int(sfx_slider.value)

	fullscreen_check.button_pressed = initial_fullscreen


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


func _on_save_pressed() -> void:
	GameManager.save_settings()
	closed.emit()


func _on_close_pressed() -> void:
	# Revert changes if discarded
	GameManager.set_master_volume(initial_master)
	GameManager.set_music_volume(initial_music)
	GameManager.set_sfx_volume(initial_sfx)
	GameManager.set_fullscreen_mode(initial_fullscreen)
	closed.emit()
