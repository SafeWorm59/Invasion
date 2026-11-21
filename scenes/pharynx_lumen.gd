@tool
extends Node2D
const Map := preload("res://scenes/pharynx_map.gd")

## Mucosal floor shading drawn over the wall base: vertical wash, recessed edge
## shadow, central depth and organic mottling. Everything follows the single
## pharynx silhouette, so the floor reads as one continuous cavity from the
## vault to the esophageal funnel.

@export var wash_top: Color = Color("#311420")
@export var wash_upper: Color = Color("#40202D")
@export var wash_mid: Color = Color("#4A2130")
@export var wash_low: Color = Color("#2B1120")
@export var wash_deep: Color = Color("#170810")
@export var edge_shadow: Color = Color("#0E0409")

const STRIPS := 200
const EDGE_BANDS := 15
const EDGE_DEPTH := 92.0


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	_draw_wash()
	_draw_edge_shadow()
	_draw_depth()
	_draw_mottle()


func _wash_color(t: float) -> Color:
	if t < 0.18:
		return wash_top.lerp(wash_upper, t / 0.18)
	if t < 0.42:
		return wash_upper.lerp(wash_mid, (t - 0.18) / 0.24)
	if t < 0.62:
		return wash_mid.lerp(wash_upper.darkened(0.12), (t - 0.42) / 0.20)
	if t < 0.82:
		return wash_upper.darkened(0.12).lerp(wash_low, (t - 0.62) / 0.20)
	if t < 0.94:
		return wash_low.lerp(wash_deep, (t - 0.82) / 0.12)
	return wash_deep


func _draw_wash() -> void:
	for i in range(STRIPS):
		var y0: float = lerpf(Map.TOP, Map.BOTTOM, float(i) / float(STRIPS))
		var y1: float = lerpf(Map.TOP, Map.BOTTOM, float(i + 1) / float(STRIPS))
		var a := Map.lumen_point(y0, -1.0)
		var b := Map.lumen_point(y0, 1.0)
		var c := Map.lumen_point(y1, 1.0)
		var d := Map.lumen_point(y1, -1.0)
		var t: float = (float(i) + 0.5) / float(STRIPS)
		draw_colored_polygon(PackedVector2Array([a, b, c, d]), _wash_color(t))
	_draw_wash_caps()


## The wash strips stop at TOP/BOTTOM; fill the rounded caps with the matching
## colour so the vault roof and the funnel have no seam.
func _draw_wash_caps() -> void:
	var seg: int = 24

	var cb: float = Map.center_x(Map.BOTTOM)
	var hb: float = Map.half_width(Map.BOTTOM)
	var db: float = hb * 0.86
	var funnel := PackedVector2Array([Vector2(cb - hb, Map.BOTTOM)])
	for i in range(1, seg):
		var a: float = PI - PI * float(i) / float(seg)
		funnel.append(Vector2(cb + cos(a) * hb, Map.BOTTOM + sin(a) * db))
	funnel.append(Vector2(cb + hb, Map.BOTTOM))
	draw_colored_polygon(funnel, wash_deep)

	var ct: float = Map.center_x(Map.TOP)
	var ht: float = Map.half_width(Map.TOP)
	var dt: float = ht * 0.98
	var vault := PackedVector2Array([Vector2(ct + ht, Map.TOP)])
	for i in range(1, seg):
		var a: float = PI * float(i) / float(seg)
		vault.append(Vector2(ct + cos(a) * ht, Map.TOP - sin(a) * dt))
	vault.append(Vector2(ct - ht, Map.TOP))
	draw_colored_polygon(vault, wash_top)


## Soft dark band hugging the wall so the cavity reads as recessed.
func _draw_edge_shadow() -> void:
	for i in range(EDGE_BANDS):
		var k0: float = EDGE_DEPTH * float(i) / float(EDGE_BANDS)
		var k1: float = EDGE_DEPTH * float(i + 1) / float(EDGE_BANDS)
		var outer := Map.outline(-k0)
		var inner := Map.outline(-k1)
		var ring := PackedVector2Array()
		ring.append_array(outer)
		for j in range(inner.size() - 1, -1, -1):
			ring.append(inner[j])
		var alpha: float = lerpf(0.48, 0.0, float(i) / float(EDGE_BANDS - 1))
		draw_colored_polygon(ring, Color(edge_shadow.r, edge_shadow.g, edge_shadow.b, alpha))


## The lumen is a tube, so its axis sits deepest. A slow sequence of soft
## shadows along the centre line, plus a darker hollow in each large chamber.
func _draw_depth() -> void:
	var y: float = Map.TOP + 120.0
	while y < Map.BOTTOM - 120.0:
		var hw: float = Map.half_width(y)
		draw_set_transform(Vector2(Map.center_x(y), y), 0.0, Vector2(1.7, 1.0))
		draw_circle(Vector2.ZERO, hw * 0.46, Color(0.05, 0.01, 0.03, 0.055))
		y += 220.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	for i in range(Map.chamber_count()):
		var cy := Map.chamber_mid_y(i)
		var hw: float = Map.half_width(cy)
		draw_set_transform(Vector2(Map.center_x(cy), cy), 0.0, Vector2(1.9, 1.0))
		draw_circle(Vector2.ZERO, hw * 0.40, Color(0.05, 0.01, 0.03, 0.06))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Subtle organic colour variation so the mucosa is never a flat fill.
func _draw_mottle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13337

	for i in range(420):
		var y: float = rng.randf_range(Map.TOP + 80.0, Map.BOTTOM - 80.0)
		var hw: float = Map.half_width(y)
		var side: float = rng.randf_range(-0.78, 0.78)
		var pos := Vector2(Map.center_x(y) + side * hw, y)
		var radius: float = rng.randf_range(24.0, 78.0)
		var light: bool = rng.randf() > 0.45
		var col := Color(0.85, 0.55, 0.62, rng.randf_range(0.015, 0.038))
		if not light:
			col = Color(0.10, 0.02, 0.06, rng.randf_range(0.025, 0.055))
		draw_set_transform(pos, 0.0, Vector2(rng.randf_range(1.2, 2.4), 1.0))
		draw_circle(Vector2.ZERO, radius, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
