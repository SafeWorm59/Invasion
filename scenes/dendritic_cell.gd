extends CharacterBody2D

signal defeated_signal

## Dendritic cell - Level 3 immune sentinel.
##
## Moves through the larynx like a normal enemy (patrolling territories with
## smooth autonomous movement, wall collision, and pauses). When the player
## approaches within its detection radius, it erupts with a swarm of glowing
## cytokine alert trails (identical to the chemical alert burst released when
## an infected host cell pops) along with targeted golden alert packets,
## waking nearby neutrophils and macrophages onto the intruder's location.
##
## The player can evade its patrol, stay clear of its alert radius, or disrupt
## it with close physical contact before it can sound the alarm.

const CYTOKINE_PARTICLE_SCRIPT = preload("res://scenes/cytokine_particle.gd")
const CYTOKINE_PARTICLE_COUNT: int = 24
const ALERT_SIGNAL := preload("res://scenes/alert_signal.gd")

enum State {
	PATROL,
	ALERT
}

# --- State -----------------------------------------------------------------
var state: State = State.PATROL
var health: int = 80
var defeated: bool = false
var alert_active: bool = false
var alert_timer: float = 0.0
var alert_cooldown_timer: float = 0.0
var _flash_timer: float = 0.0
var death_timer: float = 0.0

var player: Node2D = null
var last_detected_pos: Vector2 = Vector2.ZERO
var has_detected: bool = false

# --- Movement & Patrol (normal enemy behavior) -----------------------------
@export var patrol_speed: float = 58.0
@export var patrol_distance: float = 240.0
@export var patrol_vertical_distance: float = 160.0
@export var patrol_pause_duration: float = 2.0
@export var patrol_reach_threshold: float = 18.0

var patrol_origin: Vector2 = Vector2.ZERO
var patrol_target: Vector2 = Vector2.ZERO
var patrol_wait_timer: float = 0.0
var patrol_waypoints: Array[Vector2] = []
var current_waypoint_index: int = 0
var _stuck_timer: float = 0.0

# --- Detection & Alert -----------------------------------------------------
@export var detection_radius: float = 520.0
@export var alert_cooldown: float = 8.0
@export var alert_duration: float = 1.6
@export var notification_radius: float = 620.0

# --- Disruption (player contact) ------------------------------------------
@export var contact_radius: float = 46.0
@export var disruption_dps: float = 45.0

# --- Combat ----------------------------------------------------------------
@export var max_health: int = 80

# --- Appearance ------------------------------------------------------------
@export var body_radius: float = 30.0
@export var dendrite_count: int = 7

const BODY_COLOR := Color("#3a8f7d")
const BODY_INNER := Color("#5fc0a6")
const BODY_EDGE := Color("#1f4f45")
const NUCLEUS_COLOR := Color("#e0c85f")
const GRANULE_COLOR := Color("#c6ecdf")

var _time: float = 0.0
var _dendrites: Array[Dictionary] = []
var _detection_next_check: float = 0.0
var _render_accum: float = 0.0


func _ready() -> void:
	add_to_group("immune_cells")
	add_to_group("dendritic_cells")

	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D

	patrol_origin = global_position

	# Build a stable, irregular set of dendrites (branching projections).
	for i in range(dendrite_count):
		_dendrites.append({
			"angle": TAU * float(i) / float(dendrite_count) + randf_range(-0.35, 0.35),
			"length": randf_range(1.5, 2.6),
			"phase": randf() * TAU,
			"branches": randi_range(2, 3),
		})

	if patrol_waypoints.is_empty():
		choose_next_patrol_target()
	else:
		patrol_target = patrol_waypoints[0]

	queue_redraw()


func setup_patrol(points: Array[Vector2]) -> void:
	patrol_waypoints = points.duplicate()
	current_waypoint_index = 0
	if not patrol_waypoints.is_empty():
		patrol_target = patrol_waypoints[0]
		patrol_origin = patrol_waypoints[0]


func choose_next_patrol_target() -> void:
	if not patrol_waypoints.is_empty():
		current_waypoint_index = (current_waypoint_index + 1) % patrol_waypoints.size()
		# Add a slight natural wander around the waypoint
		var wander := Vector2(randf_range(-40.0, 40.0), randf_range(-30.0, 30.0))
		patrol_target = patrol_waypoints[current_waypoint_index] + wander
	else:
		var angle: float = randf_range(0.0, TAU)
		var distance: float = sqrt(randf()) * patrol_distance
		var vertical_scale: float = (
			patrol_vertical_distance / maxf(patrol_distance, 1.0)
		)
		patrol_target = patrol_origin + Vector2(
			cos(angle) * distance,
			sin(angle) * distance * vertical_scale
		)


