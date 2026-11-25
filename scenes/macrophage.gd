extends CharacterBody2D

signal defeated_signal

enum State {
	PATROL,
	GUARD,
	INVESTIGATE,
	ENGULF
}

const CYTOKINE_PARTICLE_SCRIPT = preload(
	"res://scenes/cytokine_particle.gd"
)

const DEATH_CYTOKINE_PARTICLE_COUNT: int = 24
const MINION_TARGET_SCAN_INTERVAL: float = 0.25
const RESTRAINT_SCAN_INTERVAL: float = 0.25

@export var patrol_speed: float = 30.0
@export var guard_range: float = 300.0
@export var detection_range: float = 180.0
@export var guard_speed: float = 40.0
@export var patrol_distance: float = 150.0
@export var patrol_vertical_distance: float = 80.0
@export var patrol_pause_duration: float = 1.0
@export var body_radius: float = 32.0

@export var attack_range: float = 50.0
@export var attack_damage: int = 8
@export var attack_cooldown: float = 1.5
@export var attack_duration: float = 0.4

@export var max_health: int = 120
@export var required_minions: int = 3
@export var restraint_radius: float = 80.0
@export var restrained_attack_damage: int = 5
@export var restrained_attack_cooldown: float = 3.0
@export var player_join_range: float = 120.0
@export var player_attack_damage: int = 8
@export var player_attack_interval: float = 0.8

@export var investigation_speed: float = 50.0
@export var investigation_duration: float = 3.0
@export var investigation_arrival_distance: float = 16.0

@export var cytokine_recruitment_radius: float = 200.0

var pending_chemical_alert: bool = false
var pending_alert_position: Vector2 = Vector2.ZERO
var pending_alert_timer: float = 0.0

# Player hit tracking: macrophage takes 2 hits to kill the player.
var _player_hit_count: int = 0
var _player_hit_max: int = 2

const CHEMICAL_ALERT_MEMORY_DURATION: float = 10.0

var investigation_position: Vector2 = Vector2.ZERO
var investigating: bool = false
var investigation_timer: float = 0.0

var health: int = 120
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
var health_bar_width: float = 64.0
var health_bar_height: float = 7.0
var _minion_target_scan_timer: float = 0.0
var _cached_minion_target: Node2D = null
var _restraint_scan_timer: float = 0.0

# --- Amoeba membrane animation -------------------------------------------
# The outline is rebuilt from sine harmonics + lobes + pseudopods.
# Cache it and only recalculate every 2 frames to avoid 720-exp() calls per frame.
var _membrane_time: float = 0.0
var _membrane_phase: float = 0.0
var _lobes: Array[Dictionary] = []
var _pseudopods: Array[Dictionary] = []
const MEMBRANE_SEGMENTS: int = 36
var _cached_outline: PackedVector2Array = PackedVector2Array()
var _membrane_update_timer: float = 0.0

# Engulfment state.
var engulf_active: bool = false
var engulf_timer: float = 0.0
var engulf_duration: float = 0.6
var engulf_point: Vector2 = Vector2.ZERO
var _engulf_consumed: Array[int] = []

const MEMBRANE_COLOR := Color("#7482c0")
const MEMBRANE_INNER := Color("#95a0dd")
const MEMBRANE_EDGE := Color("#3c4576")
const NUCLEUS_COLOR := Color("#42356f")
const GRANULE_COLOR := Color("#c2c8f0")


func _ready() -> void:
	add_to_group("immune_cells")
	add_to_group("macrophages")

	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D

	_membrane_phase = randf() * TAU
	for i in range(5):
		_lobes.append({
			"angle": TAU * float(i) / 5.0 + randf_range(-0.5, 0.5),
			"phase": randf() * TAU,
			"amp": randf_range(0.35, 0.75),
			"width": randf_range(0.55, 0.95),
		})
	for i in range(3):
		_pseudopods.append({
			"angle": TAU * float(i) / 3.0 + randf_range(-0.6, 0.6),
			"phase": randf() * TAU,
			"amp": randf_range(0.8, 1.3),
		})

	patrol_origin = global_position
	choose_next_patrol_target()
	_cached_outline = _membrane_outline(1.0)
	queue_redraw()


