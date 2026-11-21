extends CharacterBody2D

## NATURAL KILLER T (NKT) CELL - Level 4 immune surveillance enemy.
##
## Unlike every previous enemy, the NKT cell does not patrol an area, chase the
## player or engulf targets. It systematically visits the level's host cells,
## inspects each one, and - only when the host cell is actually infected -
## eliminates that cell together with every viral minion it produced.
##
## Behaviour is a small explicit state machine:
##   SURVEILLANCE -> MOVING_TO_HOST -> INSPECTING -> (healthy) RESUMING_PATROL
##                                               -> (infected) ELIMINATING
##   any lost/invalid target -> REACQUIRING_TARGET
##
## Host-cell knowledge and target reservation live in `nkt_host_registry.gd`;
## this script never scans the scene tree per frame.

signal defeated_signal

enum State {
	SURVEILLANCE,
	MOVING_TO_HOST,
	INSPECTING,
	ELIMINATING,
	RESUMING_PATROL,
	REACQUIRING_TARGET,
}

const COLOR_BODY := Color("#6d2a92")
const COLOR_INNER := Color("#a847c9")
const COLOR_EDGE := Color("#2b0d42")
const COLOR_NUCLEUS := Color("#3a1157")
const COLOR_NUCLEOLUS := Color("#d9a6f2")
const COLOR_GRANULE := Color("#e07bf0")
const COLOR_SCAN := Color(0.82, 0.42, 1.0, 0.85)
const COLOR_ALERT := Color(1.0, 0.58, 0.92, 1.0)
const COLOR_ELIMINATE := Color(0.86, 0.40, 1.0, 1.0)

const EFFECT_DURATION := 0.5
const SCAN_LINE_ALPHA := 0.22

@export var move_speed: float = 78.0
@export var inspect_distance: float = 78.0
@export var inspect_duration: float = 1.1
@export var elimination_windup: float = 0.55
@export var elimination_recover: float = 0.45
@export var body_radius: float = 26.0
@export var max_health: int = 140
@export var contact_disruption_dps: float = 55.0
@export var stuck_skip_time: float = 2.2
@export var notify_radius: float = 1250.0

var state: State = State.SURVEILLANCE
var health: int = 140
var defeated: bool = false
var death_timer: float = 0.0

var registry: Node = null
var index: int = 0
var total_nkts: int = 1
var subset: Dictionary = {}

var target: Node2D = null
var target_id: int = 0

var player: Node2D = null

var inspect_timer: float = 0.0
var eliminate_timer: float = 0.0
var eliminate_done: bool = false
var resume_timer: float = 0.0
var start_delay: float = 0.0

var _reacquire_timer: float = 0.0
var _idle_pick_timer: float = 0.0
var _stuck_timer: float = 0.0
var _notify_cooldown: float = 0.0
var _scan_phase: float = 0.0
var _time: float = 0.0
var _render_accum: float = 0.0

## Host cells already inspected during the current sweep. Once every cell in
## this NKT's section has been seen, the set clears and the sweep starts again,
## so a cell that becomes infected later is re-checked instead of ignored.
var _visited: Dictionary = {}

var _effect_timer: float = 0.0
var _effect_origin: Vector2 = Vector2.ZERO
var _effect_target: Vector2 = Vector2.ZERO

var _home: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("nkt_cells")

	health = max_health
	player = get_tree().get_first_node_in_group("player") as Node2D
	registry = get_tree().get_first_node_in_group("nkt_host_registry")

	_home = global_position
	start_delay = 1.2 + float(index) * 1.1

	queue_redraw()


## Called by the level manager right after the node enters the tree.
func setup(host_registry: Node, cell_index: int, nkt_count: int, delay: float = -1.0) -> void:
	registry = host_registry
	index = cell_index
	total_nkts = maxi(nkt_count, 1)
	if delay >= 0.0:
		start_delay = delay


## Restrict this NKT to a subset of host cells (instance ids). An empty subset
## means "any valid host cell", which is also the fallback when its own section
## has been cleared.
func assign_subset(cell_ids: Array) -> void:
	subset.clear()
	for id in cell_ids:
		subset[int(id)] = true


