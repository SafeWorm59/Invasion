extends Control

var level_id: int = 1
var is_locked: bool = false
var accent_color: Color = Color(0.9, 0.3, 0.4)
var thumbnail_path: String = ""

static var _texture_cache: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(190, 120)
	clip_contents = true


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var parent_card = get_parent().get_parent().get_parent()
	if parent_card is LevelCard and not parent_card.level_data.is_empty():
		level_id = parent_card.level_data.get("id", 1)
		is_locked = parent_card.level_data.get("locked", true)
		accent_color = parent_card.level_data.get("accent_color", Color(0.9, 0.3, 0.4))
		thumbnail_path = parent_card.level_data.get("thumbnail_path", "")

	# Base thumbnail background
	var bg := Color(0.06, 0.02, 0.03, 1.0)
	draw_rect(rect, bg)

	# Try to load and draw data-driven image thumbnail
	var drew_texture := false
	if thumbnail_path != "":
		var tex: Texture2D = null
		if _texture_cache.has(thumbnail_path):
			tex = _texture_cache[thumbnail_path]
		elif ResourceLoader.exists(thumbnail_path):
			tex = load(thumbnail_path) as Texture2D
			if tex != null:
				_texture_cache[thumbnail_path] = tex

		if tex != null:
			draw_texture_rect(tex, rect, false)
			drew_texture = true

	# If locked, draw lock overlay and return
	if is_locked:
		_draw_locked_overlay(rect)
		# Border overlay around thumbnail
		draw_rect(rect, Color(0.40, 0.25, 0.28, 0.5), false, 1.5)
		return

	# If texture was drawn and not locked, finish with border
	if drew_texture:
		draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.6), false, 1.5)
		return

	# Fallback Procedural Drawing for Levels
	if level_id == 1:
		_draw_level_1_procedural()
	elif level_id == 2:
		_draw_level_2_procedural()
	elif level_id == 3:
		_draw_level_3_procedural()
	elif level_id == 4:
		_draw_level_4_procedural()
	elif level_id == 5:
		_draw_level_5_procedural()

	# Border overlay around thumbnail
	draw_rect(rect, Color(accent_color.r, accent_color.g, accent_color.b, 0.5), false, 1.5)


func _draw_locked_overlay(rect: Rect2) -> void:
	# Semi-transparent dark wash
	draw_rect(rect, Color(0.04, 0.02, 0.03, 0.85))

	# Grid overlay for locked/classified levels
	var grid_color := Color(0.35, 0.22, 0.26, 0.45)
	for x in range(0, int(size.x), 20):
		draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
	for y in range(0, int(size.y), 20):
		draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)

	# Stylized Padlock
	var center := size * 0.5
	var lock_body := Rect2(center.x - 18, center.y - 6, 36, 28)
	draw_rect(lock_body, Color(0.40, 0.30, 0.33, 0.9), false, 2.0)
	draw_circle(Vector2(center.x, center.y + 6), 4.0, Color(0.7, 0.5, 0.55))
	draw_line(Vector2(center.x, center.y + 6), Vector2(center.x, center.y + 14), Color(0.7, 0.5, 0.55), 2.5)

	# Shackle
	var shackle_center := Vector2(center.x, center.y - 6)
	draw_arc(shackle_center, 12.0, PI, TAU, 16, Color(0.50, 0.40, 0.45, 0.9), 2.5)


