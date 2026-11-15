@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#49202F")

	polygon = PackedVector2Array([
		Vector2(-300, -300),
		Vector2(300, -300),
		Vector2(300, 300),
		Vector2(-300, 300)
	])
	
	print("Floor polygon points: ", polygon.size())
