
@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#D98B9C")

	polygon = PackedVector2Array([
		Vector2(-35, -12),
		Vector2(-22, -22),
		Vector2(-5, -24),
		Vector2(12, -18),
		Vector2(30, -10),
		Vector2(36, 0),
		Vector2(22, 10),
		Vector2(5, 14),
		Vector2(-15, 10),
		Vector2(-30, 3)
	])
