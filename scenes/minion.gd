
extends CharacterBody2D

enum CommandMode {
	FOLLOW,
	CAPTURE,
	DEFEND
}

@export var minion_radius: float = 10.0
@export var minion_color: Color = Color("#ff6655")
@export var follow_speed: float = 115.0
@export var follow_distance: float = 35.0

@export var max_health: int = 20
@export var death_animation_duration: float = 0.3
@export var capture_attack_damage: int = 5
@export var capture_attack_interval: float = 0.8
@export var surround_distance: float = 48.0

@export var attack_animation_duration: float = 0.22
@export var attack_lunge_distance: float = 10.0

@export var engulf_animation_duration: float = 0.65

var health: int = 20
var player: Node2D = null
var capture_target: Node2D = null
var formation_offset: Vector2 = Vector2.ZERO

var command_mode: CommandMode = CommandMode.FOLLOW
var defend_position: Vector2 = Vector2.ZERO

var capture_attack_timer: float = 0.0

var attack_animation_timer: float = 0.0
var is_attacking: bool = false
var attack_direction: Vector2 = Vector2.RIGHT

var dying: bool = false
var being_engulfed: bool = false
var death_timer: float = 0.0
var engulf_timer: float = 0.0
var engulf_target: Node2D = null

var fragment_angles: Array[float] = []
var fragment_distances: Array[float] = []


func _ready() -> void:
	add_to_group("minions")
	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D

	formation_offset = Vector2(
		randf_range(-45.0, 45.0),
		randf_range(-45.0, 45.0)
	)

	collision_layer = 0
	collision_mask = 0
	queue_redraw()


func set_command(
	new_command: CommandMode,
	command_position: Vector2 = Vector2.ZERO
) -> void:
	if dying or being_engulfed:
		return

	command_mode = new_command

	if command_mode == CommandMode.CAPTURE:
		capture_target = find_nearest_immune_cell()
		capture_attack_timer = 0.0
		is_attacking = false
		attack_animation_timer = 0.0
		print("Minion seeking an immune cell.")

	elif command_mode == CommandMode.FOLLOW:
		capture_target = null
		is_attacking = false
		attack_animation_timer = 0.0
		print("Minion command: Follow")

	elif command_mode == CommandMode.DEFEND:
		capture_target = null
		is_attacking = false
		attack_animation_timer = 0.0
		defend_position = command_position
		print("Minion command: Defend position ", defend_position)

	queue_redraw()


func set_defend_position(position: Vector2) -> void:
	set_command(CommandMode.DEFEND, position)


