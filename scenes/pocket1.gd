
@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#49202f")

	print("Pocket1 points: ", polygon.size())
	print("Pocket1 position: ", global_position)
	print("Pocket1 visible: ", visible)
