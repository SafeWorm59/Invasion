
@tool
extends StaticBody2D

@export_group("Fold Shape")
@export_range(40.0, 400.0, 1.0) var fold_width: float = 150.0:
	set(value):
		fold_width = value
		update_fold()

@export_range(20.0, 200.0, 1.0) var fold_height: float = 65.0:
	set(value):
		fold_height = value
		update_fold()

@export_range(5.0, 80.0, 1.0) var fold_thickness: float = 24.0:
	set(value):
		fold_thickness = value
		update_fold()

@export_group("Appearance")
@export var fold_color: Color = Color("#D98F91"):
	set(value):
		fold_color = value
		queue_redraw()

@export var outline_color: Color = Color("#A85F69"):
	set(value):
		outline_color = value
		queue_redraw()

@export_range(0.5, 6.0, 0.5) var outline_width: float = 2.0:
	set(value):
		outline_width = value
		queue_redraw()

@export_group("Collision")
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		update_fold()

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D

var fold_points := PackedVector2Array()


func _ready() -> void:
	update_fold()


func update_fold() -> void:
	if not is_inside_tree():
		return

	fold_points = create_arch_shape()

	if is_node_ready() and collision_polygon:
		collision_polygon.polygon = fold_points
		collision_polygon.disabled = not collision_enabled

	queue_redraw()


func create_arch_shape() -> PackedVector2Array:
	var points := PackedVector2Array()
	var half_width := fold_width / 2.0
	var half_thickness := fold_thickness / 2.0

	# Outer arch: follows a smooth curved ridge.
	for i in range(25):
		var t := float(i) / 24.0
		var x := lerpf(-half_width, half_width, t)
		var arch_y := -fold_height * sin(PI * t)
		points.append(Vector2(x, arch_y - half_thickness))

	# Inner arch: travels back along the underside.
	for i in range(24, -1, -1):
		var t := float(i) / 24.0
		var x := lerpf(-half_width, half_width, t)
		var arch_y := -fold_height * sin(PI * t)
		points.append(Vector2(x, arch_y + half_thickness))

	return points


func _draw() -> void:
	if fold_points.size() < 3:
		return

	draw_colored_polygon(fold_points, fold_color)

	var outline := fold_points.duplicate()
	outline.append(fold_points[0])

	draw_polyline(
		outline,
		outline_color,
		outline_width,
		true
	)
