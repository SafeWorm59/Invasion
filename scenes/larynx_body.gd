extends StaticBody2D
const Map := preload("res://scenes/larynx_map.gd")

## Physics geometry for the organic cavity.
##
## `outline` mode builds one ConcavePolygonShape2D from the analytic cavity
## boundary: a thin, continuous wall around every chamber and passage, exactly
## on the edge the shader paints. There are no invisible barriers in open space
## because the segments are only emitted where a camera-visible wall exists.
##
## `ridges` mode builds one thin outline per mucosal fold so the folds feel
## solid without blocking the passages they never cross.

@export var ridges: bool = false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	rebuild()


func rebuild() -> void:
	if not ridges:
		_build_outline_wall()
		return
	for child in get_children():
		child.queue_free()
	for i in range(Map.barrier_count()):
		var fold := CollisionShape2D.new()
		fold.name = "Fold%d" % i
		var shape := ConcavePolygonShape2D.new()
		shape.set_segments(_closed_segments(Map.barrier_polygon(i)))
		fold.shape = shape
		add_child(fold)


func _build_outline_wall() -> void:
	var wall := get_node_or_null("OutlineShape") as CollisionShape2D
	if wall == null:
		wall = CollisionShape2D.new()
		wall.name = "OutlineShape"
		add_child(wall)
	var shape := ConcavePolygonShape2D.new()
	shape.set_segments(Map.wall_segments())
	wall.shape = shape


func _closed_segments(poly: PackedVector2Array) -> PackedVector2Array:
	var segs := PackedVector2Array()
	for i in range(poly.size()):
		segs.append(poly[i])
		segs.append(poly[(i + 1) % poly.size()])
	return segs
