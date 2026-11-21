@tool
extends Node2D
const Map := preload("res://scenes/pharynx_map.gd")

## Nasopharyngeal detail: choanal depressions, paired pharyngeal recesses and a
## few soft arcs across the vault roof. Everything is expressed relative to the
## owning chamber, so one script works for every recess in the upper region.
##
## The shapes are recesses (darker than the floor) with low-alpha rims, not
## lit objects, and they are part of the wall rather than an entrance marker.

@export var chamber_index: int = 0
@export var style: int = 0  ## 0 = vault with choanae, 1 = recess pair
@export var deep_color: Color = Color(0.055, 0.018, 0.038, 1.0)
@export var recess_color: Color = Color(0.100, 0.034, 0.066, 1.0)
@export var rim_color: Color = Color(0.55, 0.32, 0.38, 0.16)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var c := Map.chamber_center(chamber_index)
	var r := Map.chamber_radii(chamber_index)
	if style == 0:
		_draw_choanae(c, r)
	_draw_recesses(c, r)
	if style == 0:
		_draw_vault_arcs(c, r)


func _ellipse(center: Vector2, rx: float, ry: float, segments: int = 30) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_choanae(c: Vector2, r: Vector2) -> void:
	var cy := c.y - r.y * 0.64
	var rxo := r.x * 0.085
	var ryo := r.y * 0.070
	for side in [-1.0, 1.0]:
		var center := Vector2(c.x + side * r.x * 0.27, cy)
		draw_colored_polygon(_ellipse(center, rxo * 1.16, ryo * 1.18), Color(0.15, 0.055, 0.09, 0.55))
		draw_colored_polygon(_ellipse(center, rxo, ryo), recess_color)
		draw_colored_polygon(_ellipse(center, rxo * 0.62, ryo * 0.60), deep_color)
		var rim := _ellipse(center, rxo * 1.05, ryo * 1.07, 30)
		rim.append(rim[0])
		draw_polyline(rim, rim_color, 2.5, true)

	var septum := _ellipse(Vector2(c.x, cy), r.x * 0.016, r.y * 0.080)
	draw_colored_polygon(septum, Color(0.36, 0.19, 0.23, 0.30))


func _draw_recesses(c: Vector2, r: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var center := Vector2(c.x + side * r.x * 0.58, c.y - r.y * 0.04)
		draw_set_transform(center, side * 0.35, Vector2(1.0, 1.0))
		draw_colored_polygon(_ellipse(Vector2.ZERO, r.x * 0.105, r.y * 0.055), recess_color)
		draw_colored_polygon(_ellipse(Vector2.ZERO, r.x * 0.063, r.y * 0.028), deep_color)
		draw_polyline(
			_ellipse(Vector2.ZERO, r.x * 0.108, r.y * 0.060, 28),
			Color(rim_color.r, rim_color.g, rim_color.b, 0.12), 2.0, true
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_vault_arcs(c: Vector2, r: Vector2) -> void:
	for i in range(4):
		var v: float = lerpf(-0.86, -0.68, float(i) / 3.0)
		var half: float = r.x * sqrt(maxf(0.05, 1.0 - v * v)) * lerpf(0.52, 0.86, float(i) / 3.0)
		var pts := PackedVector2Array()
		for j in range(13):
			var t := lerpf(-1.0, 1.0, float(j) / 12.0)
			pts.append(Vector2(c.x + t * half, c.y + v * r.y - (1.0 - t * t) * r.y * 0.022))
		draw_polyline(pts, Color(0.62, 0.36, 0.42, 0.065), 3.0, true)
