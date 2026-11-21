
extends StaticBody2D

@export var wall_thickness: float = 16.0

@onready var floor_polygon: Polygon2D = get_node("../Floor")


func _ready() -> void:
	var floor_points := _get_global_points(floor_polygon)

	if floor_points.is_empty():
		push_error("PharynxBoundaryWalls: Floor polygon is empty.")
		return

	for child in get_children():
		child.queue_free()

	_create_boundary(floor_points)


func _get_global_points(poly: Polygon2D) -> PackedVector2Array:
	var result := PackedVector2Array()

	for point in poly.polygon:
		result.append(to_local(poly.to_global(point)))

	return result


func _create_boundary(points: PackedVector2Array) -> void:
	for i in range(points.size()):
		var start_point := points[i]
		var end_point := points[(i + 1) % points.size()]
		var edge := end_point - start_point

		if edge.length() < 1.0:
			continue

		var wall := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()

		rectangle.size = Vector2(
			edge.length() + wall_thickness,
			wall_thickness
		)

		wall.shape = rectangle
		wall.position = (start_point + end_point) / 2.0
		wall.rotation = edge.angle()

		add_child(wall)
