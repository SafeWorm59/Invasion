
extends Polygon2D

func _ready() -> void:
	polygon = PackedVector2Array([
		Vector2(-900, -600),
		Vector2(900, -600),
		Vector2(900, 600),
		Vector2(-900, 600)
	])
	color = Color("#30101b")
