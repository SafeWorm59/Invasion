@tool
extends ColorRect

const Map := preload("res://scenes/lungs_map.gd")
const TISSUE_SHADER := preload("res://scenes/lungs_tissue.gdshader")

const WALL_MARGIN := 620.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.0, 0.0, 0.0, 1.0)
	_rebuild()


func _rebuild() -> void:
	var box := Map.bounds().grow(WALL_MARGIN)
	position = box.position
	size = box.size

	var material := ShaderMaterial.new()
	material.shader = TISSUE_SHADER
	var chambers := PackedVector4Array()
	for i in range(Map.chamber_count()):
		var center := Map.chamber_center(i)
		var radii := Map.chamber_radii(i)
		chambers.append(Vector4(center.x, center.y, radii.x, radii.y))
	var corridors := PackedVector4Array()
	var widths := PackedFloat32Array()
	for i in range(Map.corridor_count()):
		var a := Map.corridor_a(i)
		var b := Map.corridor_b(i)
		corridors.append(Vector4(a.x, a.y, b.x, b.y))
		widths.append(Map.corridor_width(i))

	material.set_shader_parameter("chamber_count", Map.chamber_count())
	material.set_shader_parameter("chambers", chambers)
	material.set_shader_parameter("corridor_count", Map.corridor_count())
	material.set_shader_parameter("corridors", corridors)
	material.set_shader_parameter("corridor_widths", widths)
	material.set_shader_parameter("rect_origin", box.position)
	material.set_shader_parameter("rect_size", box.size)
	var bounds := Map.bounds()
	material.set_shader_parameter("top_y", bounds.position.y)
	material.set_shader_parameter("bottom_y", bounds.end.y)
	self.material = material
