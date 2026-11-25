extends Control

# Reusable level minimap, shown fixed in the top-right corner of the HUD.
#
# It draws a simplified top-down view of the WHOLE level and live markers for
# the player, host cells, neutrophils and macrophages. Entity counts are polled
# periodically; markers are read from groups when the map is redrawn.
#
# Per-level data comes from a duck-typed provider: the current scene root may
# implement `minimap_bounds() -> Rect2` (world-space playable bounds) and
# `minimap_outline() -> Array` (a list of world-space PackedVector2Array
# polygons filling the navigable silhouette). Any level can opt in by adding
# those two methods, so Levels 3-5 need no new minimap code.

const MAP_WIDTH: float = 232.0
const MAP_HEIGHT: float = 232.0
const LEGEND_HEIGHT: float = 54.0
const SCREEN_MARGIN: float = 16.0
const INNER_PAD: float = 8.0
const FIT: float = 0.92
const ENTITY_SCAN_INTERVAL: float = 0.25

const COLOR_BG := Color(0.05, 0.03, 0.07, 0.72)
const COLOR_BORDER := Color(0.68, 0.33, 0.50, 0.95)
const COLOR_TERRAIN := Color(0.34, 0.13, 0.20, 0.95)
const COLOR_TERRAIN_EDGE := Color(0.78, 0.40, 0.55, 0.9)
const COLOR_PLAYER := Color(0.45, 1.0, 1.0, 1.0)
const COLOR_HOST := Color(0.35, 0.90, 0.42, 1.0)
const COLOR_NEUTROPHIL := Color(1.0, 0.32, 0.28, 1.0)
const COLOR_MACROPHAGE := Color(0.74, 0.56, 1.0, 1.0)
const COLOR_DENDRITIC := Color(1.0, 0.82, 0.28, 1.0)
const COLOR_NKT := Color(0.80, 0.36, 1.0, 1.0)
const COLOR_LABEL := Color(0.90, 0.86, 0.90, 1.0)
const COLOR_HINT := Color(0.75, 0.70, 0.75, 1.0)

var _provider: Node = null
var _bounds: Rect2 = Rect2()
var _outline: Array = []
var _have_map: bool = false
var _cached_mapped_polys: Array[PackedVector2Array] = []
var _cached_mapped_edges: Array[PackedVector2Array] = []
var _cached_legend: Array[Dictionary] = []
var _redraw_timer: float = 0.0

# Cache entity counts so the legend is only rebuilt when groups change.
var _last_player_count: int = -1
var _last_host_count: int = -1
var _last_neutrophil_count: int = -1
var _last_macrophage_count: int = -1
var _last_dendritic_count: int = -1
var _last_nkt_count: int = -1
var _first_run: bool = true
var _entity_scan_timer: float = 0.0


func _ready() -> void:
	add_to_group("minimap")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_safe_area(Rect2(Vector2.ZERO, get_viewport_rect().size), get_viewport_rect().size)


func apply_safe_area(safe_rect: Rect2, viewport_size: Vector2) -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_right = safe_rect.end.x - viewport_size.x - SCREEN_MARGIN
	offset_left = offset_right - MAP_WIDTH
	offset_top = safe_rect.position.y + SCREEN_MARGIN
	offset_bottom = offset_top + MAP_HEIGHT + LEGEND_HEIGHT


func _process(delta: float) -> void:
	if not _have_map:
		_resolve_provider()

	_entity_scan_timer -= delta
	if _entity_scan_timer <= 0.0 or _first_run:
		_entity_scan_timer = ENTITY_SCAN_INTERVAL
		var counts_changed: bool = _check_entity_changes()
		if counts_changed or _first_run:
			_rebuild_legend_cache()
			queue_redraw()

	# Redraw smoothly at ~10 FPS so player and entity markers track smoothly
	# without pegging the CPU.
	_redraw_timer -= delta
	if _redraw_timer <= 0.0 or _first_run:
		_redraw_timer = 0.1
		_first_run = false
		queue_redraw()


func _resolve_provider() -> void:
	var scene := get_tree().current_scene

	if scene == null:
		return

	if not scene.has_method("minimap_bounds") or not scene.has_method("minimap_outline"):
		return

	var bounds: Variant = scene.call("minimap_bounds")

	if not (bounds is Rect2):
		return

	var rect: Rect2 = bounds

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var outline: Variant = scene.call("minimap_outline")

	_provider = scene
	_bounds = rect
	_outline = outline if outline is Array else []
	_cache_terrain()
	_rebuild_legend_cache()
	_have_map = true


