extends Node2D

## Glowing golden alert packet released by a dendritic cell.
##
## It travels from the dendritic cell toward one nearby immune cell (a
## neutrophil or a macrophage), leaving a short comet trail, then fades out. It
## is purely visual: it never touches the player and deals no damage. The
## immune response itself is delivered by the dendritic cell calling
## `receive_chemical_alert` on the recipient, not by this node.

var target: Vector2 = Vector2.ZERO
var speed: float = 520.0
var life: float = 0.9
var elapsed: float = 0.0
var _trail: Array[Vector2] = []

const COLOR_CORE := Color(1.0, 0.86, 0.28, 1.0)
const COLOR_GLOW := Color(1.0, 0.72, 0.12, 1.0)


func setup(origin: Vector2, destination: Vector2) -> void:
	global_position = origin
	target = destination
	z_index = 40


func _process(delta: float) -> void:
	elapsed += delta
	var t: float = clampf(elapsed / life, 0.0, 1.0)

	# Ease out toward the target.
	var dir := (target - global_position)
	if dir.length() > 2.0:
		global_position += dir.normalized() * speed * delta * (1.0 - t * 0.6)

	_trail.push_front(global_position)
	if _trail.size() > 8:
		_trail.resize(8)

	queue_redraw()

	if t >= 1.0:
		queue_free()


func _draw() -> void:
	# Comet trail.
	for i in range(_trail.size() - 1):
		var a: float = 1.0 - float(i) / float(_trail.size())
		var local_a := _trail[i] - global_position
		var local_b := _trail[i + 1] - global_position
		draw_line(
			local_a,
			local_b,
			Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, 0.35 * a),
			4.0 * a,
			true
		)

	# Pulsing glow + bright core.
	var pulse: float = 1.0 + sin(elapsed * 26.0) * 0.25
	draw_circle(Vector2.ZERO, 9.0 * pulse, Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, 0.30))
	draw_circle(Vector2.ZERO, 5.5 * pulse, Color(COLOR_GLOW.r, COLOR_GLOW.g, COLOR_GLOW.b, 0.65))
	draw_circle(Vector2.ZERO, 2.8 * pulse, COLOR_CORE)