func _physics_process(delta: float) -> void:
	_time += delta
	_notify_cooldown = maxf(_notify_cooldown - delta, 0.0)
	_effect_timer = maxf(_effect_timer - delta, 0.0)

	if defeated:
		death_timer += delta
		velocity = Vector2.ZERO
		queue_redraw()
		if death_timer >= 0.45:
			queue_free()
		return

	if not is_instance_valid(registry):
		registry = get_tree().get_first_node_in_group("nkt_host_registry")

	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D

	_update_contact_disruption(delta)

	if start_delay > 0.0:
		start_delay -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		_queue_render(delta)
		return

	match state:
		State.SURVEILLANCE:
			_tick_surveillance(delta)
		State.MOVING_TO_HOST:
			_tick_moving(delta)
		State.INSPECTING:
			_tick_inspecting(delta)
		State.ELIMINATING:
			_tick_eliminating(delta)
		State.RESUMING_PATROL:
			_tick_resuming(delta)
		State.REACQUIRING_TARGET:
			_tick_reacquiring(delta)

	move_and_slide()
	_queue_render(delta)


# --------------------------------------------------------------------------
# State machine
# --------------------------------------------------------------------------

func _tick_surveillance(delta: float) -> void:
	velocity = Vector2.ZERO

	_idle_pick_timer -= delta
	if _idle_pick_timer > 0.0:
		return
	_idle_pick_timer = 0.9

	if _pick_next_target():
		state = State.MOVING_TO_HOST
		_stuck_timer = 0.0
		_maybe_notify("NKT CELL APPROACHING HOST CELL", COLOR_ALERT)


func _tick_moving(delta: float) -> void:
	if not _target_is_valid():
		_release_target()
		_enter_reacquiring()
		return

	var to_target: Vector2 = target.global_position - global_position
	var distance: float = to_target.length()

	if distance <= inspect_distance:
		velocity = Vector2.ZERO
		state = State.INSPECTING
		inspect_timer = 0.0
		_scan_phase = 0.0
		return

	var direction: Vector2 = to_target / maxf(distance, 0.001)
	velocity = direction * move_speed

	# Slide around a wall instead of grinding into it; give up on a target that
	# stays unreachable for too long so the route can never deadlock.
	if get_slide_collision_count() > 0:
		_stuck_timer += delta
		if _stuck_timer > 0.45:
			var side := 1.0 if get_instance_id() % 2 == 0 else -1.0
			velocity = (direction + direction.rotated(PI * 0.5) * side * 0.9).normalized() * move_speed
		if _stuck_timer > stuck_skip_time:
			_stuck_timer = 0.0
			_release_target()
			_enter_reacquiring()
	else:
		_stuck_timer = maxf(_stuck_timer - delta * 0.5, 0.0)


func _tick_inspecting(delta: float) -> void:
	velocity = Vector2.ZERO

	if not _target_is_valid():
		_release_target()
		_enter_reacquiring()
		return

	inspect_timer += delta
	_scan_phase += delta * 5.0

	if inspect_timer < inspect_duration:
		return

	# Remember this inspection for the current sweep.
	_visited[target_id] = true

	# Use the real infection state - never the cell's appearance.
	if target.get("infected") == true:
		state = State.ELIMINATING
		eliminate_timer = 0.0
		eliminate_done = false
		_maybe_notify("INFECTED HOST CELL DETECTED", COLOR_ALERT)
	else:
		_release_target()
		state = State.RESUMING_PATROL
		resume_timer = 0.25


