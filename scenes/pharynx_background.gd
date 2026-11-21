@tool
extends ColorRect
const Map := preload("res://scenes/pharynx_map.gd")

## Distant tissue beyond the painted wall. It only has to be a calm, dark field
## that matches the outermost wall gradient, so the camera never sees a hard
## rectangle or a void outside the organ.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Map.bounds()
	if box.size == Vector2.ZERO:
		return
	box = box.grow(4200.0)
	position = box.position
	size = box.size
	color = Color("#0A0309")
