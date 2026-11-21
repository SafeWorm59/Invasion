
@tool
extends Node2D

## Draws anatomical structures of the pharynx using procedural geometry.
## Attach to a Node2D positioned at the desired location.

enum StructureType { UVULA, SOFT_PALATE, ADENOID, EPIGLOTTIS, TONGUE_BASE, AUDITORY_TUBE }

@export var structure_type: StructureType = StructureType.UVULA
@export var structure_scale: float = 1.0
@export var primary_color: Color = Color("#9A5A66")
@export var secondary_color: Color = Color("#6E3742")
@export var outline_color: Color = Color("#46202A")
@export var outline_width: float = 1.5

## Epiglottis is elastic cartilage, so it is tinted separately from the mucosa.
## Exposed so a level can keep it inside its own palette.
@export var cartilage_color: Color = Color("#8E6E62")
@export var cartilage_edge_color: Color = Color("#5A3A36")
@export var cartilage_ridge_color: Color = Color("#9C7C70")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	match structure_type:
		StructureType.UVULA:
			_draw_uvula()
		StructureType.SOFT_PALATE:
			_draw_soft_palate()
		StructureType.ADENOID:
			_draw_adenoid()
		StructureType.EPIGLOTTIS:
			_draw_epiglottis()
		StructureType.TONGUE_BASE:
			_draw_tongue_base()
		StructureType.AUDITORY_TUBE:
			_draw_auditory_tube()


func _draw_uvula() -> void:
	var s := structure_scale
	var points := PackedVector2Array()

	# Teardrop / pendulous shape
	for i in range(40):
		var t := float(i) / 39.0
		var y := t * 80.0 * s
		var width_factor := sin(PI * t) * (1.0 - t * 0.3)
		var x := width_factor * 18.0 * s
		points.append(Vector2(x, y))

	# Return on the other side
	for i in range(39, -1, -1):
		var t := float(i) / 39.0
		var y := t * 80.0 * s
		var width_factor := sin(PI * t) * (1.0 - t * 0.3)
		var x := -width_factor * 18.0 * s
		points.append(Vector2(x, y))

	draw_colored_polygon(points, primary_color)
	var ol := points.duplicate()
	ol.append(points[0])
	draw_polyline(ol, outline_color, outline_width, true)

	# Highlight / sheen (soft, never a specular dot)
	draw_circle(Vector2(4.0 * s, 30.0 * s), 6.0 * s, Color(0.91, 0.63, 0.69, 0.16))


func _draw_soft_palate() -> void:
	var s := structure_scale
	var points := PackedVector2Array()

	# Curved shelf shape spanning horizontally
	for i in range(50):
		var t := float(i) / 49.0
		var x := lerpf(-200.0 * s, 200.0 * s, t)
		var y := -20.0 * s * sin(PI * t)  # gentle arch upward
		points.append(Vector2(x, y))

	# Underside (thicker in the middle)
	for i in range(49, -1, -1):
		var t := float(i) / 49.0
		var x := lerpf(-200.0 * s, 200.0 * s, t)
		var thickness := 2.0 + 25.0 * s * pow(sin(PI * t), 0.75)
		var y := thickness
		points.append(Vector2(x, y))

	draw_colored_polygon(points, primary_color)

	# Curtain in shadow along its free lower border, so the palate reads as a
	# hanging sheet of tissue rather than a flat bar.
	var under := PackedVector2Array()
	for i in range(50):
		var t := float(i) / 49.0
		under.append(Vector2(
			lerpf(-200.0 * s, 200.0 * s, t),
			(2.0 + 25.0 * s * pow(sin(PI * t), 0.75)) * 0.52
		))
	for i in range(49, -1, -1):
		var t := float(i) / 49.0
		under.append(Vector2(
			lerpf(-200.0 * s, 200.0 * s, t),
			2.0 + 25.0 * s * pow(sin(PI * t), 0.75)
		))
	draw_colored_polygon(under, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.55))

	var ol := points.duplicate()
	ol.append(points[0])
	draw_polyline(ol, outline_color, outline_width, true)

	# Lit upper surface.
	var sheen := PackedVector2Array()
	for i in range(50):
		var t := float(i) / 49.0
		sheen.append(Vector2(lerpf(-200.0 * s, 200.0 * s, t), -18.0 * s * sin(PI * t) + 2.0))
	draw_polyline(sheen, Color(0.90, 0.62, 0.70, 0.09), 3.0, true)

	# Tissue detail lines
	for i in range(8):
		var t := float(i + 1) / 9.0
		var x := lerpf(-180.0 * s, 180.0 * s, t)
		var top_y := -18.0 * s * sin(PI * t)
		var bot_y := 2.0 + 25.0 * s * pow(sin(PI * t), 0.75) - 4.0
		draw_line(
			Vector2(x, top_y + 3), Vector2(x, bot_y),
			Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.20), 1.5
		)


