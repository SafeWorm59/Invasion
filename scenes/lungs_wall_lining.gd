extends Node2D

const Map := preload("res://scenes/lungs_map.gd")

const CELL_SPACING := 38.0
const CELL_WIDTH := 24.0
const MIN_CELL_LENGTH := 16.0
const MAX_CELL_LENGTH := 44.0
const CULL_MARGIN := 100.0
const CAMERA_UPDATE_DISTANCE := 24.0
const CELL_FILL := Color("#F4A6C1")
const CELL_VARIATION := Color("#E889A8")
const CELL_OUTLINE := Color("#AD5478")
const CELL_NUCLEUS := Color("#AD5478")

var _cells: Array[Dictionary] = []
var _draw_bounds := Rect2()
var _last_camera_position := Vector2.ZERO
var _last_camera_zoom := Vector2.ZERO
var _last_viewport_size := Vector2.ZERO
var _has_camera_state := false


func _ready() -> void:
	_build_cells()
	_update_draw_bounds()
	queue_redraw()


func _process(_delta: float) -> void:
	_update_draw_bounds()


func _update_draw_bounds() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		var map_bounds := Map.bounds().grow(CULL_MARGIN)
		if _draw_bounds != map_bounds:
			_draw_bounds = map_bounds
			queue_redraw()
		return

	var viewport_size := get_viewport_rect().size
	var camera_position := camera.get_screen_center_position()
	var camera_zoom := camera.zoom
	var camera_moved := (
		not _has_camera_state
		or camera_position.distance_squared_to(_last_camera_position)
		>= CAMERA_UPDATE_DISTANCE * CAMERA_UPDATE_DISTANCE
	)
	if (
		not camera_moved
		and camera_zoom == _last_camera_zoom
		and viewport_size == _last_viewport_size
	):
		return

	_has_camera_state = true
	_last_camera_position = camera_position
	_last_camera_zoom = camera_zoom
	_last_viewport_size = viewport_size
	var world_view_size := viewport_size / camera_zoom
	_draw_bounds = Rect2(
		camera_position - world_view_size * 0.5,
		world_view_size
	).grow(CULL_MARGIN)
	queue_redraw()


func _build_cells() -> void:
	_cells.clear()
	var segments := Map.wall_segments()
	var rng := RandomNumberGenerator.new()
	rng.seed = 240619
	var path := PackedVector2Array()

	for segment_index in range(0, segments.size(), 2):
		var start: Vector2 = segments[segment_index]
		var finish: Vector2 = segments[segment_index + 1]
		if path.is_empty():
			path.append(start)
			path.append(finish)
		elif path[path.size() - 1].distance_to(start) <= 0.5:
			path.append(finish)
		else:
			_build_cells_for_path(path, rng)
			path = PackedVector2Array([start, finish])

	if path.size() >= 2:
		_build_cells_for_path(path, rng)


func _build_cells_for_path(
	path: PackedVector2Array,
	rng: RandomNumberGenerator
) -> void:
	var path_length := 0.0
	for i in range(path.size() - 1):
		path_length += path[i].distance_to(path[i + 1])
	if path_length < MIN_CELL_LENGTH:
		return

	var count := maxi(1, int(ceil(path_length / CELL_SPACING)))
	var slot_length := path_length / float(count)
	for cell_index in range(count):
		var sample := _sample_path(
			path,
			(float(cell_index) + 0.5) * slot_length
		)
		var center: Vector2 = sample["center"]
		var tangent: Vector2 = sample["tangent"]
		var normal := Vector2(-tangent.y, tangent.x)
		var probe_distance := minf(12.0, slot_length * 0.25)
		var inward := normal
		if (
			Map.cavity_sdf(center + normal * probe_distance)
			> Map.cavity_sdf(center - normal * probe_distance)
		):
			inward = -normal

		var cell_length := minf(
			MAX_CELL_LENGTH,
			slot_length * rng.randf_range(0.92, 1.08)
		)
		cell_length = maxf(MIN_CELL_LENGTH, cell_length)
		_cells.append({
			"center": center - inward * (CELL_WIDTH * 0.42),
			"tangent": tangent,
			"length": cell_length,
			"fill": CELL_FILL.lerp(CELL_VARIATION, rng.randf_range(0.0, 0.45)),
			"nucleus_offset": rng.randf_range(-cell_length * 0.16, cell_length * 0.16),
		})


func _sample_path(path: PackedVector2Array, distance: float) -> Dictionary:
	var remaining := distance
	for i in range(path.size() - 1):
		var start := path[i]
		var edge := path[i + 1] - start
		var edge_length := edge.length()
		if edge_length <= 0.001:
			continue
		if remaining <= edge_length:
			return {
				"center": start + edge * (remaining / edge_length),
				"tangent": edge / edge_length,
			}
		remaining -= edge_length

	var last_edge := path[path.size() - 1] - path[path.size() - 2]
	return {
		"center": path[path.size() - 1],
		"tangent": last_edge.normalized(),
	}


func _draw() -> void:
	var wall_segments := Map.wall_segments()
	draw_multiline(wall_segments, CELL_OUTLINE, 8.0, true)
	draw_multiline(wall_segments, CELL_FILL, 3.0, true)

	for cell: Dictionary in _cells:
		var center: Vector2 = cell["center"]
		if not _draw_bounds.has_point(center):
			continue
		var tangent: Vector2 = cell["tangent"]
		var cell_length: float = cell["length"]
		var fill: Color = cell["fill"]
		var shape := _capsule_points(center, tangent, cell_length, CELL_WIDTH)
		var outline := shape.duplicate()
		outline.append(shape[0])
		draw_colored_polygon(shape, fill)
		draw_polyline(outline, CELL_OUTLINE, 2.2, true)

		var normal := Vector2(-tangent.y, tangent.x)
		var nucleus_center := (
			center + tangent * float(cell["nucleus_offset"])
		)
		var nucleus := _ellipse_points(
			nucleus_center,
			tangent,
			cell_length * 0.22,
			CELL_WIDTH * 0.30
		)
		draw_colored_polygon(nucleus, CELL_NUCLEUS)
		draw_line(
			center + normal * (CELL_WIDTH * 0.15),
			center + normal * (CELL_WIDTH * 0.34),
			Color(1.0, 0.84, 0.88, 0.72),
			1.4,
			true
		)


func _capsule_points(
	center: Vector2,
	tangent: Vector2,
	cell_length: float,
	cell_width: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var normal := Vector2(-tangent.y, tangent.x)
	var radius := minf(cell_width * 0.5, cell_length * 0.5)
	var straight_half := maxf(cell_length * 0.5 - radius, 0.0)

	for i in range(7):
		var angle := -PI * 0.5 + PI * float(i) / 6.0
		points.append(
			center
			+ tangent * (straight_half + cos(angle) * radius)
			+ normal * (sin(angle) * radius)
		)
	for i in range(7):
		var angle := PI * 0.5 + PI * float(i) / 6.0
		points.append(
			center
			+ tangent * (-straight_half + cos(angle) * radius)
			+ normal * (sin(angle) * radius)
		)

	return points


func _ellipse_points(
	center: Vector2,
	tangent: Vector2,
	length: float,
	width: float
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var normal := Vector2(-tangent.y, tangent.x)
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		points.append(
			center
			+ tangent * cos(angle) * length * 0.5
			+ normal * sin(angle) * width * 0.5
		)
	return points