func _draw_level_1_procedural() -> void:
	# Level 1: Nasal Passage (cilia + mucus flow + airway)
	draw_circle(Vector2(size.x * 0.7, size.y * 0.4), 45.0, Color(0.45, 0.15, 0.22, 0.35))
	var tissue_color := Color(0.60, 0.22, 0.30, 0.8)
	var pts := PackedVector2Array([
		Vector2(0, size.y * 0.2),
		Vector2(size.x * 0.3, size.y * 0.35),
		Vector2(size.x * 0.6, size.y * 0.25),
		Vector2(size.x, size.y * 0.45),
		Vector2(size.x, 0),
		Vector2(0, 0)
	])
	draw_colored_polygon(pts, tissue_color)

	for i in range(12):
		var t := float(i) / 12.0
		var start := Vector2(t * size.x, size.y * 0.25 + sin(t * 4.0) * 8.0)
		var end := start + Vector2(cos(t * 3.0 + 1.2), sin(t * 3.0 + 1.2)) * 14.0
		draw_line(start, end, Color(0.75, 0.35, 0.45, 0.7), 2.0)

	var virus_pos := Vector2(size.x * 0.45, size.y * 0.65)
	draw_circle(virus_pos, 14.0, Color(0.95, 0.20, 0.35, 1.0))
	for s in range(8):
		var ang := s * TAU / 8.0
		var p1 := virus_pos + Vector2(cos(ang), sin(ang)) * 14.0
		var p2 := virus_pos + Vector2(cos(ang), sin(ang)) * 20.0
		draw_line(p1, p2, Color(1.0, 0.4, 0.5), 2.5)


func _draw_level_2_procedural() -> void:
	# Level 2: Pharynx (deeper muscular folds, lymphoid nodes, neutrophils)
	draw_circle(Vector2(size.x * 0.3, size.y * 0.5), 50.0, Color(0.50, 0.10, 0.30, 0.35))
	var muscle_color := Color(0.68, 0.20, 0.42, 0.75)
	var left_pts := PackedVector2Array([
		Vector2(0, 0),
		Vector2(size.x * 0.4, 0),
		Vector2(size.x * 0.25, size.y * 0.5),
		Vector2(size.x * 0.35, size.y),
		Vector2(0, size.y)
	])
	draw_colored_polygon(left_pts, muscle_color)

	var right_pts := PackedVector2Array([
		Vector2(size.x, 0),
		Vector2(size.x * 0.65, 0),
		Vector2(size.x * 0.78, size.y * 0.6),
		Vector2(size.x * 0.65, size.y),
		Vector2(size.x, size.y)
	])
	draw_colored_polygon(right_pts, muscle_color)

	draw_circle(Vector2(size.x * 0.55, size.y * 0.4), 11.0, Color(0.9, 0.85, 0.75, 0.9))
	draw_circle(Vector2(size.x * 0.55, size.y * 0.4), 5.0, Color(0.4, 0.35, 0.45, 0.9))

	var v_pos := Vector2(size.x * 0.45, size.y * 0.75)
	draw_circle(v_pos, 12.0, Color(0.95, 0.20, 0.35, 1.0))
	for s in range(8):
		var ang := s * TAU / 8.0
		var p1 := v_pos + Vector2(cos(ang), sin(ang)) * 12.0
		var p2 := v_pos + Vector2(cos(ang), sin(ang)) * 17.0
		draw_line(p1, p2, Color(1.0, 0.4, 0.5), 2.0)


