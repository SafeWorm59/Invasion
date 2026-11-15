
extends CharacterBody2D

signal defeated_signal

enum State {
	PATROL,
	CHASE,
	INVESTIGATE
}

const CYTOKINE_PARTICLE_SCRIPT = preload(
	"res://scenes/cytokine_particle.gd"
)

const DEATH_CYTOKINE_PARTICLE_COUNT: int = 24

@export var patrol_speed: float = 55.0
@export var chase_speed: float = 100.0
@export var detection_range: float = 220.0
@export var patrol_distance: float = 100.0
@export var patrol_vertical_distance: float = 100.0
@export var patrol_pause_duration: float = 0.8
@export var body_radius: float = 24.0

@export var attack_range: float = 42.0
@export var attack_damage: int = 10
@export var attack_cooldown: float = 1.2
@export var attack_duration: float = 0.35

@export var max_health: int = 100
@export var required_minions: int = 3
@export var restraint_radius: float = 76.0
@export var restrained_attack_damage: int = 4
@export var restrained_attack_cooldown: float = 2.5
@export var player_join_range: float = 110.0
@export var player_attack_damage: int = 10
@export var player_attack_interval: float = 0.7

@export var investigation_speed: float = 75.0
@export var investigation_duration: float = 2.5
@export var investigation_arrival_distance: float = 12.0

@export var cytokine_recruitment_radius: float = 220.0

var pending_chemical_alert: bool = false
var pending_alert_position: Vector2 = Vector2.ZERO
var pending_alert_timer: float = 0.0

const CHEMICAL_ALERT_MEMORY_DURATION: float = 12.0

var investigation_position: Vector2 = Vector2.ZERO
var investigating: bool = false
var investigation_timer: float = 0.0

var health: int = 100
var defeated: bool = false
var restrained: bool = false
var player_assisting: bool = false

var player: Node2D = null
var target: Node2D = null
var state: State = State.PATROL

var patrol_origin: Vector2
var patrol_target: Vector2
var patrol_wait_timer: float = 0.0

var attack_active: bool = false
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var attack_direction: Vector2 = Vector2.RIGHT

var death_timer: float = 0.0

var has_taken_damage: bool = false
var health_bar_width: float = 54.0
var health_bar_height: float = 7.0


func _ready() -> void:
	add_to_group("immune_cells")

	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D

	patrol_origin = global_position
	choose_next_patrol_target()

	queue_redraw()


func _physics_process(delta: float) -> void:

	if pending_chemical_alert:
		pending_alert_timer -= delta

		if pending_alert_timer <= 0.0:
			pending_chemical_alert = false

	if defeated:
		death_timer += delta
		queue_redraw()

		if death_timer >= 0.4:
			queue_free()

		return

	cooldown_timer = maxf(cooldown_timer - delta, 0.0)

	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	update_restraint()
	update_player_assistance()

	target = find_nearest_target()

	# Finish an attack animation before changing behavior.
	if attack_active:
		attack_timer += delta
		velocity = Vector2.ZERO

		if attack_timer >= attack_duration:
			attack_active = false
			perform_attack()

		move_and_slide()
		queue_redraw()
		return

	# Combat takes priority over chemical investigation.
	if is_instance_valid(target):
		investigating = false
		investigation_timer = 0.0
		state = State.CHASE

		var distance: float = global_position.distance_to(
			target.global_position
		)

		var effective_cooldown: float = attack_cooldown

		if restrained:
			effective_cooldown = restrained_attack_cooldown

		if distance <= attack_range and cooldown_timer <= 0.0:
			start_attack(effective_cooldown)
			velocity = Vector2.ZERO
		elif restrained:
			velocity = Vector2.ZERO
		else:
			var direction: Vector2 = global_position.direction_to(
				target.global_position
			)
			velocity = direction * chase_speed

	# Investigate the location where the infected cell burst.
	elif investigating and not restrained:
		state = State.INVESTIGATE

		var distance_to_alert: float = global_position.distance_to(
			investigation_position
		)

		if distance_to_alert > investigation_arrival_distance:
			var direction_to_alert: Vector2 = global_position.direction_to(
				investigation_position
			)
			velocity = direction_to_alert * investigation_speed
		else:
			velocity = Vector2.ZERO
			investigation_timer += delta

			if investigation_timer >= investigation_duration:
				investigating = false
				investigation_timer = 0.0
				state = State.PATROL

				print(
					"Investigation complete. Neutrophil resumes patrol."
				)

	# Patrol different points in a two-dimensional area.
	else:
		state = State.PATROL

		if restrained:
			velocity = Vector2.ZERO
		elif patrol_wait_timer > 0.0:
			patrol_wait_timer = maxf(
				patrol_wait_timer - delta,
				0.0
			)
			velocity = Vector2.ZERO
		else:
			var distance_to_patrol_target: float = (
				global_position.distance_to(patrol_target)
			)

			if distance_to_patrol_target < 12.0:
				velocity = Vector2.ZERO
				patrol_wait_timer = patrol_pause_duration
				choose_next_patrol_target()
			else:
				var direction: Vector2 = global_position.direction_to(
					patrol_target
				)
				velocity = direction * patrol_speed

	move_and_slide()
	queue_redraw()


