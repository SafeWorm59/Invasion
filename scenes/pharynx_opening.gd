@tool
extends Node2D
const Shape := preload("res://scenes/pharynx_shape.gd")

## A recessed anatomical opening surrounded by mucosal relief.
##
## Three modes share one renderer family so all openings in the level look like
## they belong to the same organ:
##   AUDITORY_TUBE      cartilaginous cushion + dark tube + salpingopharyngeal fold
##   LARYNGEAL_INLET    vestibule, arytenoid bumps, pale vocal folds
##   ESOPHAGEAL_OPENING radially striated sphincter ring around a deep hole

enum OpeningType { AUDITORY_TUBE, LARYNGEAL_INLET, ESOPHAGEAL_OPENING }

@export var opening: OpeningType = OpeningType.AUDITORY_TUBE
@export var opening_radius: float = 32.0
@export var squash: float = 0.62
@export var mirror: bool = false
@export var deep_color: Color = Color("#160710")
@export var wall_color: Color = Color("#35121E")
@export var rim_color: Color = Color("#7A4550")
@export var fold_color: Color = Color("#5E2F39")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if mirror:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))

	match opening:
		OpeningType.AUDITORY_TUBE:
			_draw_auditory_tube()
		OpeningType.LARYNGEAL_INLET:
			_draw_laryngeal_inlet()
		OpeningType.ESOPHAGEAL_OPENING:
			_draw_esophageal_opening()

	if mirror:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ellipse(center: Vector2, rx: float, ry: float, segments: int = 30) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _arc(center: Vector2, rx: float, ry: float, a0: float, a1: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments + 1):
		var a: float = lerpf(a0, a1, float(i) / float(segments))
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_graded_recess(rx: float, ry: float) -> void:
	var layers := [
		[1.0, wall_color],
		[0.72, wall_color.lerp(deep_color, 0.55)],
		[0.44, deep_color],
	]
	for layer in layers:
		var k: float = layer[0]
		draw_colored_polygon(_ellipse(Vector2.ZERO, rx * k, ry * k), layer[1])


func _draw_auditory_tube() -> void:
	var r: float = opening_radius
	var ry: float = r * squash

	# Torus tubarius: the raised cartilaginous cushion arching over the orifice.
	var path := _arc(Vector2.ZERO, r * 1.85, ry * 1.95, PI * 1.12, PI * 1.92, 20)
	var widths := PackedFloat32Array()
	var lip := PackedVector2Array()
	var lip_w := PackedFloat32Array()
	for i in range(path.size()):
		var taper: float = pow(sin(PI * float(i) / float(path.size() - 1)), 0.5)
		widths.append(r * 0.44 * taper)
		lip.append(path[i] + Vector2(0.0, -r * 0.17))
		lip_w.append(r * 0.13 * taper)

	draw_colored_polygon(Shape.ribbon(path, widths), fold_color)
	draw_colored_polygon(
		Shape.ribbon(lip, lip_w),
		Color(rim_color.r, rim_color.g, rim_color.b, 0.12)
	)

	# The tube itself: a dark recess, not a flat disc.
	_draw_graded_recess(r, ry)
	draw_polyline(
		_ellipse(Vector2.ZERO, r, ry, 34),
		Color(rim_color.r, rim_color.g, rim_color.b, 0.10), 2.0, true
	)

	# Salpingopharyngeal fold sweeping down and medially from the orifice.
	var tail := PackedVector2Array([
		Vector2(r * 0.30, ry * 0.72),
		Vector2(r * 0.95, ry * 1.6 + 34.0),
		Vector2(r * 1.85, ry * 1.6 + 96.0),
		Vector2(r * 2.70, ry * 1.6 + 168.0),
	])
	draw_colored_polygon(
		Shape.ribbon(tail, PackedFloat32Array([r * 0.40, r * 0.32, r * 0.20, 0.0])),
		Color(fold_color.r, fold_color.g, fold_color.b, 0.5)
	)


func _draw_laryngeal_inlet() -> void:
	var r: float = opening_radius
	var ry: float = r * squash

	# Soft halo so the inlet sits in a depression.
	for i in range(4):
		var k: float = 1.22 + float(i) * 0.17
		draw_colored_polygon(
			_ellipse(Vector2.ZERO, r * k, ry * k), Color(0.06, 0.01, 0.03, 0.045)
		)

	_draw_graded_recess(r, ry)

	# Aryepiglottic folds sweeping up and outward from the inlet rim.
	for side in [-1.0, 1.0]:
		var p := PackedVector2Array([
			Vector2(side * r * 0.70, -ry * 0.60),
			Vector2(side * r * 1.05, -ry * 1.55),
			Vector2(side * r * 1.45, -ry * 2.60),
		])
		draw_colored_polygon(
			Shape.ribbon(p, PackedFloat32Array([r * 0.17, r * 0.10, 0.0])),
			Color(fold_color.r, fold_color.g, fold_color.b, 0.55)
		)

	# True vocal folds: a pale V opening upward (posteriorly).
	for side in [-1.0, 1.0]:
		var p := PackedVector2Array([
			Vector2(0.0, ry * 0.66),
			Vector2(side * r * 0.30, ry * 0.10),
			Vector2(side * r * 0.60, -ry * 0.28),
		])
		var w := PackedFloat32Array([r * 0.055, r * 0.075, r * 0.02])
		draw_colored_polygon(Shape.ribbon(p, w), Color(0.20, 0.05, 0.10, 0.45))
		var shifted := PackedVector2Array()
		for v in p:
			shifted.append(v - Vector2(0.0, r * 0.05))
		draw_colored_polygon(
			Shape.ribbon(shifted, w),
			Color(0.90, 0.58, 0.68, 0.24)
		)

	# Arytenoid cushions at the upper corners of the inlet.
	for side in [-1.0, 1.0]:
		var c := Vector2(side * r * 0.44, -ry * 0.58)
		draw_circle(c, r * 0.17, fold_color)
		draw_circle(c - Vector2(0.0, r * 0.05), r * 0.07, Color(0.90, 0.58, 0.68, 0.15))

	draw_polyline(
		_ellipse(Vector2.ZERO, r, ry, 36),
		Color(rim_color.r, rim_color.g, rim_color.b, 0.12), 2.5, true
	)


func _draw_esophageal_opening() -> void:
	var r: float = opening_radius
	var ry: float = r * squash

	for i in range(4):
		var k: float = 1.5 + float(i) * 0.22
		draw_colored_polygon(
			_ellipse(Vector2.ZERO, r * k, ry * k), Color(0.05, 0.01, 0.02, 0.08)
		)

	# Radially striated sphincter ring.
	var outer := _ellipse(Vector2.ZERO, r * 1.36, ry * 1.36, 44)
	var inner := _ellipse(Vector2.ZERO, r * 1.02, ry * 1.02, 44)
	var ring := PackedVector2Array()
	ring.append_array(outer)
	for i in range(inner.size() - 1, -1, -1):
		ring.append(inner[i])
	draw_colored_polygon(ring, fold_color)

	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		draw_line(
			Vector2(cos(a) * r * 1.02, sin(a) * ry * 1.02),
			Vector2(cos(a) * r * 1.34, sin(a) * ry * 1.34),
			Color(0.42, 0.13, 0.20, 0.32), 2.0, true
		)

	_draw_graded_recess(r, ry)

	draw_polyline(
		_arc(Vector2.ZERO, r * 1.36, ry * 1.36, PI * 1.08, PI * 1.92, 18),
		Color(rim_color.r, rim_color.g, rim_color.b, 0.15), 3.0, true
	)