func _cache_terrain() -> void:
	_cached_mapped_polys.clear()
	_cached_mapped_edges.clear()
	var map_rect := _map_rect()
	for polygon in _outline:
		if not (polygon is PackedVector2Array):
			continue
		var poly: PackedVector2Array = polygon
		if poly.size() < 3:
			continue
		var mapped := PackedVector2Array()
		for point in poly:
			mapped.append(_world_to_map(point, map_rect))
		_cached_mapped_polys.append(mapped)
		var edge := mapped.duplicate()
		edge.append(mapped[0])
		_cached_mapped_edges.append(edge)


func _check_entity_changes() -> bool:
	# Check player
	var player_exists = is_instance_valid(get_tree().get_first_node_in_group("player"))
	var player_count: int = 0
	if player_exists:
		player_count = 1

	# Check entity groups
	var host_cells = get_tree().get_nodes_in_group("uninfected_host_cells")
	var neutrophil_count: int = get_tree().get_nodes_in_group("neutrophils").size()
	var macrophage_count: int = get_tree().get_nodes_in_group("macrophages").size()
	var dendritic_count: int = get_tree().get_nodes_in_group("dendritic_cells").size()
	var nkt_count: int = get_tree().get_nodes_in_group("nkt_cells").size()

	# Compare with last frame - return true if anything changed
	var changed: bool = false
	if player_count != _last_player_count:
		_last_player_count = player_count
		changed = true

	if host_cells.size() != _last_host_count:
		_last_host_count = host_cells.size()
		changed = true

	if neutrophil_count != _last_neutrophil_count:
		_last_neutrophil_count = neutrophil_count
		changed = true

	if macrophage_count != _last_macrophage_count:
		_last_macrophage_count = macrophage_count
		changed = true

	if dendritic_count != _last_dendritic_count:
		_last_dendritic_count = dendritic_count
		changed = true

	if nkt_count != _last_nkt_count:
		_last_nkt_count = nkt_count
		changed = true

	return changed


func _map_rect() -> Rect2:
	return Rect2(
		Vector2(INNER_PAD, INNER_PAD),
		Vector2(
			maxf(4.0, size.x - INNER_PAD * 2.0),
			maxf(4.0, MAP_HEIGHT - INNER_PAD * 2.0)
		)
	)


func _world_to_map(world: Vector2, map_rect: Rect2) -> Vector2:
	var fit_scale: float = minf(
		map_rect.size.x / _bounds.size.x,
		map_rect.size.y / _bounds.size.y
	) * FIT
	var center := map_rect.position + map_rect.size * 0.5
	var world_center := _bounds.position + _bounds.size * 0.5
	return center + (world - world_center) * fit_scale


func _draw() -> void:
	var panel_rect := Rect2(Vector2.ZERO, size)
	draw_rect(panel_rect, COLOR_BG, true)
	draw_rect(panel_rect, COLOR_BORDER, false, 1.0)

	var map_rect := _map_rect()
	draw_rect(map_rect, Color(0.09, 0.05, 0.09, 0.55), true)

	if not _have_map:
		_draw_centered_hint(map_rect)
		_draw_legend()
		return

	for i in range(_cached_mapped_polys.size()):
		draw_colored_polygon(_cached_mapped_polys[i], COLOR_TERRAIN)
		draw_polyline(_cached_mapped_edges[i], COLOR_TERRAIN_EDGE, 1.0, true)

	_draw_group_markers("uninfected_host_cells", COLOR_HOST, 2.6, map_rect)
	_draw_group_markers("neutrophils", COLOR_NEUTROPHIL, 3.0, map_rect)
	_draw_group_markers("macrophages", COLOR_MACROPHAGE, 3.4, map_rect)
	_draw_dendritic_markers(map_rect)
	_draw_nkt_markers(map_rect)
	_draw_unlocked_exit_marker(map_rect)
	_draw_player(map_rect)

	_draw_legend()


func _draw_centered_hint(map_rect: Rect2) -> void:
	var font := ThemeDB.fallback_font
	var text := "MAPPING..."
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var pos := map_rect.position + map_rect.size * 0.5
	pos.x -= text_size.x * 0.5
	pos.y += text_size.y * 0.25
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_HINT)


func _draw_group_markers(
	group: String, color: Color, radius: float, map_rect: Rect2
) -> void:
	for node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node) or not (node is Node2D):
			continue

		var marker := _world_to_map((node as Node2D).global_position, map_rect)
		draw_circle(marker, radius, color)


