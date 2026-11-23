extends StaticBody2D

const Map := preload("res://scenes/lungs_map.gd")


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	rebuild()


func rebuild() -> void:
	var wall := get_node_or_null("OutlineShape") as CollisionShape2D
	if wall == null:
		wall = CollisionShape2D.new()
		wall.name = "OutlineShape"
		add_child(wall)
	var shape := ConcavePolygonShape2D.new()
	shape.set_segments(Map.wall_segments())
	shape.backface_collision = true
	wall.shape = shape