func _tick_eliminating(delta: float) -> void:
	if not eliminate_done:
		if not _target_is_valid():
			_release_target()
			_enter_reacquiring()
			return

		eliminate_timer += delta
		var distance: float = global_position.distance_to(target.global_position)
		if distance > inspect_distance * 0.55:
			velocity = global_position.direction_to(target.global_position) * move_speed * 0.6
		else:
			velocity = Vector2.ZERO

		if eliminate_timer >= elimination_windup:
			eliminate_done = true
			_effect_timer = EFFECT_DURATION
			_effect_origin = global_position
			_effect_target = target.global_position

			# The host cell owns the destruction of itself and of the minions it
			# produced, so the cleanup rules live in one place.
			if target.has_method("eliminate"):
				target.eliminate(self)

			_maybe_notify("INFECTED CELL ELIMINATED", COLOR_ELIMINATE)
		return

	eliminate_timer += delta
	velocity = Vector2.ZERO

	if eliminate_timer >= elimination_windup + elimination_recover:
		_release_target()
		state = State.RESUMING_PATROL
		resume_timer = 0.25


func _tick_resuming(delta: float) -> void:
	velocity = Vector2.ZERO
	resume_timer -= delta
	if resume_timer <= 0.0:
		state = State.SURVEILLANCE


func _tick_reacquiring(delta: float) -> void:
	velocity = Vector2.ZERO
	_reacquire_timer -= delta
	if _reacquire_timer > 0.0:
		return

	if _pick_next_target():
		state = State.MOVING_TO_HOST
		_stuck_timer = 0.0
	else:
		state = State.SURVEILLANCE
		_idle_pick_timer = 0.5


func _enter_reacquiring() -> void:
	state = State.REACQUIRING_TARGET
	_reacquire_timer = 0.35


# --------------------------------------------------------------------------
# Target selection
# --------------------------------------------------------------------------

func _pick_next_target() -> bool:
	if not is_instance_valid(registry):
		return false

	var owner_id := get_instance_id()

	# Prefer unvisited cells inside this NKT's own section.
	var cell: Node2D = registry.pick_nearest(
		global_position, _allowed_ids(true, true), owner_id
	)

	# Section fully inspected: begin a new sweep so newly infected cells are
	# re-checked (the infection may have happened after the first visit).
	if cell == null:
		_visited.clear()
		cell = registry.pick_nearest(
			global_position, _allowed_ids(false, true), owner_id
		)

	# Section empty or every cell already claimed: assist the rest of the
	# airway rather than idling, so the surveillance never deadlocks.
	if cell == null and not subset.is_empty():
		cell = registry.pick_nearest(
			global_position, _allowed_ids(false, false), owner_id
		)

	if cell == null:
		return false

	if not registry.claim(cell, owner_id):
		return false

	target = cell
	target_id = cell.get_instance_id()
	return true


func _allowed_ids(exclude_visited: bool, restrict_subset: bool) -> Dictionary:
	var allowed := {}

	if not is_instance_valid(registry):
		return allowed

	for node in registry.valid_cells():
		if not is_instance_valid(node):
			continue

		var id: int = node.get_instance_id()

		if restrict_subset and not subset.is_empty() and not subset.has(id):
			continue

		if exclude_visited and _visited.has(id):
			continue

		allowed[id] = true

	return allowed


func _target_is_valid() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target.is_queued_for_deletion():
		return false
	if not target.is_in_group("host_cells"):
		return false
	if target.get("eliminated") == true:
		return false
	return true


func _release_target() -> void:
	if is_instance_valid(registry):
		if target != null and is_instance_valid(target):
			registry.release(target, get_instance_id())
		registry.release_all(get_instance_id())
	target = null
	target_id = 0


func _exit_tree() -> void:
	if is_instance_valid(registry):
		registry.release_all(get_instance_id())


# --------------------------------------------------------------------------
# Player counterplay: disrupt the NKT by pressing against it
# --------------------------------------------------------------------------

func _update_contact_disruption(delta: float) -> void:
	if not is_instance_valid(player) or not player.visible:
		return
	if global_position.distance_to(player.global_position) <= body_radius + 22.0:
		var amount := maxi(1, int(round(contact_disruption_dps * delta)))
		take_damage(amount)


func take_damage(amount: int) -> void:
	if defeated or amount <= 0:
		return

	health = maxi(health - amount, 0)
	queue_redraw()

	if health <= 0:
		defeated = true
		death_timer = 0.0
		velocity = Vector2.ZERO
		_release_target()
		remove_from_group("nkt_cells")
		defeated_signal.emit()
		print("[NKT] NKT cell disrupted - surveillance lost.")


