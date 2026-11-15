
@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#49202F")

	print("Points: ", polygon.size())
	print("Visible: ", visible)
	print("Color: ", color)
	print("Global position: ", global_position)

func _draw() -> void:
	pass
