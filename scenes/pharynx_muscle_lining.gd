
@tool
extends Node2D

@export var floor_path: NodePath = NodePath("../Floor")

# Cell spacing and dimensions
@export var cell_spacing: float = 54.0
@export var min_cell_length: float = 42.0
@export var max_cell_length: float = 66.0
@export var cell_width: float = 24.0
@export var wall_offset: float = 5.0

# Appearance — pharynx uses warmer, deeper tissue tones
@export var muscle_color: Color = Color("#E89DAD")
@export var outline_color: Color = Color("#C46B7D")
@export var nucleus_color: Color = Color("#C46B7D")
@export_range(1.0, 20.0, 1.0) var outline_width: float = 4.0

@export_range(1.0, 20.0, 1.0) var corner_radius: float = 7.0
@export_range(4, 12, 1) var corner_segments: int = 6
@export_range(0.0, 0.4, 0.01) var nucleus_offset_amount: float = 0.18

var _cell_data: Array[Dictionary] = []
var _last_signature: String = ""


func _ready() -> void:
	_rebuild_cells()


func _process(_delta: float) -> void:
	var signature := _get_geometry_signature()
	if signature != _last_signature:
		_rebuild_cells()


func _get_geometry_signature() -> String:
	var floor_node := get_node_or_null(floor_path) as Polygon2D

	if floor_node == null:
		return ""

	return str(
		floor_node.polygon, floor_node.global_transform,
		global_transform,
		cell_spacing, min_cell_length, max_cell_length,
		cell_width, wall_offset, outline_width
	)


func _rebuild_cells() -> void:
	_cell_data.clear()

	var floor_node := get_node_or_null(floor_path) as Polygon2D

	if floor_node == null:
		_last_signature = _get_geometry_signature()
		queue_redraw()
		return

	if floor_node.polygon.size() < 3:
		_last_signature = _get_geometry_signature()
		queue_redraw()
		return

	var floor_points := _get_local_points(floor_node)

	var rng := RandomNumberGenerator.new()
	rng.seed = 420721

	_add_cells_along_outline(floor_points, rng)

	_last_signature = _get_geometry_signature()
	queue_redraw()


func _get_local_points(poly: Polygon2D) -> PackedVector2Array:
	var result := PackedVector2Array()

	for point: Vector2 in poly.polygon:
		result.append(to_local(poly.to_global(point)))

	return result


func _add_cells_along_outline(
	points: PackedVector2Array,
	rng: RandomNumberGenerator
) -> void:
	if points.size() < 3:
		return

	var signed_area := 0.0

	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		signed_area += a.x * b.y - b.x * a.y

	var orientation := 1.0 if signed_area > 0.0 else -1.0

	var spacing := maxf(
		cell_spacing,
		min_cell_length + 2.0
	)

	for i in range(points.size()):
		var start: Vector2 = points[i]
		var finish: Vector2 = points[(i + 1) % points.size()]
		var edge: Vector2 = finish - start
		var edge_length := edge.length()

		if edge_length < 1.0:
			continue

		var tangent := edge / edge_length
		var outward := Vector2(tangent.y, -tangent.x) * orientation

		var count := maxi(1, int(ceil(edge_length / spacing)))
		var slot_length := edge_length / float(count)

		for j in range(count):
			var center := (
				start
				+ tangent * ((float(j) + 0.5) * slot_length)
				+ outward * wall_offset
			)

			var available_length := maxf(
				8.0,
				slot_length - 2.0
			)
			var upper_length := minf(
				max_cell_length,
				available_length
			)
			var lower_length := minf(
				min_cell_length,
				upper_length
			)

			var actual_length := rng.randf_range(
				lower_length,
				upper_length
			)

			var nucleus_offset := Vector2(
				rng.randf_range(
					-actual_length * nucleus_offset_amount,
					actual_length * nucleus_offset_amount
				),
				rng.randf_range(
					-cell_width * 0.12,
					cell_width * 0.12
				)
			)

			_cell_data.append({
				"center": center,
				"tangent": tangent,
				"length": actual_length,
				"width": cell_width,
				"nucleus_offset": nucleus_offset
			})


func _draw() -> void:
	for cell: Dictionary in _cell_data:
		_draw_muscle_cell(
			cell["center"] as Vector2,
			cell["tangent"] as Vector2,
			float(cell["length"]),
			float(cell["width"]),
			cell["nucleus_offset"] as Vector2
		)


func _draw_muscle_cell(
	center: Vector2,
	tangent: Vector2,
	actual_length: float,
	actual_width: float,
	nucleus_offset: Vector2
) -> void:
	var normal := Vector2(-tangent.y, tangent.x)
	var half_length := actual_length * 0.5
	var half_width := actual_width * 0.5
	var radius := minf(
		corner_radius,
		minf(half_length, half_width)
	)

	var corner_centers: Array[Vector2] = [
		Vector2(half_length - radius, -half_width + radius),
		Vector2(half_length - radius, half_width - radius),
		Vector2(-half_length + radius, half_width - radius),
		Vector2(-half_length + radius, -half_width + radius)
	]

	var start_angles: Array[float] = [-90.0, 0.0, 90.0, 180.0]
	var shape := PackedVector2Array()

	for corner in range(4):
		var corner_center: Vector2 = corner_centers[corner]

		for segment in range(corner_segments + 1):
			var angle := deg_to_rad(
				start_angles[corner]
				+ 90.0 * float(segment) / float(corner_segments)
			)

			var local_point := corner_center + Vector2(
				cos(angle), sin(angle)
			) * radius

			shape.append(
				center
				+ tangent * local_point.x
				+ normal * local_point.y
			)

	draw_colored_polygon(shape, muscle_color)

	if not shape.is_empty():
		var outline_points := shape.duplicate()
		outline_points.append(shape[0])

		draw_polyline(
			outline_points,
			outline_color,
			outline_width,
			true
		)

	# Nucleus
	var nucleus_center := (
		center
		+ tangent * nucleus_offset.x
		+ normal * nucleus_offset.y
	)

	var nucleus := PackedVector2Array()
	var nucleus_length := actual_length * 0.30
	var nucleus_width := actual_width * 0.34

	for i in range(13):
		var angle := TAU * float(i) / 12.0
		nucleus.append(
			nucleus_center
			+ tangent * cos(angle) * nucleus_length * 0.5
			+ normal * sin(angle) * nucleus_width * 0.5
		)

	draw_colored_polygon(nucleus, nucleus_color)