func choose_next_patrol_target() -> void:
	var angle: float = randf_range(0.0, TAU)

	var distance: float = sqrt(randf()) * patrol_distance

	var vertical_scale: float = (
		patrol_vertical_distance / maxf(patrol_distance, 1.0)
	)

	patrol_target = patrol_origin + Vector2(
		cos(angle) * distance,
		sin(angle) * distance * vertical_scale
	)


func update_restraint() -> void:
	var nearby_minions: int = 0

	for node in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		var minion := node as Node2D

		if minion.get("dying") == true:
			continue

		var distance: float = global_position.distance_to(
			minion.global_position
		)

		if distance <= restraint_radius:
			if minion.get("command_mode") == 1:
				nearby_minions += 1

	var was_restrained: bool = restrained
	restrained = nearby_minions >= required_minions

	if restrained and not was_restrained:
		print("Neutrophil restrained! Minions holding: ", nearby_minions)
	elif was_restrained and not restrained:
		print("Neutrophil broke free!")

	if not restrained:
		player_assisting = false


func update_player_assistance() -> void:
	if not player_assisting:
		return

	if not restrained or not is_instance_valid(player):
		player_assisting = false
		return

	if not player.visible:
		player_assisting = false
		return

	var distance: float = global_position.distance_to(
		player.global_position
	)

	if distance > player_join_range:
		player_assisting = false
		print("Player left the team attack.")


func is_restrained() -> bool:
	return restrained and not defeated


func can_player_join() -> bool:
	if defeated or not restrained or not is_instance_valid(player):
		return false

	if not player.visible:
		return false

	return global_position.distance_to(
		player.global_position
	) <= player_join_range


func set_player_assisting(enabled: bool) -> void:
	if defeated:
		return

	if enabled and can_player_join():
		player_assisting = true
		print("Player joined the team attack!")
	else:
		player_assisting = false


func get_player_slot_position() -> Vector2:
	var player_circle_radius: float = 62.0
	var player_circle_angle: float = -PI / 2.0

	var offset := Vector2(
		cos(player_circle_angle),
		sin(player_circle_angle)
	) * player_circle_radius

	return global_position + offset


func take_damage(amount: int) -> void:
	if defeated or amount <= 0:
		return

	has_taken_damage = true
	health = max(health - amount, 0)

	print("Neutrophil health: %d / %d" % [health, max_health])
	queue_redraw()

	if health <= 0:
		var death_position: Vector2 = global_position

		defeated = true
		defeated_signal.emit()
		restrained = false
		player_assisting = false
		investigating = false
		velocity = Vector2.ZERO
		attack_active = false

		release_death_chemical_alert(death_position)

		remove_from_group("immune_cells")

		print("Neutrophil defeated!")