func find_nearest_immune_cell() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = INF

	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		if node.get("defeated") == true:
			continue

		var immune_cell := node as Node2D
		var distance := global_position.distance_to(
			immune_cell.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = immune_cell

	return nearest


func _physics_process(delta: float) -> void:
	if being_engulfed:
		update_engulf_animation(delta)
		return

	if dying:
		death_timer += delta
		queue_redraw()

		if death_timer >= death_animation_duration:
			queue_free()

		return

	if is_attacking:
		attack_animation_timer += delta

		if attack_animation_timer >= attack_animation_duration:
			is_attacking = false
			attack_animation_timer = 0.0

		queue_redraw()

	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		velocity = Vector2.ZERO
		return

	match command_mode:
		CommandMode.FOLLOW:
			follow_player()

		CommandMode.CAPTURE:
			capture_behavior(delta)

		CommandMode.DEFEND:
			defend_position_behavior()

	move_and_slide()


func follow_player() -> void:
	var target_position: Vector2 = (
		player.global_position + formation_offset
	)
	move_toward_position(target_position, follow_distance)


func capture_behavior(delta: float) -> void:
	if not is_instance_valid(capture_target):
		capture_target = find_nearest_immune_cell()

	if not is_instance_valid(capture_target):
		follow_player()
		return

	if capture_target.get("defeated") == true:
		capture_target = null
		is_attacking = false
		velocity = Vector2.ZERO
		return

	var slot_position: Vector2 = get_capture_slot_position()
	move_toward_position(slot_position, 5.0)

	if capture_target.has_method("is_restrained"):
		if capture_target.is_restrained():
			capture_attack_timer -= delta

			var distance_to_target: float = global_position.distance_to(
				capture_target.global_position
			)

			if (
				distance_to_target <= surround_distance + 24.0
				and capture_attack_timer <= 0.0
			):
				capture_attack_timer = capture_attack_interval

				attack_direction = global_position.direction_to(
					capture_target.global_position
				)
				is_attacking = true
				attack_animation_timer = 0.0
				queue_redraw()

				if capture_target.has_method("take_damage"):
					capture_target.take_damage(capture_attack_damage)
					print("Viral minion attacks restrained neutrophil!")


func get_capture_slot_position() -> Vector2:
	var circle_minions: Array[Node2D] = []

	for node in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		var minion := node as Node2D

		if minion.get("dying") == true:
			continue

		if minion.get("being_engulfed") == true:
			continue

		if minion.get("command_mode") != CommandMode.CAPTURE:
			continue

		if minion.get("capture_target") != capture_target:
			continue

		circle_minions.append(minion)

	if circle_minions.is_empty():
		return capture_target.global_position + Vector2(
			surround_distance, 0.0
		)

	var slot_index: int = circle_minions.find(self)

	if slot_index < 0:
		slot_index = 0

	var total_minions: int = circle_minions.size()
	var angle: float = TAU * float(slot_index) / float(total_minions)

	var circle_offset := Vector2(
		cos(angle),
		sin(angle)
	) * surround_distance

	return capture_target.global_position + circle_offset


func defend_position_behavior() -> void:
	var target_position: Vector2 = defend_position + formation_offset
	move_toward_position(target_position, 8.0)


func move_toward_position(
	target_position: Vector2,
	stop_distance: float
) -> void:
	var distance_to_target: float = global_position.distance_to(
		target_position
	)

	if distance_to_target > stop_distance:
		var direction: Vector2 = global_position.direction_to(
			target_position
		)
		velocity = direction * follow_speed
	else:
		velocity = Vector2.ZERO


func take_damage(amount: int) -> void:
	if dying or being_engulfed or amount <= 0:
		return

	health = max(health - amount, 0)
	print("Minion health: %d / %d" % [health, max_health])

	if health <= 0:
		start_death_animation()


func start_death_animation() -> void:
	if dying or being_engulfed:
		return

	dying = true
	velocity = Vector2.ZERO
	is_attacking = false
	attack_animation_timer = 0.0

	remove_from_group("minions")
	collision_layer = 0
	collision_mask = 0

	fragment_angles.clear()
	fragment_distances.clear()

	for i in range(7):
		fragment_angles.append(randf_range(0.0, TAU))
		fragment_distances.append(randf_range(12.0, 30.0))

	death_timer = 0.0
	print("Viral minion popped and eliminated!")
	queue_redraw()


func start_engulf_animation(immune_cell: Node2D) -> void:
	if dying or being_engulfed:
		return

	if not is_instance_valid(immune_cell):
		start_death_animation()
		return

	being_engulfed = true
	engulf_target = immune_cell
	engulf_timer = 0.0
	velocity = Vector2.ZERO
	is_attacking = false
	attack_animation_timer = 0.0

	remove_from_group("minions")
	collision_layer = 0
	collision_mask = 0

	print("Neutrophil is engulfing a viral minion!")
	queue_redraw()


func update_engulf_animation(delta: float) -> void:
	engulf_timer += delta

	if not is_instance_valid(engulf_target):
		queue_free()
		return

	var progress: float = clampf(
		engulf_timer / engulf_animation_duration,
		0.0,
		1.0
	)

	global_position = global_position.lerp(
		engulf_target.global_position,
		minf(delta * 7.0, 1.0)
	)

	queue_redraw()

	if progress >= 1.0:
		print("Viral minion engulfed!")
		queue_free()


func _draw() -> void:
	if being_engulfed:
		var progress: float = clampf(
			engulf_timer / engulf_animation_duration,
			0.0,
			1.0
		)

		var remaining_scale: float = 1.0 - progress
		var body_size: float = minion_radius * remaining_scale

		if body_size > 0.1:
			draw_circle(Vector2.ZERO, body_size, minion_color)
			draw_circle(
				Vector2(2, 1) * remaining_scale,
				body_size * 0.35,
				Color("#8c1025")
			)

		return

	if dying:
		var progress: float = clampf(
			death_timer / death_animation_duration,
			0.0,
			1.0
		)
		var remaining_scale: float = 1.0 - progress

		for i in range(fragment_angles.size()):
			var angle: float = fragment_angles[i]
			var distance: float = fragment_distances[i] * progress
			var fragment_position := Vector2(
				cos(angle), sin(angle)
			) * distance
			var fragment_size: float = 3.0 * remaining_scale

			var points := PackedVector2Array([
				fragment_position + Vector2(-fragment_size, -fragment_size),
				fragment_position + Vector2(fragment_size, 0.0),
				fragment_position + Vector2(0.0, fragment_size)
			])

			draw_colored_polygon(points, minion_color)

		return

	draw_circle(Vector2.ZERO, minion_radius, minion_color)
	draw_circle(
		Vector2(2, 1),
		minion_radius * 0.35,
		Color("#8c1025")
	)

	for i in range(4):
		var angle := TAU * float(i) / 4.0
		var direction := Vector2(cos(angle), sin(angle))

		var points := PackedVector2Array([
			direction * (minion_radius * 0.7)
				+ direction.rotated(PI / 2.0) * 3.0,
			direction * (minion_radius * 1.4),
			direction * (minion_radius * 0.7)
				- direction.rotated(PI / 2.0) * 3.0
		])

		draw_colored_polygon(points, minion_color)

	if is_attacking:
		var progress: float = clampf(
			attack_animation_timer / attack_animation_duration,
			0.0,
			1.0
		)

		var lunge: float = (
			sin(progress * PI) * attack_lunge_distance
		)

		var attack_tip: Vector2 = attack_direction * (
			minion_radius + lunge + 8.0
		)

		draw_line(
			Vector2.ZERO,
			attack_tip,
			Color("#ffd166"),
			4.0,
			true
		)

		draw_circle(
			attack_tip,
			3.0,
			Color("#fff1b8")
		)
