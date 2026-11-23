@tool
extends ColorRect

const Map := preload("res://scenes/lungs_map.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := Map.bounds().grow(4200.0)
	position = box.position
	size = box.size
	color = Color("#0A0406")
