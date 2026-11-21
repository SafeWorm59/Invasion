@tool
extends Node2D
const Map := preload("res://scenes/pharynx_map.gd")

## Tonsillar pillar: the mucosal arch that frames the medial border of a
## palatine tonsil. Two concentric arches are drawn (palatoglossal in front,
## palatopharyngeal behind) as tapered ribbons so each one emerges from and
## dissolves back into the surrounding mucosa.

@export var arc_radius: float = 152.0
@export var arc_span_deg: float = 126.0
@export var thickness: float = 30.0
@export var mirror: bool = false
@export var fold_color: Color = Color("#9A5A66")
@export var shadow_color: Color = Color("#2A0F1A")
@export var highlight_color: Color = Color("#A8707A")


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if mirror:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))

	_draw_arch(arc_radius, thickness, fold_color, 1.0)
	_draw_arch(arc_radius - 36.0, thickness * 0.52, fold_color.darkened(0.18), 0.8)

	if mirror:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_arch(radius: float, width: float, color: Color, alpha: float) -> void:
	var span: float = deg_to_rad(arc_span_deg)
	var steps: int = 24
	var path := PackedVector2Array()
	var widths := PackedFloat32Array()
	var shadow := PackedVector2Array()

	for i in range(steps):
		var u: float = float(i) / float(steps - 1)
		var a: float = lerpf(-span, span, u)
		var p := Vector2(cos(a) * radius, sin(a) * radius)
		var taper: float = pow(sin(PI * u), 0.42)
		path.append(p)
		shadow.append(p + Vector2(0.0, 5.0))
		widths.append(width * 0.5 * taper)

	draw_colored_polygon(
		Map.ribbon(shadow, widths),
		Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha * 0.55)
	)
	draw_colored_polygon(
		Map.ribbon(path, widths),
		Color(color.r, color.g, color.b, alpha)
	)

	var lip := PackedVector2Array()
	var lip_w := PackedFloat32Array()
	for i in range(steps):
		lip.append(path[i] + path[i].normalized() * width * -0.20)
		lip_w.append(widths[i] * 0.46)
	draw_colored_polygon(
		Map.ribbon(lip, lip_w),
		Color(highlight_color.r, highlight_color.g, highlight_color.b, alpha * 0.035)
	)
