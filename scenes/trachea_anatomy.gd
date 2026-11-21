@tool
extends Node2D
const Map := preload("res://scenes/trachea_map.gd")

## Tracheal landmark relief.
##
## Draws the recognizable surface anatomy of the windpipe on top of the tissue
## shader: C-shaped hyaline cartilage rings, the posterior membranous wall with
## its trachealis muscle, the ciliated epithelial lining, goblet cells, mucus
## patches and the carina where the airway splits into the two main bronchi.
##
## Everything is expressed relative to the shared map, so the relief always
## lands on the visible lumen and the collision wall. These are mucosal surface
## features (like the larynx folds' decorative crests) and never protrude into
## the walkable cavity, so they add no collision of their own.

const CARTILAGE := Color(0.82, 0.68, 0.63, 0.52)
const CARTILAGE_HI := Color(0.97, 0.88, 0.83, 0.34)
const CARTILAGE_EDGE := Color(0.34, 0.15, 0.16, 0.55)
const CARTILAGE_SHADOW := Color(0.09, 0.03, 0.04, 0.55)
const POSTERIOR := Color(0.34, 0.12, 0.14, 0.55)
const POSTERIOR_EDGE := Color(0.54, 0.23, 0.24, 0.40)
const MUSCLE := Color(0.60, 0.27, 0.28, 0.38)
const MUSCLE_HI := Color(0.78, 0.42, 0.42, 0.22)
const CILIA := Color(0.94, 0.70, 0.71, 0.50)
const GOBLET := Color(0.93, 0.80, 0.74, 0.62)
const GOBLET_HI := Color(1.0, 0.93, 0.88, 0.55)
const MUCUS := Color(0.96, 0.80, 0.76, 0.12)
const MUCUS_HI := Color(1.0, 0.91, 0.87, 0.20)
const CARINA := Color(0.70, 0.50, 0.46, 0.52)
const CARINA_HI := Color(0.95, 0.84, 0.78, 0.35)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_posterior_wall()
	_draw_cartilage_rings()
	_draw_trachealis()
	_draw_cilia()
	_draw_goblet_cells()
	_draw_mucus()
	_draw_carina()


# --------------------------------------------------------------------------
# Posterior membranous wall
# --------------------------------------------------------------------------

func _draw_posterior_wall() -> void:
	var band := Map.posterior_band()
	if band.size() < 3:
		return

	draw_colored_polygon(band, POSTERIOR)

	var rim := _closed(band)
	draw_polyline(rim, POSTERIOR_EDGE, 2.0, true)

	# The anterior (cartilage) side of the band gets a soft pale lip so the
	# transition from C-ring to membrane is legible.
	var lip := PackedVector2Array()
	for i in range(Map.RING_COUNT):
		lip.append(Vector2(Map.posterior_inner_x(i), Map.ring_y(i)))
	draw_polyline(lip, CARTILAGE_HI, 2.5, true)


func _draw_trachealis() -> void:
	# Longitudinal smooth-muscle fibres bridging the open ends of the C-rings.
	var first_y := Map.ring_y(0) - 250.0
	var last_y := Map.ring_y(Map.RING_COUNT - 1) + 250.0

	for f in range(5):
		var frac := 0.18 + 0.16 * float(f)
		var path := PackedVector2Array()
		var y := first_y
		while y <= last_y:
			var x := _posterior_x_at(y, frac)
			x += sin(y * 0.0085 + float(f) * 1.7) * 5.0
			path.append(Vector2(x, y))
			y += 90.0
		if path.size() >= 2:
			draw_polyline(path, MUSCLE, 3.2, true)
			var hi := PackedVector2Array()
			for p in path:
				hi.append(p + Vector2(-1.0, 0.0))
			draw_polyline(hi, MUSCLE_HI, 1.1, true)


func _posterior_x_at(y: float, frac: float) -> float:
	var k := 0
	while k < Map.RING_COUNT - 2 and y > Map.ring_y(k + 1):
		k += 1
	var y0 := Map.ring_y(k)
	var y1 := Map.ring_y(k + 1)
	var t := clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)
	var inner := lerpf(Map.posterior_inner_x(k), Map.posterior_inner_x(k + 1), t)
	var outer := lerpf(Map.posterior_outer_x(k), Map.posterior_outer_x(k + 1), t)
	return lerpf(inner, outer, frac)


