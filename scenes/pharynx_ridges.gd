@tool
extends Node2D
const Map := preload("res://scenes/pharynx_map.gd")

## Raised mucosal folds inside the widest chambers.
##
## These are the only decorative structures with collision: they are broad
## wall-attached folds that force the player to weave, and they always leave a
## wide gap on the opposite side. They are drawn as soft tissue with a shadow
## and a muted crest, never as a bright object.

@export var body_color: Color = Color(0.345, 0.155, 0.200, 0.92)
@export var crest_color: Color = Color(0.560, 0.285, 0.345, 0.14)
@export var shadow_color: Color = Color(0.030, 0.010, 0.018, 0.40)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	for i in range(Map.barrier_count()):
		var path := Map.barrier_path(i)
		## Draw as line segments instead of ribbon to avoid triangulation issues
		if path.size() > 1:
			# Draw the central line of the fold
			draw_line(path[0], path[-1], body_color, 4.0)
			# Draw intermediate segments
			for j in range(path.size() - 1):
				draw_line(path[j], path[j + 1], body_color, 4.0)

		# Commented out: crest and shadow drawing for debugging
		# var crest := PackedVector2Array()
		# var crest_w := PackedFloat32Array()
		# for j in range(path.size()):
		# 	crest.append(path[j] - Vector2(0.0, 5.0))
		# 	crest_w.append(widths[j] * 0.34)
		# draw_colored_polygon(Map.ribbon(crest, crest_w), crest_color)
