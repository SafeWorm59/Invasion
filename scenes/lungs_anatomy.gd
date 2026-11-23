@tool
extends Node2D

const Map := preload("res://scenes/lungs_map.gd")

const AIRWAY_SHADOW := Color(0.18, 0.07, 0.12, 0.16)
const AIRWAY_HIGHLIGHT := Color(0.85, 0.56, 0.63, 0.12)
const ALVEOLUS_FILL := Color(0.92, 0.64, 0.71, 0.16)
const ALVEOLUS_EDGE := Color(1.0, 0.82, 0.85, 0.25)
const TERMINAL_CHAMBERS := [9, 10, 11, 12, 13, 14, 15, 16]


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	for i in range(Map.corridor_count()):
		var a := Map.corridor_a(i)
		var b := Map.corridor_b(i)
		var width := Map.corridor_width(i)
		draw_line(a, b, AIRWAY_SHADOW, width * 1.45, true)
		draw_line(a, b, AIRWAY_HIGHLIGHT, width * 0.72, true)

	for chamber_index in TERMINAL_CHAMBERS:
		_draw_alveolar_cluster(chamber_index)


func _draw_alveolar_cluster(chamber_index: int) -> void:
	var center := Map.chamber_center(chamber_index)
	var radii := Map.chamber_radii(chamber_index)
	for i in range(14):
		var angle := TAU * float(i) / 14.0
		var scale := 0.18 + 0.32 * float((i * 7) % 13) / 13.0
		var alveolus := center + Vector2(
			cos(angle) * radii.x * scale,
			sin(angle) * radii.y * scale
		)
		var alveolus_radius := 32.0 + float(i % 3) * 6.0
		draw_circle(alveolus, alveolus_radius, ALVEOLUS_FILL)
		draw_arc(alveolus, alveolus_radius, 0.0, TAU, 20, ALVEOLUS_EDGE, 2.0, true)
