@tool
extends Node2D
const Map := preload("res://scenes/pharynx_map.gd")

## Regional mucosal relief for one anatomical region.
##
## Each chamber gets a very soft bowl, two faint wall contours and a handful of
## transverse rugae. All of it is drawn at low alpha with no bright edges: it is
## there to describe the surface of the organ, not to advertise itself as an
## object. Corridors get a barely visible central shadow so passages read as
## tubes rather than flat bridges.

@export var region: int = 1
@export var ruga_color: Color = Color(0.56, 0.27, 0.33, 0.10)
@export var shadow_color: Color = Color(0.035, 0.012, 0.020, 0.28)
@export var depth_color: Color = Color(0.030, 0.010, 0.018, 0.075)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3300 + region * 97

	for i in range(Map.chamber_count()):
		if Map.chamber_region(i) != region:
			continue
		_draw_chamber(i, rng)

	for i in range(Map.corridor_count()):
		if Map.corridor_region(i) != region:
			continue
		_draw_corridor(i)


func _ellipse(center: Vector2, rx: float, ry: float, segments: int = 56) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_chamber(index: int, rng: RandomNumberGenerator) -> void:
	var c := Map.chamber_center(index)
	var r := Map.chamber_radii(index)

	# Soft central depth so the chamber reads as a bowl, not a painted disc.
	draw_colored_polygon(_ellipse(c, r.x * 0.70, r.y * 0.66), depth_color)

	# Two low-contrast contours that follow the chamber wall.
	for k in [0.90, 0.79]:
		var ring := _ellipse(c, r.x * k, r.y * k, 64)
		ring.append(ring[0])
		draw_polyline(
			ring,
			Color(ruga_color.r, ruga_color.g, ruga_color.b, 0.05),
			6.0, true
		)

	# Transverse rugae: broad, soft folds across the floor of the chamber.
	var count := 3 + int(r.y / 420.0)
	for j in range(count):
		var v := lerpf(-0.60, 0.60, (float(j) + 0.5) / float(count))
		v += rng.randf_range(-0.045, 0.045)
		var half := r.x * 0.76 * sqrt(maxf(0.04, 1.0 - v * v))
		var y := c.y + v * r.y
		var bow := rng.randf_range(-10.0, 10.0)
		var points := PackedVector2Array()
		var widths := PackedFloat32Array()
		var steps := 15
		var w := rng.randf_range(26.0, 44.0)
		for s in range(steps):
			var t := float(s) / float(steps - 1)
			var x := c.x + lerpf(-half, half, t)
			var wobble := sin(t * 3.4 + float(j) * 1.9) * 7.0
			points.append(Vector2(x, y + bow * (1.0 - t * t) + wobble))
			widths.append(w * pow(sin(PI * t), 0.6))

		var shadow := PackedVector2Array()
		for p in points:
			shadow.append(p + Vector2(0.0, 6.0))
		draw_colored_polygon(Map.ribbon(shadow, widths), shadow_color)
		draw_colored_polygon(Map.ribbon(points, widths), ruga_color)


func _draw_corridor(index: int) -> void:
	var a := Map.corridor_a(index)
	var b := Map.corridor_b(index)
	var w := Map.corridor_width(index)
	draw_colored_polygon(
		Map.ribbon(PackedVector2Array([a, b]), PackedFloat32Array([w * 0.5, w * 0.5])),
		Color(depth_color.r, depth_color.g, depth_color.b, 0.05)
	)