func is_alerting() -> bool:
	return state == State.INSPECTING or state == State.ELIMINATING


# --------------------------------------------------------------------------
# Notifications
# --------------------------------------------------------------------------

func _maybe_notify(text: String, color: Color) -> void:
	if _notify_cooldown > 0.0:
		return
	if is_instance_valid(player) and global_position.distance_to(player.global_position) > notify_radius:
		return

	_notify_cooldown = 5.0
	var hud := get_tree().get_first_node_in_group("hud")
	if is_instance_valid(hud) and hud.has_method("show_notification"):
		hud.show_notification(text, color)


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

func _queue_render(delta: float) -> void:
	_render_accum -= delta
	if (
		_render_accum <= 0.0
		or _effect_timer > 0.0
		or state == State.INSPECTING
		or state == State.ELIMINATING
	):
		_render_accum = 0.033
		queue_redraw()


func _draw() -> void:
	if defeated:
		var progress := clampf(death_timer / 0.45, 0.0, 1.0)
		draw_circle(Vector2.ZERO, body_radius * (1.0 - progress), Color(COLOR_BODY.r, COLOR_BODY.g, COLOR_BODY.b, 1.0 - progress))
		draw_circle(Vector2.ZERO, body_radius * 0.4 * (1.0 - progress), Color(COLOR_NUCLEUS.r, COLOR_NUCLEUS.g, COLOR_NUCLEUS.b, 1.0 - progress))
		return

	_draw_scanning()
	_draw_aura()
	_draw_body()
	_draw_nucleus()
	_draw_granules()
	_draw_health_bar()
	_draw_effect()


func _draw_body() -> void:
	var pts := PackedVector2Array()
	var segments := 30
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var r := body_radius * (
			1.0
			+ 0.055 * sin(a * 3.0 + _time * 1.6)
			+ 0.030 * sin(a * 5.0 - _time * 1.1)
		)
		pts.append(Vector2(cos(a), sin(a)) * r)

	draw_colored_polygon(pts, COLOR_BODY)

	var inner := PackedVector2Array()
	for p in pts:
		inner.append(p * 0.80)
	draw_colored_polygon(inner, COLOR_INNER)

	# A lymphocyte is round and fairly smooth; short microvilli give it life.
	for i in range(10):
		var a := TAU * float(i) / 10.0 + _time * 0.25
		var dir := Vector2(cos(a), sin(a))
		var base := dir * body_radius * 0.94
		var tip := dir * body_radius * (1.08 + 0.06 * sin(_time * 2.0 + float(i)))
		draw_line(base, tip, Color(COLOR_EDGE.r, COLOR_EDGE.g, COLOR_EDGE.b, 0.7), 2.0, true)

	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, COLOR_EDGE, 2.6, true)


func _draw_nucleus() -> void:
	# Large, slightly indented lymphocyte nucleus.
	var center := Vector2(-body_radius * 0.08, -body_radius * 0.05)
	var seg := 26
	var pts := PackedVector2Array()
	for i in range(seg):
		var a := TAU * float(i) / float(seg)
		var r := body_radius * 0.46 * (1.0 + 0.08 * sin(a * 2.0 + _time * 0.7))
		pts.append(center + Vector2(cos(a) * r * 1.08, sin(a) * r * 0.92))

	draw_colored_polygon(pts, COLOR_NUCLEUS)

	# The indentation that makes the nucleus read as lymphocyte-like.
	draw_circle(center + Vector2(body_radius * 0.20, -body_radius * 0.08), body_radius * 0.14, COLOR_INNER)
	draw_circle(center + Vector2(-body_radius * 0.10, -body_radius * 0.12), body_radius * 0.07, COLOR_NUCLEOLUS)


