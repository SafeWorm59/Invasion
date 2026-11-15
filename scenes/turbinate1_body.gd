
extends StaticBody2D

@onready var visual: Polygon2D = get_node("../Turbinate1")


func _ready() -> void:
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionPolygon2D"
	collision.polygon = visual.polygon
	collision.position = visual.position
	collision.rotation = visual.rotation
	collision.scale = visual.scale
	collision.build_mode = CollisionPolygon2D.BUILD_SOLIDS

	add_child(collision)
