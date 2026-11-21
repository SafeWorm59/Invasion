class_name CreditsMenu
extends PanelContainer

signal closed

@onready var back_button: Button = $Margin/VBox/BackButton


func _ready() -> void:
	add_theme_stylebox_override("panel", UIThemeHelper.create_panel_style(Color(0.11, 0.03, 0.06, 0.96), Color(0.85, 0.25, 0.38, 0.8), 12))
	UIThemeHelper.style_button(back_button, false)
	back_button.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	closed.emit()
