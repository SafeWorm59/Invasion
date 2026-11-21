
@tool
extends Node2D

## Draws a biologically recognizable palatine tonsil with crypts.

@export var tonsil_radius: float = 120.0
@export var tonsil_color: Color = Color("#8A3E4A")
@export var crypt_color: Color = Color("#4A1A24")
@export var outline_color: Color = Color("#3A151D")
@export var outline_width: float = 2.0
@export var num_lobes: int = 8
@export var num_crypts: int = 6
@export var lobe_variation: float = 0.25
@export var crypt_depth: float = 0.35
@export var flip_horizontal: bool = false

var _rng := RandomNumberGenerator.new()


## Binomial low-pass over a closed polygon.
func _smooth(points: PackedVector2Array, passes: int) -> PackedVector2Array:
	var result := points
	var n: int = points.size()
	for _p in range(passes):
		var next_pts := PackedVector2Array()
		for i in range(n):
			var a: Vector2 = result[(i - 1 + n) % n]
			var b: Vector2 = result[i]
			var c: Vector2 = result[(i + 1) % n]
			next_pts.append(a * 0.25 + b * 0.5 + c * 0.25)
		result = next_pts
	return result


func _ready() -> void:
	_rng.seed = hash(name)
	queue_redraw()


func _draw() -> void:
	_rng.seed = hash(name)

	# Draw outer tonsil body with irregular lobes
	var outer_points := PackedVector2Array()
	var segments := num_lobes * 8

	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		if flip_horizontal:
			angle = TAU - angle

		# Create lobulated (bumpy) surface
		var lobe_offset := sin(angle * num_lobes) * tonsil_radius * lobe_variation
		var noise_offset := _rng.randf_range(-tonsil_radius * 0.02, tonsil_radius * 0.02)
		var r := tonsil_radius + lobe_offset + noise_offset

		outer_points.append(Vector2(cos(angle) * r, sin(angle) * r))

	# Smooth the silhouette: the lobulation should stay readable, but the
	# per-vertex noise must not turn the outline into a saw blade.
	outer_points = _smooth(outer_points, 5)

	# Volume: a gently darker rim and a lit dome. The contrast is kept low so the
	# mass sits in the wall instead of popping out like a pick-up.
	var rim_color := Color(
		tonsil_color.r * 0.84, tonsil_color.g * 0.76, tonsil_color.b * 0.80, 1.0
	)
	var dome := PackedVector2Array()
	for p in outer_points:
		dome.append(p * 0.90 + Vector2(-tonsil_radius * 0.015, -tonsil_radius * 0.03))

	draw_colored_polygon(outer_points, rim_color)
	draw_colored_polygon(dome, tonsil_color)

	# Outline
	var outline := outer_points.duplicate()
	outline.append(outer_points[0])
	draw_polyline(
		outline, Color(outline_color.r, outline_color.g, outline_color.b, 0.30),
		outline_width, true
	)

	# Draw tonsillar crypts (darker recesses)
	_rng.seed = hash(name) + 1000
	for i in range(num_crypts):
		var crypt_angle := TAU * float(i) / float(num_crypts) + _rng.randf_range(-0.3, 0.3)
		var crypt_dist := tonsil_radius * _rng.randf_range(0.15, 0.55)
		var crypt_center := Vector2(cos(crypt_angle), sin(crypt_angle)) * crypt_dist
		var crypt_size := tonsil_radius * _rng.randf_range(0.12, 0.22)

		# Irregular crypt shape
		var crypt_points := PackedVector2Array()
		var crypt_segments := 14
		for j in range(crypt_segments):
			var ca := TAU * float(j) / float(crypt_segments)
			var cr := crypt_size * (1.0 + _rng.randf_range(-0.18, 0.18))
			crypt_points.append(crypt_center + Vector2(cos(ca) * cr, sin(ca) * cr * 0.7))

		# Round the crypt opening so it reads as a pit in the tonsil surface.
		crypt_points = _smooth(crypt_points, 2)
		draw_colored_polygon(crypt_points, crypt_color)

		var crypt_outline := crypt_points.duplicate()
		crypt_outline.append(crypt_points[0])
		draw_polyline(
			crypt_outline, Color(outline_color.r, outline_color.g, outline_color.b, 0.22),
			1.2, true
		)

	# Draw a few lymphoid follicles (lighter spots)
	_rng.seed = hash(name) + 2000
	for i in range(2):
		var fa := _rng.randf_range(0.0, TAU)
		var fd := _rng.randf_range(tonsil_radius * 0.1, tonsil_radius * 0.6)
		var fc := Vector2(cos(fa), sin(fa)) * fd
		var fr := _rng.randf_range(12.0, 20.0)
		draw_circle(fc, fr, Color(0.72, 0.40, 0.46, 0.13))
