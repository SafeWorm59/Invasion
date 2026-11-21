extends StaticBody2D
const Map := preload("res://scenes/trachea_map.gd")

## Physics geometry for the tracheal cavity.
##
## Builds one ConcavePolygonShape2D from the analytic cavity boundary: a thin,
## continuous wall around every tube segment and bronchus, exactly on the edge
## the shader paints. The cartilage rings and the posterior membrane are
## mucosal surface features, so they add no invisible barriers in open space.


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
	wall.shape = shape
