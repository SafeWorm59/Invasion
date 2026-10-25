
extends StaticBody2D

@export var wall_size: Vector2 = Vector2(160, 80)
@export var corner_radius: float = 18.0

func _ready() -> void:
	update_wall()

func update_wall() -> void:
	var collision := get_node_or_null("CollisionShape2D")
	if collision and collision.shape is RectangleShape2D:
		collision.shape.size = wall_size

	queue_redraw()

func _draw() -> void:
	var half := wall_size / 2.0
	var r: float = minf(corner_radius, minf(half.x, half.y))
	var points := PackedVector2Array()

	# Four rounded corners.
	var centers := [
		Vector2(half.x - r, -half.y + r),
		Vector2(half.x - r, half.y - r),
		Vector2(-half.x + r, half.y - r),
		Vector2(-half.x + r, -half.y + r)
	]

	var starts := [-90.0, 0.0, 90.0, 180.0]

	for i in range(4):
		for step in range(7):
			var angle := deg_to_rad(
				starts[i] + float(step) * 90.0 / 6.0
			)
			points.append(
				centers[i] + Vector2(cos(angle), sin(angle)) * r
			)

	# Outer fleshy wall.
	draw_colored_polygon(points, Color("#963b59"))

	# Smaller inner surface.
	draw_rect(
		Rect2(Vector2(-half.x + 8, -half.y + 8),
			  Vector2(wall_size.x - 16, wall_size.y - 16)),
		Color("#c96783")
	)

	# Subtle highlight.
	draw_line(
		Vector2(-half.x + r, -half.y + 5),
		Vector2(half.x - r, -half.y + 5),
		Color("#ed9bad"),
		3.0
	)