func _physics_process(delta: float) -> void:
	_time += delta
	alert_cooldown_timer = maxf(alert_cooldown_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)

	if defeated:
		death_timer += delta
		queue_redraw()
		if death_timer >= 0.4:
			queue_free()
		return

	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	_update_contact_disruption(delta)

	# --- State Handling ---
	if alert_active:
		velocity = Vector2.ZERO
		alert_timer -= delta
		if alert_timer <= 0.0:
			alert_active = false
			state = State.PATROL
			choose_next_patrol_target()
	else:
		# --- Normal Enemy Patrol Movement ---
		if patrol_wait_timer > 0.0:
			patrol_wait_timer -= delta
			velocity = Vector2.ZERO
		else:
			var dist_to_target: float = global_position.distance_to(patrol_target)
			if dist_to_target < patrol_reach_threshold:
				velocity = Vector2.ZERO
				patrol_wait_timer = patrol_pause_duration
				choose_next_patrol_target()
				_stuck_timer = 0.0
			else:
				var direction: Vector2 = global_position.direction_to(patrol_target)
				velocity = direction * patrol_speed

				# Normal CharacterBody2D movement with collision against walls
				move_and_slide()

				# Anti-stuck logic: if sliding against a wall without progress, pick a new target
				if get_slide_collision_count() > 0:
					_stuck_timer += delta
					if _stuck_timer > 1.2:
						_stuck_timer = 0.0
						patrol_wait_timer = 0.5
						choose_next_patrol_target()
				else:
					_stuck_timer = maxf(_stuck_timer - delta * 0.5, 0.0)

	# --- Active Detection: Trigger Alert Trails when player/minions get near ---
	_detection_next_check -= delta
	if _detection_next_check <= 0.0:
		_detection_next_check = 0.25
		_check_detection()

	# Redraw throttled to ~30 FPS for smooth organic animation without CPU lag
	_render_accum -= delta
	if _render_accum <= 0.0 or alert_active or _flash_timer > 0.0:
		_render_accum = 0.033
		queue_redraw()


# The virus can disrupt a dendritic cell by pressing right up against it.
func _update_contact_disruption(delta: float) -> void:
	if not is_instance_valid(player) or not player.visible:
		return
	if global_position.distance_to(player.global_position) <= contact_radius:
		take_damage(int(round(disruption_dps * delta * 10.0)))


func _check_detection() -> void:
	if alert_active or alert_cooldown_timer > 0.0:
		return

	# Proximity check for player
	if is_instance_valid(player) and player.visible:
		if global_position.distance_to(player.global_position) <= detection_radius:
			last_detected_pos = player.global_position
			has_detected = true
			trigger_alert(player.global_position)
			return

	# Proximity check for viral minions
	var minion_group := get_tree().get_nodes_in_group("minions")
	for node in minion_group:
		if not is_instance_valid(node) or node.get("dying") == true:
			continue
		if global_position.distance_to(node.global_position) <= detection_radius:
			last_detected_pos = node.global_position
			has_detected = true
			trigger_alert(node.global_position)
			return


## Trigger the alarm: releases the full swarm of cytokine alert trails (identical
## to the burst when a cell is popped) and directs nearby leukocytes to the threat.
func trigger_alert(intruder_pos: Vector2) -> void:
	if defeated:
		return

	alert_active = true
	state = State.ALERT
	alert_timer = alert_duration
	alert_cooldown_timer = alert_cooldown
	_flash_timer = 0.6
	velocity = Vector2.ZERO

	# Release the cytokine particle trails (identical to popped host cell)
	_release_cytokine_alert_trails()

	# Broadcast targeted signal packets to nearby neutrophils and macrophages
	_broadcast_to_immune_cells(intruder_pos)

	queue_redraw()
	print("[DendriticCell] Player near sentinel! Released %d alert trails at %s" % [CYTOKINE_PARTICLE_COUNT, str(global_position)])


## Releases the full burst of 24 cytokine signaling particles with glowing trails
## identical to the effect when an infected cell pops.
func _release_cytokine_alert_trails() -> void:
	var main_scene := get_tree().current_scene
	if main_scene == null:
		return

	for i in range(CYTOKINE_PARTICLE_COUNT):
		var particle := CYTOKINE_PARTICLE_SCRIPT.new() as Node2D
		main_scene.add_child(particle)
		particle.setup(global_position)
		var angle := TAU * float(i) / float(CYTOKINE_PARTICLE_COUNT) + randf_range(-0.15, 0.15)
		particle.set("travel_direction", Vector2(cos(angle), sin(angle)))


## Sends glowing golden packets to every neutrophil and macrophage inside the
## notification radius and wakes them onto the intruder's position.
func _broadcast_to_immune_cells(intruder_pos: Vector2) -> void:
	var recipients: Array[Node2D] = []

	for group in ["neutrophils", "macrophages"]:
		for node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node is Node2D:
				continue
			if node.get("defeated") == true:
				continue
			if global_position.distance_to(node.global_position) <= notification_radius:
				recipients.append(node)

	for cell in recipients:
		var signal_node := ALERT_SIGNAL.new() as Node2D
		get_tree().current_scene.add_child(signal_node)
		if signal_node.has_method("setup"):
			signal_node.setup(global_position, cell.global_position)

		if cell.has_method("receive_chemical_alert"):
			cell.receive_chemical_alert(intruder_pos, false)
		elif cell.has_method("receive_dendritic_alert"):
			cell.receive_dendritic_alert(intruder_pos)


