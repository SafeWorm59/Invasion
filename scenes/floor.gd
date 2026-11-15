
extends Polygon2D

func _ready() -> void:
	color = Color("#49202F")

	polygon = PackedVector2Array([
		# Zone A: nasal entry
		Vector2(-250, -1300),
		Vector2(100, -1350),
		Vector2(250, -1250),
		Vector2(220, -1050),

		# Zone B: first bend
		Vector2(450, -950),
		Vector2(600, -800),
		Vector2(450, -650),
		Vector2(100, -650),
		Vector2(-100, -500),

		# Pocket 1: left-side alcove
		Vector2(-450, -650),
		Vector2(-650, -550),
		Vector2(-700, -350),
		Vector2(-550, -200),
		Vector2(-350, -250),
		Vector2(-250, -400),

		# Zone C: central chamber
		Vector2(-100, -250),
		Vector2(-250, 0),
		Vector2(-200, 300),
		Vector2(100, 400),
		Vector2(500, 400),
		Vector2(750, 250),
		Vector2(800, 0),
		Vector2(650, -150),
		Vector2(850, -250),

		# Pocket 2: right-side alcove
		Vector2(1050, -250),
		Vector2(1250, -100),
		Vector2(1250, 150),
		Vector2(1100, 300),
		Vector2(900, 250),

		# Zone D: winding posterior passage
		Vector2(750, 450),
		Vector2(850, 650),
		Vector2(700, 850),
		Vector2(450, 900),
		Vector2(250, 1050),

		# Zone E: exit chamber
		Vector2(300, 1250),
		Vector2(450, 1350),
		Vector2(150, 1400),
		Vector2(-100, 1350),
		Vector2(-200, 1200),
		Vector2(-100, 1050),
		Vector2(100, 1000),
		Vector2(200, 900)
	])
