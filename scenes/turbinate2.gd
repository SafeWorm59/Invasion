
@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#B45B68")

	polygon = PackedVector2Array([
		Vector2(-110, -300),
		Vector2(-65, -280),
		Vector2(-30, -245),
		Vector2(-15, -205),
		Vector2(-25, -165),
		Vector2(-55, -135),
		Vector2(-85, -145),
		Vector2(-65, -175),
		Vector2(-60, -205),
		Vector2(-75, -235),
		Vector2(-100, -260)
	])