# --------------------------------------------------------------------------
# C-shaped hyaline cartilage rings
# --------------------------------------------------------------------------

func _draw_cartilage_rings() -> void:
	for i in range(Map.RING_COUNT):
		var band := _ring_band(i, Map.RING_THICKNESS, Map.RING_BOW)

		var shadow := PackedVector2Array()
		for p in band:
			shadow.append(p + Vector2(0.0, 8.0))
		draw_colored_polygon(shadow, CARTILAGE_SHADOW)

		draw_colored_polygon(band, CARTILAGE)
		draw_polyline(_closed(band), CARTILAGE_EDGE, 1.6, true)

		var crest := _ring_curve(i, Map.RING_BOW)
		draw_polyline(crest, CARTILAGE_HI, 2.4, true)

		# Rounded ends of the C: the open ends face the posterior membrane.
		var left_end := Vector2(Map.ring_center_x(i) - Map.ring_half_width(i), Map.ring_y(i))
		var right_end := Vector2(Map.ring_gap_x(i), Map.ring_y(i))
		for end in [left_end, right_end]:
			draw_circle(end, Map.RING_THICKNESS * 0.44, CARTILAGE)
			draw_arc(end, Map.RING_THICKNESS * 0.44, 0.0, TAU, 18, CARTILAGE_EDGE, 1.4, true)


func _ring_curve(i: int, bow: float) -> PackedVector2Array:
	var cx := Map.ring_center_x(i)
	var half := Map.ring_half_width(i)
	var gap := Map.ring_gap_x(i)
	var y := Map.ring_y(i)
	var pts := PackedVector2Array()
	var steps := 28
	for k in range(steps):
		var t := float(k) / float(steps - 1)
		var x := lerpf(cx - half, gap, t)
		var arc := -(1.0 - pow(t * 2.0 - 1.0, 2.0)) * bow
		pts.append(Vector2(x, y + arc))
	return pts


func _ring_band(i: int, thickness: float, bow: float) -> PackedVector2Array:
	var curve := _ring_curve(i, bow)
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var n := curve.size()

	for k in range(n):
		var t := float(k) / float(n - 1)
		var th := thickness * (0.62 + 0.38 * sin(t * PI))
		top.append(curve[k] + Vector2(0.0, -th * 0.5))
		bottom.append(curve[k] + Vector2(0.0, th * 0.5))

	var poly := PackedVector2Array()
	poly.append_array(top)
	for k in range(bottom.size() - 1, -1, -1):
		poly.append(bottom[k])
	return poly


# --------------------------------------------------------------------------
# Ciliated epithelium, goblet cells and mucus
# --------------------------------------------------------------------------

func _draw_cilia() -> void:
	var samples := Map.boundary_samples()
	if samples.is_empty():
		return

	var step := maxi(1, samples.size() / 260)
	for i in range(0, samples.size(), step):
		var p := samples[i]
		var center_x := _tube_center_x_at(p.y)
		var half := _tube_half_at(p.y)
		if p.x > center_x + half * 0.50:
			continue

		var e := 5.0
		var gx := Map.cavity_sdf(p + Vector2(e, 0.0)) - Map.cavity_sdf(p - Vector2(e, 0.0))
		var gy := Map.cavity_sdf(p + Vector2(0.0, e)) - Map.cavity_sdf(p - Vector2(0.0, e))
		var grad := Vector2(gx, gy)
		if grad.length() < 0.0001:
			continue
		var inward := -grad.normalized()
		var side := inward.rotated(PI * 0.5)
		var length := 8.0 + 3.0 * sin(float(i) * 0.7)
		var tip := p + inward * length + side * sin(float(i) * 1.3) * 2.4
		draw_line(p, tip, CILIA, 1.0, true)


func _draw_goblet_cells() -> void:
	var samples := Map.boundary_samples()
	if samples.is_empty():
		return

	var step := maxi(1, samples.size() / 34)
	for i in range(step, samples.size(), step):
		var p := samples[i]
		var center_x := _tube_center_x_at(p.y)
		var half := _tube_half_at(p.y)
		if p.x > center_x + half * 0.48:
			continue

		var e := 5.0
		var gx := Map.cavity_sdf(p + Vector2(e, 0.0)) - Map.cavity_sdf(p - Vector2(e, 0.0))
		var gy := Map.cavity_sdf(p + Vector2(0.0, e)) - Map.cavity_sdf(p - Vector2(0.0, e))
		var grad := Vector2(gx, gy)
		if grad.length() < 0.0001:
			continue
		var inward := -grad.normalized()
		var c := p + inward * 24.0

		draw_colored_polygon(_ellipse(c, 5.5, 8.5, 14), GOBLET)
		draw_circle(c + Vector2(-1.5, -2.0), 1.8, GOBLET_HI)

		# A small mucus droplet sitting on the goblet cell.
		draw_circle(c + inward * 9.0, 3.2, MUCUS_HI)