func _draw_level_3_procedural() -> void:
	# Level 3: Larynx (Voice Box: vocal cords, glottis slit, dendritic surveillance)
	draw_circle(Vector2(size.x * 0.5, size.y * 0.5), 55.0, Color(0.50, 0.22, 0.10, 0.35))

	# Vocal cord folds (left & right bands)
	var fold_color := Color(0.60, 0.25, 0.30, 0.8)
	var left_fold := PackedVector2Array([
		Vector2(0, 0),
		Vector2(size.x * 0.32, 0),
		Vector2(size.x * 0.38, size.y * 0.5),
		Vector2(size.x * 0.30, size.y),
		Vector2(0, size.y)
	])
	draw_colored_polygon(left_fold, fold_color)

	var right_fold := PackedVector2Array([
		Vector2(size.x, 0),
		Vector2(size.x * 0.68, 0),
		Vector2(size.x * 0.62, size.y * 0.5),
		Vector2(size.x * 0.70, size.y),
		Vector2(size.x, size.y)
	])
	draw_colored_polygon(right_fold, fold_color)

	# Vocal fold margins (pearly white lips)
	draw_line(Vector2(size.x * 0.32, 0), Vector2(size.x * 0.38, size.y * 0.5), Color(0.85, 0.80, 0.75, 0.8), 2.0)
	draw_line(Vector2(size.x * 0.38, size.y * 0.5), Vector2(size.x * 0.30, size.y), Color(0.85, 0.80, 0.75, 0.8), 2.0)
	draw_line(Vector2(size.x * 0.68, 0), Vector2(size.x * 0.62, size.y * 0.5), Color(0.85, 0.80, 0.75, 0.8), 2.0)
	draw_line(Vector2(size.x * 0.62, size.y * 0.5), Vector2(size.x * 0.70, size.y), Color(0.85, 0.80, 0.75, 0.8), 2.0)

	# Dendritic Cell Sentinel with golden surveillance arcs
	var dc_pos := Vector2(size.x * 0.50, size.y * 0.42)
	draw_arc(dc_pos, 28.0, 0.0, TAU, 24, Color(1.0, 0.82, 0.28, 0.45), 1.5)
	draw_arc(dc_pos, 44.0, 0.0, TAU, 28, Color(1.0, 0.82, 0.28, 0.25), 1.0)

	# Dendrite arms
	for i in range(6):
		var da := i * TAU / 6.0 + 0.3
		var arm_end := dc_pos + Vector2(cos(da), sin(da)) * 20.0
		draw_line(dc_pos, arm_end, Color(0.25, 0.60, 0.50, 0.9), 2.0)
		draw_circle(arm_end, 2.0, Color(0.8, 0.95, 0.90))

	# Dendritic body
	draw_circle(dc_pos, 10.0, Color(0.23, 0.56, 0.49, 1.0))
	draw_circle(dc_pos, 5.0, Color(0.88, 0.78, 0.37, 1.0))

	# Player virus entering from bottom
	var v_pos := Vector2(size.x * 0.50, size.y * 0.82)
	draw_circle(v_pos, 11.0, Color(0.95, 0.20, 0.35, 1.0))
	for s in range(8):
		var ang := s * TAU / 8.0
		var p1 := v_pos + Vector2(cos(ang), sin(ang)) * 11.0
		var p2 := v_pos + Vector2(cos(ang), sin(ang)) * 16.0
		draw_line(p1, p2, Color(1.0, 0.4, 0.5), 2.0)


func _draw_level_4_procedural() -> void:
	# Level 4: Trachea (vertical lumen, C-shaped cartilage rings, posterior
	# membranous wall, carina split toward the bronchi, NKT surveillance).
	draw_circle(Vector2(size.x * 0.5, size.y * 0.45), 60.0, Color(0.48, 0.16, 0.20, 0.35))

	# Lumen: a continuous tube that opens into two bronchi at the bottom.
	var lumen := PackedVector2Array([
		Vector2(size.x * 0.30, 0),
		Vector2(size.x * 0.70, 0),
		Vector2(size.x * 0.73, size.y * 0.70),
		Vector2(size.x * 0.60, size.y * 0.90),
		Vector2(size.x * 0.56, size.y),
		Vector2(size.x * 0.44, size.y),
		Vector2(size.x * 0.40, size.y * 0.90),
		Vector2(size.x * 0.27, size.y * 0.70),
	])
	draw_colored_polygon(lumen, Color(0.37, 0.12, 0.15, 0.92))

	# Posterior membranous wall on the right side (no cartilage here).
	var posterior := PackedVector2Array([
		Vector2(size.x * 0.62, 0),
		Vector2(size.x * 0.70, 0),
		Vector2(size.x * 0.73, size.y * 0.70),
		Vector2(size.x * 0.62, size.y * 0.86),
	])
	draw_colored_polygon(posterior, Color(0.30, 0.09, 0.12, 0.85))
	draw_line(
		Vector2(size.x * 0.62, 0),
		Vector2(size.x * 0.62, size.y * 0.86),
		Color(0.80, 0.50, 0.50, 0.45),
		1.5
	)

	# C-shaped hyaline cartilage rings.
	for i in range(5):
		var y := size.y * 0.09 + float(i) * size.y * 0.155
		var cx := size.x * 0.5
		var half := size.x * 0.21
		var pts := PackedVector2Array()
		for k in range(24):
			var t := float(k) / 23.0
			var x := cx - half + 2.0 * half * t
			var bow := -(1.0 - pow(t * 2.0 - 1.0, 2.0)) * 5.0
			pts.append(Vector2(x, y + bow))
		draw_polyline(pts, Color(0.20, 0.07, 0.09, 0.55), 5.0, true)
		draw_polyline(pts, Color(0.86, 0.71, 0.65, 0.80), 3.0, true)
		draw_polyline(pts, Color(1.0, 0.90, 0.84, 0.35), 1.0, true)

	# Carinal spur and the two main bronchi.
	var carina_y := size.y * 0.86
	draw_line(
		Vector2(size.x * 0.5, carina_y),
		Vector2(size.x * 0.56, size.y),
		Color(0.78, 0.58, 0.52, 0.75),
		2.0
	)
	draw_line(
		Vector2(size.x * 0.5, carina_y),
		Vector2(size.x * 0.44, size.y),
		Color(0.78, 0.58, 0.52, 0.75),
		2.0
	)

	# NKT cell with a violet surveillance ring.
	var nkt := Vector2(size.x * 0.61, size.y * 0.42)
	draw_arc(nkt, 13.0, 0.0, TAU, 20, Color(0.85, 0.52, 1.0, 0.35), 1.2)
	draw_circle(nkt, 7.0, Color(0.44, 0.15, 0.60, 1.0))
	draw_circle(nkt, 4.2, Color(0.72, 0.30, 0.86, 1.0))
	draw_circle(nkt + Vector2(-1.0, -1.0), 1.8, Color(0.90, 0.65, 1.0, 1.0))

	# Player virus entering from the bottom.
	var v_pos := Vector2(size.x * 0.47, size.y * 0.78)
	draw_circle(v_pos, 10.0, Color(0.95, 0.20, 0.35, 1.0))
	for s in range(8):
		var ang := s * TAU / 8.0
		var p1 := v_pos + Vector2(cos(ang), sin(ang)) * 10.0
		var p2 := v_pos + Vector2(cos(ang), sin(ang)) * 15.0
		draw_line(p1, p2, Color(1.0, 0.4, 0.5), 2.0)