func _physics_process(delta: float) -> void:

	_membrane_time += delta
	_membrane_update_timer -= delta
	if _membrane_update_timer <= 0.0 or attack_active or engulf_active:
		_membrane_update_timer = 0.033
		_cached_outline = _membrane_outline(1.0)
		queue_redraw()

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

	_restraint_scan_timer -= delta
	_minion_target_scan_timer -= delta
	if _restraint_scan_timer <= 0.0:
		_restraint_scan_timer = RESTRAINT_SCAN_INTERVAL
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

	# Swallowing an engulfed target: hold still while the membrane closes over
	# the meal, then resume normal behaviour.
	if engulf_active:
		state = State.ENGULF
		engulf_timer += delta
		velocity = Vector2.ZERO

		if engulf_timer >= engulf_duration:
			engulf_active = false
			engulf_timer = 0.0

		move_and_slide()
		queue_redraw()
		return

	# Combat takes priority over chemical investigation.
	if is_instance_valid(target):
		investigating = false
		investigation_timer = 0.0
		state = State.GUARD

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
			velocity = direction * guard_speed

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
					"Investigation complete. Macrophage resumes patrol."
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
		if (
			minion.get("being_engulfed") == true
			or minion.get("dissolved") == true
		):
			continue
		if minion.get("capture_target") != self:
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
		print("Macrophage restrained! Minions holding: ", nearby_minions)
	elif was_restrained and not restrained:
		print("Macrophage broke free!")

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

	if OS.is_debug_build():
		print("Macrophage health: %d / %d" % [health, max_health])
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

		if OS.is_debug_build():
			print("Macrophage defeated!")


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

	if (
		_minion_target_scan_timer <= 0.0
		or (
			is_instance_valid(_cached_minion_target)
			and not _is_valid_minion_target(_cached_minion_target)
		)
	):
		_cached_minion_target = _find_nearest_minion()
		_minion_target_scan_timer = MINION_TARGET_SCAN_INTERVAL

	if _is_valid_minion_target(_cached_minion_target):
		var minion_distance: float = global_position.distance_to(
			_cached_minion_target.global_position
		)
		if minion_distance < nearest_distance:
			nearest_distance = minion_distance
			nearest = _cached_minion_target

	return nearest


func _find_nearest_minion() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = detection_range

	for node in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		var minion := node as Node2D

		if minion.get("dying") == true:
			continue

		var distance: float = global_position.distance_to(minion.global_position)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = minion

	return nearest


func _is_valid_minion_target(candidate: Node2D) -> bool:
	return (
		is_instance_valid(candidate)
		and candidate.is_in_group("minions")
		and candidate.get("dying") != true
	)


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

	# Viral minions are swallowed, not chipped down: a single successful engulf
	# action consumes the target outright.
	if attacked_target.is_in_group("minions"):
		_consume_target(attacked_target)
		return

	# Normal damage for the player and other valid targets.
	if attacked_target.has_method("take_damage"):
		attacked_target.take_damage(damage_to_deal)

		# Track player hits: macrophage takes 2 hits to kill the player.
		if attacked_target == player:
			_player_hit_count += 1
			print("Macrophage hit player! Hit count: %d / %d" % [_player_hit_count, _player_hit_max])

			if _player_hit_count >= _player_hit_max:
				# Player defeated after 2 hits.
				player.take_damage(int(player.get("health")))
				_player_hit_count = 0  # Reset for next encounter
				print("Player defeated by macrophage!")
			else:
				notify_minions_of_player_attack()
				print("Macrophage attacked the player!")


# Consumes a target in a single action. The target dies immediately: its
# collision and AI are switched off and it leaves the "minions" group (so it
# can never be targeted or counted again), then it plays its engulf animation
# and frees itself. `_engulf_consumed` guards against the same instance being
# consumed twice in the same frame or across frames.
func _consume_target(node: Node2D) -> void:
	if not is_instance_valid(node):
		return

	if node.get("dying") == true or node.get("being_engulfed") == true:
		return

	var id := node.get_instance_id()

	if _engulf_consumed.has(id):
		return

	_engulf_consumed.append(id)

	if node.has_method("start_engulf_animation"):
		# Plays the shrink-into-the-macrophage animation; the target disables its
		# own collision/AI and frees itself when the animation finishes.
		node.start_engulf_animation(self)
	elif node.has_method("take_damage"):
		# Targets without an engulf animation are simply killed on the spot.
		node.take_damage(1_000_000)

	engulf_point = node.global_position
	engulf_active = true
	engulf_timer = 0.0
	state = State.ENGULF
	queue_redraw()

	if node.is_in_group("minions") and OS.is_debug_build():
		var capture_target := node.get("capture_target") as Node2D
		var capture_target_name: String = (
			String(capture_target.name)
			if is_instance_valid(capture_target)
			else "none"
		)
		print(
			"[Combat] %s engulfed minion %s (capture target: %s)."
			% [name, node.name, capture_target_name]
		)
	else:
		print("Macrophage engulfed a target instantly!")


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

	# Recruit nearby macrophages to the same alert.
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

	print("Macrophage received a chemical alert!")


