class_name UIThemeHelper
extends RefCounted

# Helper to provide uniform biological sci-fi styling for UI elements across menus

static func create_button_style(bg_color: Color, border_color: Color, corner_radius: int = 8, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


static func style_button(button: Button, is_accent: bool = false) -> void:
	var normal_bg := Color(0.24, 0.07, 0.12, 0.88) if not is_accent else Color(0.45, 0.12, 0.20, 0.92)
	var normal_border := Color(0.70, 0.22, 0.32, 0.75) if not is_accent else Color(0.95, 0.35, 0.45, 0.95)

	var hover_bg := Color(0.38, 0.11, 0.18, 0.98) if not is_accent else Color(0.60, 0.16, 0.26, 1.0)
	var hover_border := Color(1.0, 0.45, 0.55, 1.0)

	var pressed_bg := Color(0.16, 0.04, 0.08, 1.0)
	var pressed_border := Color(0.90, 0.30, 0.40, 1.0)

	var disabled_bg := Color(0.12, 0.08, 0.10, 0.45)
	var disabled_border := Color(0.30, 0.25, 0.28, 0.35)

	button.add_theme_stylebox_override("normal", create_button_style(normal_bg, normal_border))
	button.add_theme_stylebox_override("hover", create_button_style(hover_bg, hover_border))
	button.add_theme_stylebox_override("pressed", create_button_style(pressed_bg, pressed_border))
	button.add_theme_stylebox_override("disabled", create_button_style(disabled_bg, disabled_border))
	button.add_theme_stylebox_override("focus", create_button_style(hover_bg, hover_border))

	button.add_theme_color_override("font_color", Color(0.95, 0.90, 0.92))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.85, 0.70, 0.75))
	button.add_theme_color_override("font_disabled_color", Color(0.50, 0.45, 0.48))
	button.add_theme_font_size_override("font_size", 18)

	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Add gentle scale tween on hover
	button.pivot_offset = button.size * 0.5
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)

	button.mouse_entered.connect(func():
		if not button.disabled:
			var tw := button.create_tween()
			tw.tween_property(button, "scale", Vector2(1.03, 1.03), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	button.mouse_exited.connect(func():
		var tw := button.create_tween()
		tw.tween_property(button, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)


static func create_panel_style(bg_color: Color = Color(0.12, 0.04, 0.07, 0.94), border_color: Color = Color(0.70, 0.22, 0.32, 0.65), corner_radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	return style