func _draw_granules() -> void:
	var offsets := [
		Vector2(0.42, 0.30), Vector2(-0.44, 0.24), Vector2(0.20, 0.46),
		Vector2(-0.30, -0.40), Vector2(0.44, -0.28), Vector2(-0.10, 0.52),
	]
	for i in range(offsets.size()):
		var o: Vector2 = offsets[i] * body_radius
		o += Vector2(sin(_time * 1.2 + float(i)), cos(_time * 0.9 + float(i) * 1.4)) * 1.6
		draw_circle(o, 2.2, COLOR_GRANULE)


func _draw_aura() -> void:
	var pulse := 1.0 + 0.06 * sin(_time * 2.2)
	draw_arc(Vector2.ZERO, body_radius * 1.32 * pulse, 0.0, TAU, 32, Color(0.70, 0.35, 0.95, 0.22), 1.6, true)


func _draw_scanning() -> void:
	if not _target_is_valid():
		return

	if state != State.INSPECTING and state != State.ELIMINATING:
		return

	var target_local := to_local(target.global_position)
	var line_color := Color(COLOR_SCAN.r, COLOR_SCAN.g, COLOR_SCAN.b, SCAN_LINE_ALPHA)
	draw_line(Vector2.ZERO, target_local, line_color, 1.5, true)

	var ring_color := COLOR_SCAN if state == State.INSPECTING else COLOR_ELIMINATE
	draw_arc(target_local, 34.0, 0.0, TAU, 28, Color(ring_color.r, ring_color.g, ring_color.b, 0.30), 1.6, true)

	if state == State.INSPECTING:
		var sweep := fposmod(_scan_phase, TAU)
		draw_arc(Vector2.ZERO, body_radius + 12.0, sweep, sweep + 1.3, 18, ring_color, 2.6, true)
		draw_arc(Vector2.ZERO, body_radius + 12.0, 0.0, TAU, 32, Color(ring_color.r, ring_color.g, ring_color.b, 0.16), 1.4, true)
	else:
		var progress := clampf(eliminate_timer / maxf(elimination_windup, 0.001), 0.0, 1.0)
		draw_line(Vector2.ZERO, target_local, Color(ring_color.r, ring_color.g, ring_color.b, 0.55), 3.0, true)
		draw_arc(target_local, 30.0 + 16.0 * progress, 0.0, TAU, 26, Color(ring_color.r, ring_color.g, ring_color.b, 0.7), 2.2, true)


func _draw_effect() -> void:
	if _effect_timer <= 0.0:
		return

	var progress := 1.0 - _effect_timer / EFFECT_DURATION
	var center := to_local(_effect_target)

	var radius := 12.0 + 74.0 * progress
	draw_arc(center, radius, 0.0, TAU, 30, Color(COLOR_ELIMINATE.r, COLOR_ELIMINATE.g, COLOR_ELIMINATE.b, 1.0 - progress), 3.0 * (1.0 - progress) + 1.0, true)
	draw_arc(center, radius * 0.62, 0.0, TAU, 24, Color(COLOR_ALERT.r, COLOR_ALERT.g, COLOR_ALERT.b, 0.7 * (1.0 - progress)), 2.0, true)

	for i in range(8):
		var a := TAU * float(i) / 8.0 + 0.4
		var p := center + Vector2(cos(a), sin(a)) * radius * 0.92
		draw_circle(p, 3.0 * (1.0 - progress), Color(COLOR_GRANULE.r, COLOR_GRANULE.g, COLOR_GRANULE.b, 1.0 - progress))


func _draw_health_bar() -> void:
	if health >= max_health or defeated:
		return

	var width := 58.0
	var height := 6.0
	var pos := Vector2(-width * 0.5, -body_radius - 20.0)
	draw_rect(Rect2(pos, Vector2(width, height)), Color("#211428"))

	var ratio := clampf(float(health) / float(max_health), 0.0, 1.0)
	var color := Color(0.82, 0.42, 1.0)
	if ratio <= 0.5:
		color = Color("#ffb347")
	if ratio <= 0.25:
		color = Color("#ff6b8a")

	draw_rect(Rect2(pos, Vector2(width * ratio, height)), color)
	draw_rect(Rect2(pos, Vector2(width, height)), Color("#f0dcff"), false, 1.0)