func _draw_dendritic_markers(map_rect: Rect2) -> void:
	# Dendritic cells are drawn as a diamond so they read differently from the
	# round immune-cell dots. An alerting sentinel pulses a gold ring.
	for node in get_tree().get_nodes_in_group("dendritic_cells"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue

		var marker := _world_to_map((node as Node2D).global_position, map_rect)
		var r := 3.8
		var diamond := PackedVector2Array([
			marker + Vector2(0.0, -r),
			marker + Vector2(r, 0.0),
			marker + Vector2(0.0, r),
			marker + Vector2(-r, 0.0),
		])
		draw_colored_polygon(diamond, COLOR_DENDRITIC)

		if node.has_method("is_alerting") and node.is_alerting():
			draw_arc(marker, r + 3.0, 0.0, TAU, 16, Color(1.0, 1.0, 0.75, 0.95), 1.5, true)


func _draw_nkt_markers(map_rect: Rect2) -> void:
	# NKT cells get their own violet ring-and-dot marker so their surveillance
	# route is readable on the minimap. While inspecting or eliminating, the
	# outer ring pulses bright magenta.
	for node in get_tree().get_nodes_in_group("nkt_cells"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue

		var marker := _world_to_map((node as Node2D).global_position, map_rect)
		draw_circle(marker, 3.2, COLOR_NKT)
		draw_arc(marker, 5.2, 0.0, TAU, 18, Color(0.94, 0.72, 1.0, 0.95), 1.2, true)

		if node.has_method("is_alerting") and node.is_alerting():
			draw_arc(marker, 7.4, 0.0, TAU, 18, Color(1.0, 0.62, 0.96, 0.95), 1.5, true)


func _draw_player(map_rect: Rect2) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		return

	var marker := _world_to_map(player.global_position, map_rect)
	draw_circle(marker, 4.5, COLOR_PLAYER)
	draw_arc(marker, 6.5, 0.0, TAU, 18, COLOR_PLAYER, 1.0, true)


func _draw_unlocked_exit_marker(map_rect: Rect2) -> void:
	for node in get_tree().get_nodes_in_group("level_exit"):
		if not is_instance_valid(node) or not (node is Node2D):
			continue
		if not node.has_meta("exit_unlocked") or not bool(node.get_meta("exit_unlocked")):
			continue

		var marker := _world_to_map((node as Node2D).global_position, map_rect)
		var exit_color := Color("#72FF9B")
		draw_circle(marker, 4.0, exit_color)
		draw_arc(marker, 8.0, 0.0, TAU, 24, Color.WHITE, 1.8, true)
		draw_line(marker + Vector2(-3.0, 0.0), marker + Vector2(3.0, 0.0), Color.WHITE, 1.3, true)
		draw_line(marker + Vector2(0.0, -3.0), marker + Vector2(0.0, 3.0), Color.WHITE, 1.3, true)
		draw_string(
			ThemeDB.fallback_font,
			marker + Vector2(10.0, 3.0),
			"EXIT",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			8,
			Color.WHITE
		)


func _rebuild_legend_cache() -> void:
	_cached_legend.clear()
	if is_instance_valid(get_tree().get_first_node_in_group("player")):
		_cached_legend.append({"color": COLOR_PLAYER, "label": "YOU"})
	if not get_tree().get_nodes_in_group("uninfected_host_cells").is_empty():
		_cached_legend.append({"color": COLOR_HOST, "label": "UNINFECTED HOST"})
	if not get_tree().get_nodes_in_group("neutrophils").is_empty():
		_cached_legend.append({"color": COLOR_NEUTROPHIL, "label": "NEUTROPHIL"})
	if not get_tree().get_nodes_in_group("macrophages").is_empty():
		_cached_legend.append({"color": COLOR_MACROPHAGE, "label": "MACROPHAGE"})
	if not get_tree().get_nodes_in_group("dendritic_cells").is_empty():
		_cached_legend.append({"color": COLOR_DENDRITIC, "label": "DENDRITIC"})
	if not get_tree().get_nodes_in_group("nkt_cells").is_empty():
		_cached_legend.append({"color": COLOR_NKT, "label": "NKT"})


func _draw_legend() -> void:
	var entries: Array[Dictionary] = _cached_legend
	if entries.is_empty():
		_rebuild_legend_cache()
		entries = _cached_legend

	var font := ThemeDB.fallback_font
	var top := size.y - LEGEND_HEIGHT
	var col_width := size.x * 0.5

	var col := 0
	var row := 0
	for i in range(entries.size()):
		var x := INNER_PAD + float(col) * col_width
		var baseline := top + 11.0 + float(row) * 11.0
		_draw_legend_item(font, x, baseline, entries[i]["color"], entries[i]["label"], 10)

		col += 1
		if col >= 2:
			col = 0
			row += 1

	var legend_note := "GREEN = UNINFECTED HOST CELL"
	draw_string(
		font,
		Vector2(INNER_PAD, size.y - 3.0),
		legend_note,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		COLOR_LABEL
	)


func _draw_legend_item(
	font: Font, x: float, baseline_y: float, color: Color, label: String, font_size: int
) -> void:
	draw_rect(Rect2(x, baseline_y - 8.0, 8.0, 8.0), color)
	draw_rect(Rect2(x, baseline_y - 8.0, 8.0, 8.0), COLOR_BORDER, false, 1.0)
	draw_string(
		font,
		Vector2(x + 12.0, baseline_y),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		COLOR_LABEL
	)