func _draw_adenoid() -> void:
	var s := structure_scale
	var rng := RandomNumberGenerator.new()
	rng.seed = 777

	# Lobulated mass (several overlapping lumps)
	for lobe in range(7):
		var lobe_center := Vector2(
			rng.randf_range(-50.0 * s, 50.0 * s),
			rng.randf_range(-30.0 * s, 30.0 * s)
		)
		var lobe_rx := rng.randf_range(25.0, 45.0) * s
		var lobe_ry := rng.randf_range(20.0, 35.0) * s

		var pts := PackedVector2Array()
		for i in range(20):
			var a := TAU * float(i) / 20.0
			var nr := 1.0 + rng.randf_range(-0.15, 0.15)
			pts.append(lobe_center + Vector2(cos(a) * lobe_rx * nr, sin(a) * lobe_ry * nr))

		var lobe_color := primary_color.lerp(secondary_color, rng.randf_range(0.0, 0.4))
		draw_colored_polygon(pts, lobe_color)
		var ol := pts.duplicate()
		ol.append(pts[0])
		draw_polyline(ol, Color(outline_color.r, outline_color.g, outline_color.b, 0.28), 1.2, true)


func _draw_epiglottis() -> void:
	var s := structure_scale
	var points := PackedVector2Array()

	# Leaf-shaped cartilage
	for i in range(40):
		var t := float(i) / 39.0
		var y := t * 100.0 * s
		var width := 30.0 * s * sin(PI * t) * (1.0 - t * 0.15)
		points.append(Vector2(width, y))

	for i in range(39, -1, -1):
		var t := float(i) / 39.0
		var y := t * 100.0 * s
		var width := 30.0 * s * sin(PI * t) * (1.0 - t * 0.15)
		points.append(Vector2(-width, y))

	# Cartilaginous yellow-pink
	var epi_color := cartilage_color
	draw_colored_polygon(points, epi_color)
	var ol := points.duplicate()
	ol.append(points[0])
	draw_polyline(ol, cartilage_edge_color, outline_width, true)

	# Central ridge
	draw_line(
		Vector2(0, 10 * s), Vector2(0, 85 * s),
		Color(cartilage_ridge_color.r, cartilage_ridge_color.g, cartilage_ridge_color.b, 0.30),
		2.0 * s
	)


func _draw_tongue_base() -> void:
	var s := structure_scale
	var points := PackedVector2Array()

	# Broad rounded mound
	for i in range(50):
		var t := float(i) / 49.0
		var x := lerpf(-160.0 * s, 160.0 * s, t)
		var y := -60.0 * s * sin(PI * t)
		points.append(Vector2(x, y))

	for i in range(49, -1, -1):
		var t := float(i) / 49.0
		var x := lerpf(-160.0 * s, 160.0 * s, t)
		points.append(Vector2(x, 15.0 * s))

	var tongue_color := Color("#8A4A56")
	draw_colored_polygon(points, tongue_color)
	var ol := points.duplicate()
	ol.append(points[0])
	draw_polyline(ol, Color(0.58, 0.25, 0.31, 0.65), outline_width, true)

	# Papillae (small bumps on the tongue surface)
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	for i in range(15):
		var bx := rng.randf_range(-140.0 * s, 140.0 * s)
		var by_t := (bx + 160.0 * s) / (320.0 * s)
		var surface_y := -60.0 * s * sin(PI * by_t)
		var by := surface_y + rng.randf_range(2.0, 8.0)
		draw_circle(Vector2(bx, by), rng.randf_range(3.0, 6.0) * s, Color(0.78, 0.42, 0.49, 0.16))


func _draw_auditory_tube() -> void:
	var s := structure_scale

	# Small opening / recess
	var points := PackedVector2Array()
	for i in range(20):
		var a := TAU * float(i) / 20.0
		var rx := 20.0 * s
		var ry := 12.0 * s
		points.append(Vector2(cos(a) * rx, sin(a) * ry))

	draw_colored_polygon(points, Color("#2A0E18"))
	var ol := points.duplicate()
	ol.append(points[0])
	draw_polyline(ol, outline_color, 2.0, true)

	# Surrounding tissue fold
	var fold := PackedVector2Array()
	for i in range(30):
		var a := PI + PI * float(i) / 29.0  # semicircle above
		var rx := 28.0 * s
		var ry := 18.0 * s
		fold.append(Vector2(cos(a) * rx, sin(a) * ry - 5.0 * s))

	for i in range(29, -1, -1):
		var a := PI + PI * float(i) / 29.0
		var rx := 35.0 * s
		var ry := 24.0 * s
		fold.append(Vector2(cos(a) * rx, sin(a) * ry - 5.0 * s))

	draw_colored_polygon(fold, primary_color)
	var fold_ol := fold.duplicate()
	fold_ol.append(fold[0])
	draw_polyline(fold_ol, Color(outline_color.r, outline_color.g, outline_color.b, 0.28), 1.2, true)