func find_nearest_target() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = detection_range

	if is_instance_valid(player) and player.visible:
		var distance: float = global_position.distance_to(
			player.global_position
		)

		if distance <= nearest_distance:
			nearest_distance = distance
			nearest = player

	for node in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		var minion := node as Node2D

		if minion.get("dying") == true:
			continue

		var distance: float = global_position.distance_to(
			minion.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = minion

	return nearest


func start_attack(cooldown: float = -1.0) -> void:
	if not is_instance_valid(target):
		return

	attack_direction = global_position.direction_to(
		target.global_position
	)

	attack_active = true
	attack_timer = 0.0

	if cooldown < 0.0:
		cooldown = attack_cooldown

	cooldown_timer = cooldown
	queue_redraw()


func perform_attack() -> void:
	if not is_instance_valid(target):
		return

	var attacked_target: Node2D = target

	var distance: float = global_position.distance_to(
		attacked_target.global_position
	)

	if distance > attack_range + 12.0:
		return

	var damage_to_deal: int = attack_damage

	if restrained:
		damage_to_deal = restrained_attack_damage

	# Special behavior for viral minions.
	if attacked_target.is_in_group("minions"):
		var previous_health: int = int(attacked_target.get("health"))

		if attacked_target.has_method("take_damage"):
			attacked_target.take_damage(damage_to_deal)

		# If this attack defeated the minion, engulf it.
		if (
			is_instance_valid(attacked_target)
			and int(attacked_target.get("health")) <= 0
			and attacked_target.has_method("start_engulf_animation")
		):
			attacked_target.start_engulf_animation(self)
			print("Neutrophil engulfed a defeated viral minion!")
		elif previous_health > 0:
			print("Neutrophil attacked a viral minion!")

		return

	# Normal damage for the player and other valid targets.
	if attacked_target.has_method("take_damage"):
		var previous_player_health: int = -1

		if attacked_target == player:
			previous_player_health = int(player.get("health"))

		attacked_target.take_damage(damage_to_deal)

		# Notify the squad only if the player actually lost health.
		if attacked_target == player:
			var current_player_health: int = int(player.get("health"))

			if current_player_health < previous_player_health:
				notify_minions_of_player_attack()
				print("Neutrophil attacked the player!")


func notify_minions_of_player_attack() -> void:
	var minions := get_tree().get_nodes_in_group("minions")
	var notified_count: int = 0

	for minion in minions:
		if not is_instance_valid(minion):
			continue

		if minion.has_method("respond_to_player_attack"):
			minion.respond_to_player_attack(self)
			notified_count += 1

	print(
		"Player under attack! %d minions responding!"
		% notified_count
	)


func receive_chemical_alert(
	location: Vector2,
	spread_recruitment: bool = true
) -> void:
	if defeated or restrained:
		return

	pending_chemical_alert = true
	pending_alert_position = location
	pending_alert_timer = CHEMICAL_ALERT_MEMORY_DURATION

	if not is_instance_valid(target):
		investigation_position = location
		investigating = true
		investigation_timer = investigation_duration
		state = State.INVESTIGATE

	# Recruit nearby neutrophils to the same alert.
	if spread_recruitment:
		for cell in get_tree().get_nodes_in_group("immune_cells"):
			if cell == self or not is_instance_valid(cell):
				continue

			if cell.get("defeated") == true:
				continue

			var distance: float = global_position.distance_to(
				cell.global_position
			)

			if distance <= cytokine_recruitment_radius:
				if cell.has_method("receive_chemical_alert"):
					cell.receive_chemical_alert(location, false)

	print("Neutrophil received a chemical alert!")


func _draw() -> void:
	if defeated:
		var progress: float = clampf(
			death_timer / 0.4,
			0.0,
			1.0
		)

		draw_circle(
			Vector2.ZERO,
			body_radius * (1.0 - progress),
			Color(0.9, 0.9, 0.6, 1.0 - progress)
		)
		return

	if restrained:
		draw_arc(
			Vector2.ZERO,
			restraint_radius * 0.7,
			0.0,
			TAU,
			48,
			Color("#ff6655"),
			2.0,
			true
		)

	if attack_active:
		var progress: float = clampf(
			attack_timer / attack_duration,
			0.0,
			1.0
		)

		var extension: float = sin(progress * PI)
		var arm_length: float = 24.0 + 28.0 * extension
		var side_direction: Vector2 = attack_direction.rotated(PI / 2.0)

		for i in range(3):
			var spread: float = float(i - 1) * 0.32
			var direction: Vector2 = attack_direction.rotated(spread)
			var start: Vector2 = direction * (body_radius * 0.55)
			var finish: Vector2 = direction * arm_length

			finish += side_direction * float(i - 1) * 5.0 * extension

			draw_line(
				start,
				finish,
				Color("#e8e5a0"),
				7.0 - float(abs(i - 1)),
				true
			)

			draw_circle(finish, 4.0, Color("#d4ce80"))

	draw_circle(Vector2.ZERO, body_radius, Color("#e8e5a0"))

	draw_circle(Vector2(-7, -3), 7.0, Color("#7856a6"))
	draw_circle(Vector2(4, -8), 7.0, Color("#7856a6"))
	draw_circle(Vector2(8, 4), 7.0, Color("#7856a6"))
	draw_circle(Vector2(-4, 8), 6.0, Color("#7856a6"))

	draw_circle(Vector2(-13, -12), 2.0, Color("#c4b85d"))
	draw_circle(Vector2(13, -11), 2.0, Color("#c4b85d"))
	draw_circle(Vector2(14, 10), 2.0, Color("#c4b85d"))
	draw_circle(Vector2(-13, 12), 2.0, Color("#c4b85d"))
	draw_circle(Vector2(0, 15), 2.0, Color("#c4b85d"))

	draw_health_bar()


func draw_health_bar() -> void:
	if not has_taken_damage or defeated:
		return

	var bar_position := Vector2(
		-health_bar_width / 2.0,
		-body_radius - 17.0
	)

	var background_rect := Rect2(
		bar_position,
		Vector2(health_bar_width, health_bar_height)
	)

	draw_rect(background_rect, Color("#29232b"))

	var health_ratio: float = clampf(
		float(health) / float(max_health),
		0.0,
		1.0
	)

	var health_color := Color("#55d66b")

	if health_ratio <= 0.5:
		health_color = Color("#ffb347")

	if health_ratio <= 0.25:
		health_color = Color("#ff453a")

	var fill_rect := Rect2(
		bar_position,
		Vector2(
			health_bar_width * health_ratio,
			health_bar_height
		)
	)

	draw_rect(fill_rect, health_color)
	draw_rect(background_rect, Color("#f0e8f0"), false, 1.0)


func release_death_chemical_alert(
	origin: Vector2
) -> void:
	var main_scene := get_tree().current_scene

	if main_scene == null:
		return

	for i in range(DEATH_CYTOKINE_PARTICLE_COUNT):
		var particle := CYTOKINE_PARTICLE_SCRIPT.new() as Node2D

		main_scene.add_child(particle)
		particle.setup(origin)

	print(
		"Fallen neutrophil released %d chemical signaling particles!"
		% DEATH_CYTOKINE_PARTICLE_COUNT
	)