func _draw_mucus() -> void:
	# Mucociliary streams running up the anterior mucosa.
	for s in range(3):
		var path := PackedVector2Array()
		var y := Map.ring_y(0) - 220.0
		while y <= Map.ring_y(Map.RING_COUNT - 1) + 220.0:
			var cx := _tube_center_x_at(y)
			var half := _tube_half_at(y)
			var x := cx - half * (0.34 + 0.18 * float(s))
			x += sin(y * 0.006 + float(s) * 2.1) * 16.0
			path.append(Vector2(x, y))
			y += 110.0
		if path.size() >= 2:
			draw_polyline(path, MUCUS_HI, 2.0, true)

	# Soft translucent mucus patches.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120
	for i in range(Map.RING_COUNT):
		var count := 2 + (i % 2)
		for k in range(count):
			var cx := Map.ring_center_x(i)
			var half := Map.ring_half_width(i)
			var x := cx + rng.randf_range(-half * 0.62, half * 0.48)
			var y := Map.ring_y(i) + rng.randf_range(-190.0, 190.0)
			var rx := rng.randf_range(22.0, 48.0)
			var ry := rng.randf_range(7.0, 14.0)
			draw_colored_polygon(_ellipse(Vector2(x, y), rx, ry, 20), MUCUS)
			draw_colored_polygon(
				_ellipse(Vector2(x - rx * 0.22, y - ry * 0.20), rx * 0.42, ry * 0.34, 14),
				MUCUS_HI
			)


# --------------------------------------------------------------------------
# Carina and main bronchi
# --------------------------------------------------------------------------

func _draw_carina() -> void:
	var c := Map.chamber_center(Map.carina_chamber())

	# The carinal spur: the ridge that divides the airway into the two bronchi.
	var spur := PackedVector2Array([
		Vector2(c.x, c.y - 190.0),
		Vector2(c.x - 118.0, c.y + 20.0),
		Vector2(c.x - 46.0, c.y + 210.0),
		Vector2(c.x, c.y + 150.0),
		Vector2(c.x + 46.0, c.y + 210.0),
		Vector2(c.x + 118.0, c.y + 20.0),
	])
	draw_colored_polygon(spur, CARINA)
	draw_polyline(_closed(spur), CARINA_HI, 2.6, true)

	# A soft central highlight down the spur.
	draw_polyline(
		PackedVector2Array([
			Vector2(c.x, c.y - 160.0),
			Vector2(c.x, c.y + 120.0),
		]),
		CARINA_HI,
		3.0,
		true
	)

	# Bronchial cartilage: incomplete rings around each main bronchus.
	for side in [-1.0, 1.0]:
		var center := Vector2(c.x + side * 420.0, c.y + 440.0)
		for k in range(3):
			var rx := 168.0 + float(k) * 26.0
			var ry := 196.0 + float(k) * 26.0
			var ring := _ellipse(center, rx, ry, 44)
			draw_polyline(_closed(ring), CARTILAGE, 7.0, true)
			draw_polyline(_closed(ring), CARTILAGE_HI, 2.0, true)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _tube_center_x_at(y: float) -> float:
	var k := 0
	while k < Map.RING_COUNT - 2 and y > Map.ring_y(k + 1):
		k += 1
	var y0 := Map.ring_y(k)
	var y1 := Map.ring_y(k + 1)
	var t := clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)
	return lerpf(Map.ring_center_x(k), Map.ring_center_x(k + 1), t)


func _tube_half_at(y: float) -> float:
	var k := 0
	while k < Map.RING_COUNT - 2 and y > Map.ring_y(k + 1):
		k += 1
	var y0 := Map.ring_y(k)
	var y1 := Map.ring_y(k + 1)
	var t := clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)
	return lerpf(Map.ring_half_width(k), Map.ring_half_width(k + 1), t)


func _ellipse(c: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
