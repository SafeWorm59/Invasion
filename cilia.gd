
extends Node2D

@export var strand_count: int = 7
@export var strand_length: float = 15.0
@export var strand_spacing: float = 4.0
@export var sway_amount: float = 3.0
@export var sway_speed: float = 2.0
@export var strand_color: Color = Color(0.85, 0.63, 0.67, 0.7)

var animation_time: float = 0.0
var strand_phases: Array[float] = []


func _ready() -> void:
	for i in range(strand_count):
		strand_phases.append(randf_range(0.0, TAU))


func _process(delta: float) -> void:
	animation_time += delta
	queue_redraw()


func _draw() -> void:
	for i in range(strand_count):
		var base := Vector2(i * strand_spacing, 0.0)

		var sway := sin(
			animation_time * sway_speed + strand_phases[i]
		) * sway_amount

		var tip := base + Vector2(sway, -strand_length)

		draw_line(
			base,
			tip,
			strand_color,
			2.0,
			true
		)