func _draw_level_5_procedural() -> void:
	# Level 5: paired lung branches opening into clusters of alveoli.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.04, 0.08, 1.0))
	var airway := Color(0.68, 0.36, 0.51, 0.9)
	var airway_hi := Color(0.95, 0.69, 0.75, 0.82)
	var junction := Vector2(size.x * 0.5, size.y * 0.42)
	var trunk_top := Vector2(size.x * 0.5, size.y * 0.08)
	draw_line(trunk_top, junction, airway, 16.0, true)
	draw_line(trunk_top, junction, airway_hi, 7.0, true)

	var left_main := Vector2(size.x * 0.30, size.y * 0.62)
	var right_main := Vector2(size.x * 0.70, size.y * 0.62)
	for endpoint in [left_main, right_main]:
		draw_line(junction, endpoint, airway, 12.0, true)
		draw_line(junction, endpoint, airway_hi, 5.0, true)

	var alveoli := [
		Vector2(size.x * 0.16, size.y * 0.31),
		Vector2(size.x * 0.18, size.y * 0.82),
		Vector2(size.x * 0.84, size.y * 0.31),
		Vector2(size.x * 0.82, size.y * 0.82),
	]
	var branches := [
		[left_main, alveoli[0]],
		[left_main, alveoli[1]],
		[right_main, alveoli[2]],
		[right_main, alveoli[3]],
	]
	for branch in branches:
		draw_line(branch[0], branch[1], airway, 7.0, true)
		draw_line(branch[0], branch[1], airway_hi, 3.0, true)

	for center in alveoli:
		for i in range(7):
			var angle := TAU * float(i) / 7.0
			var offset := Vector2(cos(angle), sin(angle)) * 11.0
			draw_circle(center + offset, 6.0, Color(0.78, 0.48, 0.65, 0.9))
			draw_circle(center + offset, 3.2, Color(0.96, 0.74, 0.80, 0.85))

	var b_cell := Vector2(size.x * 0.73, size.y * 0.48)
	draw_circle(b_cell, 7.0, Color(0.22, 0.68, 0.76, 1.0))
	draw_circle(b_cell, 3.0, Color(0.63, 0.92, 0.90, 1.0))