func take_damage(amount: int) -> void:
	if defeated or amount <= 0:
		return

	health = max(health - amount, 0)

	if health <= 0:
		defeated = true
		death_timer = 0.0
		velocity = Vector2.ZERO
		defeated_signal.emit()
		remove_from_group("immune_cells")
		remove_from_group("dendritic_cells")
		print("Dendritic cell disrupted - surveillance lost.")

	queue_redraw()


func is_alerting() -> bool:
	return alert_active


func _draw() -> void:
	if defeated:
		var t: float = clampf(death_timer / 0.4, 0.0, 1.0)
		_draw_body(1.0 - t)
		return

	_draw_dendrites()
	_draw_body(1.0)
	_draw_nucleus()
	_draw_granules()

	if alert_active or _flash_timer > 0.0:
		_draw_alarm()

	_draw_health_bar()


func _draw_dendrites() -> void:
	for d in _dendrites:
		var base_angle: float = float(d["angle"]) + sin(_time * 0.6 + float(d["phase"])) * 0.10
		var length: float = body_radius * float(d["length"])
		var start := Vector2(cos(base_angle), sin(base_angle)) * body_radius * 0.85
		var tip := Vector2(cos(base_angle), sin(base_angle)) * length

		var mid := start.lerp(tip, 0.55)
		var perp := Vector2(-sin(base_angle), cos(base_angle))
		mid += perp * sin(_time * 0.9 + float(d["phase"])) * length * 0.12

		var pts := PackedVector2Array([start, mid, tip])
		draw_polyline(pts, BODY_EDGE, 4.0, true)
		draw_polyline(pts, BODY_INNER, 2.2, true)

		# Side branches forking off the main projection.
		var branches: int = int(d["branches"])
		for b in range(branches):
			var f: float = 0.35 + 0.30 * float(b)
			var anchor: Vector2 = start.lerp(mid, f)
			var dir_ang: float = base_angle + (-0.9 if b % 2 == 0 else 0.9)
			var blen: float = length * (0.32 - 0.06 * float(b))
			var btip := anchor + Vector2(cos(dir_ang), sin(dir_ang)) * blen
			draw_line(anchor, btip, BODY_EDGE, 2.6, true)
			draw_line(anchor, btip, BODY_INNER, 1.3, true)
			draw_circle(btip, 1.8, GRANULE_COLOR)


func _draw_body(scale_factor: float) -> void:
	var pts := PackedVector2Array()
	var segments := 28
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var r: float = body_radius * scale_factor * (
			1.0
			+ 0.12 * sin(a * 3.0 + _time * 1.2)
			+ 0.08 * sin(a * 5.0 - _time * 0.8)
		)
		pts.append(Vector2(cos(a), sin(a)) * r)

	draw_colored_polygon(pts, BODY_COLOR)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.78)
	draw_colored_polygon(inner, BODY_INNER)

	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, BODY_EDGE, 2.0, true)


func _draw_nucleus() -> void:
	var seg := 14
	var pts := PackedVector2Array()
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		var r: float = body_radius * 0.34 * (1.0 + 0.16 * sin(a * 2.0 + _time * 0.7))
		pts.append(Vector2(cos(a) * r * 1.15, sin(a) * r * 0.85))
	draw_colored_polygon(pts, NUCLEUS_COLOR)


func _draw_granules() -> void:
	var offsets := [
		Vector2(0.45, 0.18), Vector2(-0.38, 0.30), Vector2(0.22, -0.44),
		Vector2(-0.20, -0.30), Vector2(0.06, 0.50),
	]
	for i in range(offsets.size()):
		var o: Vector2 = offsets[i] * body_radius
		o += Vector2(sin(_time * 1.1 + float(i)), cos(_time * 0.9 + float(i))) * 1.4
		draw_circle(o, 2.0, GRANULE_COLOR)


func _draw_alarm() -> void:
	var pulse: float = 1.0 + sin(_time * 12.0) * 0.18
	draw_arc(Vector2.ZERO, detection_radius * 0.18 * pulse, 0.0, TAU, 32, Color(1.0, 0.78, 0.16, 0.30), 3.0, true)
	draw_arc(Vector2.ZERO, body_radius * 1.35 * pulse, 0.0, TAU, 32, Color(1.0, 0.78, 0.16, 0.9), 3.0, true)


func _draw_health_bar() -> void:
	var w := 60.0
	var h := 6.0
	var pos := Vector2(-w * 0.5, -body_radius - 20.0)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("#221c14"))
	var ratio: float = clampf(float(health) / float(max_health), 0.0, 1.0)
	var col := Color(1.0, 0.78, 0.16)
	if ratio <= 0.5:
		col = Color("#ffae4d")
	if ratio <= 0.25:
		col = Color("#ff6b3a")
	draw_rect(Rect2(pos, Vector2(w * ratio, h)), col)
	draw_rect(Rect2(pos, Vector2(w, h)), Color("#f0e8d0"), false, 1.0)
