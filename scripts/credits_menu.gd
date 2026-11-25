class_name CreditsMenu
extends PanelContainer

const UISafeArea := preload("res://scripts/ui_safe_area.gd")

signal closed

@onready var back_button: Button = $Margin/VBox/BackButton
@onready var title_label: Label = $Margin/VBox/Title


func _ready() -> void:
	add_theme_stylebox_override("panel", UIThemeHelper.create_panel_style(Color(0.11, 0.03, 0.06, 0.96), Color(0.85, 0.25, 0.38, 0.8), 12))
	UIThemeHelper.style_button(back_button, false)
	back_button.pressed.connect(_on_back_pressed)
	get_viewport().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	var panel_width := minf(560.0, maxf(300.0, safe_rect.size.x - 24.0))
	var panel_height := minf(480.0, maxf(360.0, safe_rect.size.y - 24.0))
	var center_delta := safe_rect.get_center() - viewport_size * 0.5
	custom_minimum_size = Vector2(panel_width, panel_height)
	offset_left = center_delta.x - panel_width * 0.5
	offset_right = center_delta.x + panel_width * 0.5
	offset_top = center_delta.y - panel_height * 0.5
	offset_bottom = center_delta.y + panel_height * 0.5
	back_button.custom_minimum_size = Vector2(minf(200.0, panel_width - 64.0), 48.0)
	title_label.add_theme_font_size_override("font_size", maxi(18, roundi(22.0 * minf(panel_width / 560.0, 1.0))))


func _on_back_pressed() -> void:
	closed.emit()
