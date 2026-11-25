extends RefCounted


static func get_safe_rect(viewport_size: Vector2) -> Rect2:
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if not OS.has_feature("mobile") or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return viewport_rect

	var display_size := DisplayServer.screen_get_size()
	var safe_area := DisplayServer.get_display_safe_area()
	if display_size.x <= 0 or display_size.y <= 0 or safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return viewport_rect

	var scale := viewport_size / Vector2(display_size)
	var display_rect := Rect2(Vector2(safe_area.position) * scale, Vector2(safe_area.size) * scale)
	var clipped_rect := display_rect.intersection(viewport_rect)
	if clipped_rect.size.x <= 0.0 or clipped_rect.size.y <= 0.0:
		return viewport_rect
	return clipped_rect


static func fit_to_safe_rect(control: Control, safe_rect: Rect2, viewport_size: Vector2, margin: float = 0.0) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = safe_rect.position.x + margin
	control.offset_top = safe_rect.position.y + margin
	control.offset_right = safe_rect.end.x - viewport_size.x - margin
	control.offset_bottom = safe_rect.end.y - viewport_size.y - margin