func _draw() -> void:
	if defeated:
		var progress: float = clampf(death_timer / 0.4, 0.0, 1.0)
		var collapse: PackedVector2Array = _membrane_outline(1.0 - progress)
		if collapse.size() >= 3:
			draw_colored_polygon(
				collapse,
				Color(MEMBRANE_COLOR.r, MEMBRANE_COLOR.g, MEMBRANE_COLOR.b, 1.0 - progress)
			)
		draw_circle(
			Vector2.ZERO,
			body_radius * 0.4 * (1.0 - progress),
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

	# Irregular, animated amoeboid membrane (cached at ~30 FPS).
	var outline: PackedVector2Array = _cached_outline
	if outline.size() < 3:
		outline = _membrane_outline(1.0)

	# Filmy outer edge, filled cytoplasm, then a soft inner core.
	draw_colored_polygon(outline, MEMBRANE_COLOR)

	var inner := PackedVector2Array()
	for point in outline:
		inner.append(point * 0.8)
	draw_colored_polygon(inner, MEMBRANE_INNER)

	var rim := outline.duplicate()
	rim.append(outline[0])
	draw_polyline(rim, MEMBRANE_EDGE, 2.0, true)

	if attack_active or engulf_active:
		_draw_reaching()

	_draw_nucleus()
	_draw_granules()

	draw_health_bar()


# Builds the membrane outline as a radial polygon. A few sine harmonics give it
# an organically uneven edge, `_lobes` add slow-moving pseudopodial bumps, and
# while attacking/engulfing an extra reach bulges toward the target.
func _membrane_outline(size_scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var base := body_radius
	var t := _membrane_time

	for i in range(MEMBRANE_SEGMENTS):
		var a := TAU * float(i) / float(MEMBRANE_SEGMENTS)
		var r := base * (
			1.0
			+ 0.10 * sin(a * 3.0 + t * 0.8 + _membrane_phase)
			+ 0.07 * sin(a * 5.0 - t * 0.6 + _membrane_phase * 1.7)
			+ 0.05 * sin(a * 2.0 + t * 1.1 + _membrane_phase * 0.5)
		)

		for lobe in _lobes:
			var lobe_angle: float = float(lobe["angle"]) + t * 0.15
			var diff := _angle_delta(a, lobe_angle)
			var wobble := 0.6 + 0.4 * sin(t * 1.4 + float(lobe["phase"]))
			r += base * 0.45 * float(lobe["amp"]) * wobble * exp(-pow(diff / float(lobe["width"]), 2.0))

		# Longer, narrower pseudopodia reaching out from the membrane.
		for pod in _pseudopods:
			var pod_angle: float = float(pod["angle"]) + t * 0.25
			var pdiff := _angle_delta(a, pod_angle)
			var pwobble := 0.55 + 0.45 * sin(t * 1.1 + float(pod["phase"]))
			r += base * float(pod["amp"]) * pwobble * exp(-pow(pdiff / 0.38, 2.0))

		if attack_active or engulf_active:
			var reach := _reach_direction()
			var amount := _reach_amount()
			var ad := _angle_delta(a, reach.angle())
			r += base * 0.9 * amount * exp(-pow(ad / 0.6, 2.0))

		points.append(Vector2(cos(a), sin(a)) * r * size_scale)

	return points


func _draw_reaching() -> void:
	var reach := _reach_direction()
	var amount := _reach_amount()

	for k in range(3):
		var ang := reach.angle() + float(k - 1) * 0.28
		var dir := Vector2(cos(ang), sin(ang))
		var start := dir * body_radius * 0.4
		var finish := dir * body_radius * (1.0 + 0.7 * amount) * (1.0 - 0.12 * float(abs(k - 1)))
		draw_line(
			start,
			finish,
			Color(MEMBRANE_INNER.r, MEMBRANE_INNER.g, MEMBRANE_INNER.b, 0.85),
			5.0 - float(abs(k - 1)),
			true
		)


func _reach_direction() -> Vector2:
	if engulf_active:
		var to_target := engulf_point - global_position
		if to_target.length() > 0.001:
			return to_target.normalized()
	return attack_direction


func _reach_amount() -> float:
	if engulf_active:
		return sin(clampf(engulf_timer / engulf_duration, 0.0, 1.0) * PI)
	return sin(clampf(attack_timer / maxf(attack_duration, 0.001), 0.0, 1.0) * PI)


func _draw_nucleus() -> void:
	var center := Vector2(-body_radius * 0.10, -body_radius * 0.06)
	var nseg := 22
	var npts := PackedVector2Array()

	for i in range(nseg):
		var a := TAU * float(i) / float(nseg)
		var nr := body_radius * 0.44 * (
			1.0 + 0.14 * sin(a * 2.0 + _membrane_time * 0.5 + _membrane_phase)
		)
		npts.append(center + Vector2(cos(a) * nr * 1.2, sin(a) * nr * 0.82))

	draw_colored_polygon(npts, NUCLEUS_COLOR)
	draw_circle(
		center + Vector2(-body_radius * 0.10, -body_radius * 0.12),
		body_radius * 0.12,
		Color(0.55, 0.48, 0.85, 0.6)
	)


func _draw_granules() -> void:
	var offsets := [
		Vector2(0.42, 0.10), Vector2(-0.30, 0.34), Vector2(0.20, -0.36),
		Vector2(-0.16, -0.20), Vector2(0.10, 0.42), Vector2(0.34, 0.30),
		Vector2(-0.40, 0.02),
	]

	for i in range(offsets.size()):
		var o: Vector2 = offsets[i] * body_radius
		o += Vector2(
			sin(_membrane_time * 0.9 + float(i)),
			cos(_membrane_time * 0.7 + float(i) * 1.3)
		) * 1.5
		draw_circle(o, 2.0, GRANULE_COLOR)


func _angle_delta(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


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
		"Fallen macrophage released %d chemical signaling particles!"
		% DEATH_CYTOKINE_PARTICLE_COUNT
	)