@tool
extends Node2D
const Map := preload("res://scenes/larynx_map.gd")

## Raised mucosal folds inside the larynx chambers (the vestibular and vocal
## folds and a few cricoid ridges). They are drawn as soft tapered ribbons of
## tissue with a shadowed base and a muted crest, matching the tissue shader's
## low-contrast palette. These are the only decorative structures with
## collision (see larynx_body.gd, ridges mode).

@export var body_color: Color = Color(0.360, 0.160, 0.205, 0.94)
@export var crest_color: Color = Color(0.560, 0.290, 0.350, 0.30)
@export var shadow_color: Color = Color(0.030, 0.010, 0.018, 0.45)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	for i in range(Map.barrier_count()):
		var path := Map.barrier_path(i)
		var widths := Map.barrier_widths(i)
		if path.size() < 2:
			continue

		# Soft shadow under the fold.
		var shadow := Map.ribbon(_offset(path, Vector2(0.0, 10.0)), widths)
		if shadow.size() >= 3:
			draw_colored_polygon(shadow, shadow_color)

		# The fold body.
		var body := Map.ribbon(path, widths)
		if body.size() >= 3:
			draw_colored_polygon(body, body_color)

		# A dull crest highlight along the centre line.
		var crest_path := _offset(path, Vector2(0.0, -3.0))
		var crest_w := PackedFloat32Array()
		for w in widths:
			crest_w.append(w * 0.34)
		var crest := Map.ribbon(crest_path, crest_w)
		if crest.size() >= 3:
			draw_colored_polygon(crest, crest_color)


func _offset(path: PackedVector2Array, delta: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in path:
		out.append(p + delta)
	return out