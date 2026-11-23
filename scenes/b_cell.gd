extends CharacterBody2D

signal defeated_signal

const PROJECTILE_SCENE := preload("res://scenes/antibody_projectile.tscn")

@export var patrol_speed: float = 38.0
@export var detection_range: float = 500.0
@export var attack_range: float = 500.0
@export var preferred_distance: float = 250.0
@export var minimum_distance: float = 155.0
@export var patrol_radius: float = 105.0
@export var attack_cooldown: float = 2.35
@export var projectile_speed: float = 340.0
@export var projectile_damage: int = 10
@export var max_health: int = 80
@export var body_radius: float = 28.0

var health: int = 80
var defeated: bool = false
var has_taken_damage: bool = false
var player: Node2D = null
var _home_position := Vector2.ZERO
var _patrol_target := Vector2.ZERO
var _patrol_wait: float = 0.0
var _cooldown: float = 0.5
var _death_timer: float = 0.0
var _animation_time: float = 0.0


func _ready() -> void:
	add_to_group("immune_cells")
	add_to_group("b_cells")
	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D
	_home_position = global_position
	_choose_patrol_target()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_animation_time += delta
	if defeated:
		_death_timer += delta
		queue_redraw()
		if _death_timer >= 0.4:
			queue_free()
		return

	_cooldown = maxf(_cooldown - delta, 0.0)
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if is_instance_valid(player) and player.visible:
		var distance := global_position.distance_to(player.global_position)
		if distance <= detection_range:
			if distance < minimum_distance:
				velocity = player.global_position.direction_to(global_position) * patrol_speed
			elif distance > preferred_distance:
				velocity = global_position.direction_to(player.global_position) * patrol_speed * 0.42
			else:
				velocity = Vector2.ZERO

			if distance <= attack_range and _cooldown <= 0.0:
				_fire_at_player()
		else:
			_patrol(delta)
	else:
		_patrol(delta)

	move_and_slide()
	queue_redraw()


func _patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait = maxf(_patrol_wait - delta, 0.0)
		velocity = Vector2.ZERO
		return
	if global_position.distance_to(_patrol_target) < 14.0:
		velocity = Vector2.ZERO
		_patrol_wait = 0.8
		_choose_patrol_target()
		return
	velocity = global_position.direction_to(_patrol_target) * patrol_speed


func _choose_patrol_target() -> void:
	var angle := randf_range(0.0, TAU)
	var distance := sqrt(randf()) * patrol_radius
	_patrol_target = _home_position + Vector2(cos(angle), sin(angle)) * distance


func _fire_at_player() -> void:
	if not is_instance_valid(player):
		return
	var direction := global_position.direction_to(player.global_position)
	var scene_root := get_tree().current_scene
	if scene_root == null:
		push_error("[BCell] Cannot fire antibody: no current scene.")
		return

	var projectile := PROJECTILE_SCENE.instantiate() as Area2D
	scene_root.add_child(projectile)
	projectile.global_position = global_position + direction * (body_radius + 16.0)
	projectile.set("speed", projectile_speed)
	projectile.call("setup", direction, projectile_damage, self)
	_cooldown = attack_cooldown


func take_damage(amount: int) -> void:
	if defeated or amount <= 0:
		return
	has_taken_damage = true
	health = maxi(health - amount, 0)
	if health <= 0:
		defeated = true
		velocity = Vector2.ZERO
		defeated_signal.emit()
		remove_from_group("immune_cells")
		remove_from_group("b_cells")
		var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision != null:
			collision.set_deferred("disabled", true)
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - clampf(_death_timer / 0.4, 0.0, 1.0) if defeated else 1.0
	var outer := Color(0.19, 0.53, 0.68, fade)
	var inner := Color(0.38, 0.79, 0.83, fade)
	var nucleus := Color(0.10, 0.24, 0.48, fade)
	var wobble := sin(_animation_time * 2.4) * 2.0

	draw_arc(Vector2.ZERO, body_radius + 7.0 + wobble, 0.0, TAU, 28, Color(0.48, 0.86, 0.91, 0.22 * fade), 2.0, true)
	draw_circle(Vector2.ZERO, body_radius + wobble, outer)
	draw_circle(Vector2(-2.0, -2.0), body_radius * 0.70, inner)
	draw_circle(Vector2(5.0, 1.0), body_radius * 0.34, nucleus)
	draw_circle(Vector2(3.0, -3.0), body_radius * 0.13, Color(0.78, 0.91, 0.89, fade))

	for i in range(3):
		var angle := TAU * float(i) / 3.0 + _animation_time * 0.35
		var base := Vector2(cos(angle), sin(angle)) * (body_radius * 0.66)
		draw_line(base, base + Vector2(cos(angle) * 8.0, sin(angle) * 8.0), Color(0.80, 0.94, 0.91, 0.85 * fade), 2.4, true)

	_draw_health_bar(fade)


func _draw_health_bar(alpha: float) -> void:
	var width := 56.0
	var top := -body_radius - 15.0
	draw_rect(Rect2(-width * 0.5, top, width, 6.0), Color(0.08, 0.05, 0.10, 0.85 * alpha))
	var ratio := clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
	draw_rect(Rect2(-width * 0.5, top, width * ratio, 6.0), Color(0.40, 0.94, 0.70, alpha))
