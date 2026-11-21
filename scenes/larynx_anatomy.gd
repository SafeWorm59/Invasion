@tool
extends Node2D
const Map := preload("res://scenes/larynx_map.gd")

## Larynx landmark relief: the recognizable structures of the voice box painted
## onto the cavity floor so the space reads as a larynx rather than an abstract
## tube. Everything is expressed relative to a chamber, so the shapes scale with
## the anatomy that the shader and the collision shell already share.
##
## Chambers: 0 Epiglottis, 2 Vestibule, 3/4 Vestibular folds, 6/7 Ventricles,
## 8 Vocal folds / glottis, 10 Cricoid, 13/14 Trachea.

const MUCOSA_PALE := Color(0.48, 0.22, 0.27, 0.55)
const MUCOSA_RIM := Color(0.62, 0.34, 0.38, 0.22)
const CARTILAGE := Color(0.66, 0.50, 0.44, 0.30)
const RECESS_DEEP := Color(0.055, 0.018, 0.038, 0.92)
const RECESS := Color(0.105, 0.036, 0.068, 0.85)
const RIM := Color(0.58, 0.32, 0.38, 0.16)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_epiglottis()
	_draw_vestibular_folds()
	_draw_ventricles()
	_draw_vocal_folds()
	_draw_cricoid()
	_draw_tracheal_rings()


func _center(i: int) -> Vector2:
	return Map.chamber_center(i)


func _radii(i: int) -> Vector2:
	return Map.chamber_radii(i)


func _ellipse(c: Vector2, rx: float, ry: float, segments: int = 30) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# The epiglottis: a leaf-shaped flap hanging into the top of the larynx.
func _draw_epiglottis() -> void:
	var c := _center(0)
	var r := _radii(0)
	draw_set_transform(c, 0.0, Vector2.ONE)

	var leaf := PackedVector2Array()
	leaf.append(Vector2(0.0, -r.y * 0.86))
	leaf.append(Vector2(-r.x * 0.30, -r.y * 0.62))
	leaf.append(Vector2(-r.x * 0.20, r.y * 0.05))
	leaf.append(Vector2(0.0, r.y * 0.16))
	leaf.append(Vector2(r.x * 0.20, r.y * 0.05))
	leaf.append(Vector2(r.x * 0.30, -r.y * 0.62))
	draw_colored_polygon(leaf, MUCOSA_PALE)
	draw_polyline(_closed(leaf), MUCOSA_RIM, 3.0, true)

	var stalk := PackedVector2Array([
		Vector2(0.0, -r.y * 0.60), Vector2(0.0, r.y * 0.10)
	])
	draw_polyline(stalk, MUCOSA_RIM, 4.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Paired vestibular (false) folds flanking the vestibule.
func _draw_vestibular_folds() -> void:
	for i in [3, 4]:
		var c := _center(i)
		var r := _radii(i)
		draw_set_transform(c, 0.0, Vector2.ONE)
		var band := _ellipse(Vector2.ZERO, r.x * 0.72, r.y * 0.26, 28)
		draw_colored_polygon(band, MUCOSA_PALE)
		draw_polyline(_closed(band), MUCOSA_RIM, 2.5, true)
		draw_polyline(
			PackedVector2Array([Vector2(-r.x * 0.6, 0.0), Vector2(r.x * 0.6, 0.0)]),
			MUCOSA_RIM, 2.0, true
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The laryngeal ventricles: deep pockets beside the vocal folds.
func _draw_ventricles() -> void:
	for i in [6, 7]:
		var c := _center(i)
		var r := _radii(i)
		draw_set_transform(c, 0.0, Vector2.ONE)
		draw_colored_polygon(_ellipse(Vector2.ZERO, r.x * 0.70, r.y * 0.60, 30), RECESS)
		draw_colored_polygon(_ellipse(Vector2(0.0, -r.y * 0.06), r.x * 0.42, r.y * 0.34, 30), RECESS_DEEP)
		draw_polyline(_closed(_ellipse(Vector2.ZERO, r.x * 0.72, r.y * 0.62, 30)), RIM, 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# True vocal folds with the glottis slit between them - the signature feature.
func _draw_vocal_folds() -> void:
	var c := _center(8)
	var r := _radii(8)
	draw_set_transform(c, 0.0, Vector2.ONE)

	var fold_y := -r.y * 0.10
	var thickness := r.y * 0.16
	var half_span := r.x * 0.82
	var glottis_half := r.x * 0.10

	# Left and right pale folds with the dark glottis gap between them.
	_draw_fold_band(Vector2(-half_span, fold_y), Vector2(-glottis_half, fold_y), thickness)
	_draw_fold_band(Vector2(glottis_half, fold_y), Vector2(half_span, fold_y), thickness)

	# Glottis slit (dark), pointed at both ends.
	var slit := PackedVector2Array([
		Vector2(0.0, fold_y - thickness * 1.4),
		Vector2(glottis_half, fold_y),
		Vector2(0.0, fold_y + thickness * 1.4),
		Vector2(-glottis_half, fold_y),
	])
	draw_colored_polygon(slit, RECESS_DEEP)
	draw_polyline(_closed(slit), RIM, 2.0, true)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_fold_band(a: Vector2, b: Vector2, thickness: float) -> void:
	var band := PackedVector2Array([
		a + Vector2(0.0, -thickness),
		b + Vector2(0.0, -thickness),
		b + Vector2(0.0, thickness),
		a + Vector2(0.0, thickness),
	])
	draw_colored_polygon(band, MUCOSA_PALE)
	draw_polyline(_closed(band), MUCOSA_RIM, 2.5, true)


# The cricoid cartilage: a ring around the lower larynx.
func _draw_cricoid() -> void:
	var c := _center(10)
	var r := _radii(10)
	draw_set_transform(c, 0.0, Vector2.ONE)
	var ring := _ellipse(Vector2.ZERO, r.x * 0.86, r.y * 0.86, 44)
	draw_polyline(_closed(ring), CARTILAGE, 6.0, true)
	draw_polyline(_closed(_ellipse(Vector2.ZERO, r.x * 0.80, r.y * 0.80, 44)), Color(0.72, 0.56, 0.50, 0.16), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Tracheal cartilage: horizontal C-rings down the windpipe.
func _draw_tracheal_rings() -> void:
	for i in [13, 14]:
		var c := _center(i)
		var r := _radii(i)
		draw_set_transform(c, 0.0, Vector2.ONE)
		var rings := 4
		for k in range(rings):
			var ty: float = lerpf(-r.y * 0.6, r.y * 0.6, float(k) / float(rings - 1))
			var half: float = r.x * sqrt(maxf(0.05, 1.0 - pow(ty / r.y, 2.0))) * 0.9
			var pts := PackedVector2Array()
			for j in range(15):
				var t := lerpf(-1.0, 1.0, float(j) / 14.0)
				pts.append(Vector2(t * half, ty - (1.0 - t * t) * r.y * 0.03))
			draw_polyline(pts, CARTILAGE, 5.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out