extends Area2D

@export var speed: float = 340.0
@export var damage: int = 10
@export var lifetime: float = 4.0

var _direction := Vector2.RIGHT
var _source: Node2D = null
var _elapsed: float = 0.0


func _ready() -> void:
	add_to_group("antibody_projectiles")
	queue_redraw()


func setup(direction: Vector2, shot_damage: int, source: Node2D) -> void:
	_direction = direction.normalized()
	damage = maxi(shot_damage, 0)
	_source = source
	rotation = _direction.angle()


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if body == _source:
		return
	if body.is_in_group("player") and body.visible and body.has_method("take_damage"):
		body.take_damage(damage)
	queue_free()


func _draw() -> void:
	var antibody_color := Color("#b5f3ed")
	var edge_color := Color("#3d9d9a")
	draw_line(Vector2(-7.0, 0.0), Vector2(1.0, 0.0), edge_color, 5.0, true)
	draw_line(Vector2(-7.0, 0.0), Vector2(1.0, 0.0), antibody_color, 2.5, true)
	draw_line(Vector2(0.0, 0.0), Vector2(8.0, -6.0), edge_color, 4.5, true)
	draw_line(Vector2(0.0, 0.0), Vector2(8.0, 6.0), edge_color, 4.5, true)
	draw_line(Vector2(0.0, 0.0), Vector2(8.0, -6.0), antibody_color, 2.0, true)
	draw_line(Vector2(0.0, 0.0), Vector2(8.0, 6.0), antibody_color, 2.0, true)
	draw_circle(Vector2(-7.0, 0.0), 2.4, antibody_color)
