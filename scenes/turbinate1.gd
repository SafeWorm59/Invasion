
@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#9B4658")

	print("Points: ", polygon.size())
	print("Visible: ", visible)
	print("Color: ", color)
