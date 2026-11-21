@tool
extends ColorRect
const Map := preload("res://scenes/trachea_map.gd")
const TISSUE_SHADER := preload("res://scenes/trachea_tissue.gdshader")

## Paints the tracheal mucosa and the surrounding wall with one shader.
##
## The shader receives the exact same chamber/corridor tables the collision
## shell and the minimap are built from, so the visible lumen edge and the
## physical wall always agree. The rect is grown beyond the cavity so the wall
## gradient has room to fade into darkness at the edge of the playable area.

const WALL_MARGIN := 620.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 1.0)
	_rebuild()


func _rebuild() -> void:
	var box := Map.bounds()
	if box.size == Vector2.ZERO:
		return
	box = box.grow(WALL_MARGIN)
	position = box.position
	size = box.size

	var mat := ShaderMaterial.new()
	mat.shader = TISSUE_SHADER
	var chambers := PackedVector4Array()
	for i in range(Map.chamber_count()):
		var c := Map.chamber_center(i)
		var r := Map.chamber_radii(i)
		chambers.append(Vector4(c.x, c.y, r.x, r.y))
	var corridors := PackedVector4Array()
	var widths := PackedFloat32Array()
	for i in range(Map.corridor_count()):
		var a := Map.corridor_a(i)
		var b := Map.corridor_b(i)
		corridors.append(Vector4(a.x, a.y, b.x, b.y))
		widths.append(Map.corridor_width(i))

	mat.set_shader_parameter("chamber_count", Map.chamber_count())
	mat.set_shader_parameter("chambers", chambers)
	mat.set_shader_parameter("corridor_count", Map.corridor_count())
	mat.set_shader_parameter("corridors", corridors)
	mat.set_shader_parameter("corridor_widths", widths)
	mat.set_shader_parameter("rect_origin", box.position)
	mat.set_shader_parameter("rect_size", box.size)
	var bounds := Map.bounds()
	mat.set_shader_parameter("top_y", bounds.position.y)
	mat.set_shader_parameter("bottom_y", bounds.end.y)
	self.material = mat
