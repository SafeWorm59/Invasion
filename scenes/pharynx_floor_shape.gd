@tool
extends Polygon2D
const Map := preload("res://scenes/pharynx_map.gd")

## Holds the merged walkable contour as real `polygon` data. The visible cavity
## is painted by the tissue shader, so this node stays transparent by default,
## but the exact same contour remains available to any layer that needs it.

@export var floor_color: Color = Color(0.0, 0.0, 0.0, 0.0)


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	polygon = Map.floor_polygon()
	color = floor_color
	queue_redraw()
