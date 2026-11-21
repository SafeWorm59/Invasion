
@tool
extends Polygon2D

func _ready() -> void:
	color = Color("#3D1A28")

	print("Pharynx Floor points: ", polygon.size())
	print("Pharynx Floor visible: ", visible)
	print("Pharynx Floor color: ", color)
	print("Pharynx Floor global position: ", global_position)

func _draw() -> void:
	pass
