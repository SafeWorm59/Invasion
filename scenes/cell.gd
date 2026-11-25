extends Node2D

const MINION_SCENE = preload("res://scenes/minion.tscn")
const MINION_MIN_COUNT: int = 1
const MINION_MAX_COUNT: int = 2
const CYTOKINE_PARTICLE_SCRIPT = preload(
	"res://scenes/cytokine_particle.gd"
)

const CYTOKINE_PARTICLE_COUNT: int = 24

signal replication_completed(cell: Node2D)

signal objective_completed(cell: Node2D)

## Emitted once when an immune cell (the NKT cell) destroys this host cell.
## The NKT host registry listens so it can drop the reference immediately.
signal destroyed(cell: Node2D)

const ELIMINATION_DURATION: float = 0.45

var player_nearby: bool = false
var nearby_player: Node2D = null

@export var cell_color: Color = Color("#b94f72")
@export var cell_radius: float = 34.0

var infected: bool = false
var objective_counted: bool = false
var bursting: bool = false
var burst_animation_time: float = 0.0

## Set by the NKT cell. An eliminated cell stops replicating, ejects the
## player, removes its own minions and collapses, but is never freed twice.
var eliminated: bool = false
var elimination_timer: float = 0.0

var warning_active: bool = false
var warning_timer: float = 0.0

const WARNING_DURATION: float = 2.0

const BURST_DURATION: float = 0.2
const FRAGMENT_COUNT: int = 7
const REPLICATION_REDRAW_INTERVAL: float = 0.05

var replication_time: float = 8.0
var replication_started: bool = false
var replication_remaining: float = 0.0
var _replication_countdown: Label
var _replication_redraw_timer: float = 0.0
var _last_countdown_warning: bool = false

var fragment_angles: Array[float] = []
var fragment_distances: Array[float] = []
var fragment_rotations: Array[float] = []


func _ready() -> void:
	randomize()
	_replication_countdown = Label.new()
	_replication_countdown.name = "ReplicationCountdown"
	_replication_countdown.position = Vector2(-50.0, -cell_radius - 31.0)
	_replication_countdown.size = Vector2(100.0, 24.0)
	_replication_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_replication_countdown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_replication_countdown.z_index = 11
	_replication_countdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_replication_countdown.add_theme_font_override("font", ThemeDB.fallback_font)
	_replication_countdown.add_theme_font_size_override("font_size", 18)
	_replication_countdown.add_theme_color_override("font_color", Color.WHITE)
	_replication_countdown.add_theme_color_override("font_outline_color", Color("#1a0b12"))
	_replication_countdown.add_theme_constant_override("outline_size", 3)
	_replication_countdown.visible = false
	add_child(_replication_countdown)
	if not infected and not eliminated:
		add_to_group("uninfected_host_cells")


func _draw() -> void:
	if eliminated:
		var progress: float = clampf(
			elimination_timer / ELIMINATION_DURATION,
			0.0,
			1.0
		)
		var alpha: float = 1.0 - progress
		var radius: float = cell_radius * (1.0 - 0.80 * progress)

		draw_circle(
			Vector2.ZERO,
			radius,
			Color(0.72, 0.34, 0.62, alpha)
		)
		draw_circle(
			Vector2.ZERO,
			radius * 0.70,
			Color(0.92, 0.58, 0.82, alpha * 0.85)
		)
		draw_circle(
			Vector2(5, -4) * (1.0 - progress),
			radius * 0.28,
			Color(0.36, 0.12, 0.42, alpha)
		)

		# Membrane fragments drift outwards as the cell collapses.
		for i in range(9):
			var angle := TAU * float(i) / 9.0 + progress * 1.6
			var distance := cell_radius * (0.35 + progress * 1.15)
			draw_circle(
				Vector2(cos(angle), sin(angle)) * distance,
				3.2 * alpha,
				Color(0.86, 0.46, 0.96, alpha)
			)
		return

	if bursting:
		var progress: float = min(
			burst_animation_time / BURST_DURATION,
			1.0
		)

		for i in range(fragment_angles.size()):
			var angle: float = fragment_angles[i]
			var distance: float = (
				cell_radius * 0.35
				+ fragment_distances[i] * progress
			)

			var fragment_position := Vector2(
				cos(angle),
				sin(angle)
			) * distance

			var fragment_size: float = cell_radius * 0.22
			var rotation: float = fragment_rotations[i] * progress

			var points := PackedVector2Array([
				Vector2(-fragment_size, -fragment_size * 0.5),
				Vector2(fragment_size, -fragment_size),
				Vector2(fragment_size * 0.5, fragment_size)
			])

			for j in range(points.size()):
				points[j] = points[j].rotated(rotation) + fragment_position

			draw_colored_polygon(points, cell_color)

		return

	# Choose the cell's appearance.
	var outer_color: Color = cell_color
	var inner_color: Color = Color("#e58aa0")
	var nucleus_color: Color = Color("#78304f")

	if infected:
		outer_color = Color("#873f9e")
		inner_color = Color("#c16bd6")
		nucleus_color = Color("#4a1e63")

	# Flash the infected cell during the final two seconds.
	if warning_active:
		var flash: float = absf(sin(warning_timer * 12.0))

		outer_color = outer_color.lerp(
			Color("#ff3030"),
			flash * 0.85
		)

		inner_color = inner_color.lerp(
			Color("#ffb0a0"),
			flash * 0.7
		)

	# Draw the cell.
	draw_circle(Vector2.ZERO, cell_radius, outer_color)
	draw_circle(Vector2.ZERO, cell_radius * 0.72, inner_color)
	draw_circle(Vector2(5, -4), cell_radius * 0.28, nucleus_color)
	draw_circle(Vector2(-12, 8), cell_radius * 0.10, Color("#f6b4bd"))


func _on_interaction_area_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		player_nearby = true
		nearby_player = body
		print("Player is near a host cell")


func _on_interaction_area_body_exited(body: Node2D) -> void:
	if body == nearby_player:
		player_nearby = false
		nearby_player = null
		print("Player left the host cell")


func can_player_enter(player: Node2D) -> bool:
	return (
		not eliminated
		and not infected
		and player_nearby
		and nearby_player == player
	)


func try_enter(player: Node2D) -> bool:
	if not can_player_enter(player):
		return false

	if not infect():
		return false

	start_replication()

	player.visible = false
	print("Virus entered a host cell!")
	return true


func infect() -> bool:
	if infected:
		print("This cell is already infected!")
		return false

	infected = true
	objective_counted = true
	remove_from_group("uninfected_host_cells")
	queue_redraw()

	emit_signal("objective_completed", self)

	print("Host cell infected! Replication can begin.")
	return true


func start_replication() -> void:
	if replication_started or bursting or eliminated:
		return

	replication_started = true
	replication_remaining = replication_time
	warning_active = false
	warning_timer = 0.0
	_update_replication_countdown()

	print("Replication started!")


func _update_replication_countdown() -> void:
	if not is_instance_valid(_replication_countdown):
		return

	if _replication_countdown.visible != replication_started:
		_replication_countdown.visible = replication_started
	if not replication_started:
		return

	var countdown_text := str(maxi(int(ceil(replication_remaining)), 0))
	if _replication_countdown.text != countdown_text:
		_replication_countdown.text = countdown_text
	if _last_countdown_warning != warning_active:
		_last_countdown_warning = warning_active
		_replication_countdown.add_theme_color_override(
			"font_color",
			Color("#ff4545") if warning_active else Color.WHITE
		)


func prepare_fragments() -> void:
	fragment_angles.clear()
	fragment_distances.clear()
	fragment_rotations.clear()

	for i in range(FRAGMENT_COUNT):
		fragment_angles.append(randf_range(0.0, TAU))
		fragment_distances.append(
			randf_range(cell_radius * 0.7, cell_radius * 1.5)
		)
		fragment_rotations.append(randf_range(-2.5, 2.5))


func _process(delta: float) -> void:
	if eliminated:
		elimination_timer = min(
			elimination_timer + delta,
			ELIMINATION_DURATION
		)
		queue_redraw()

		if elimination_timer >= ELIMINATION_DURATION:
			queue_free()

		return

	if bursting:
		burst_animation_time = min(
			burst_animation_time + delta,
			BURST_DURATION
		)
		queue_redraw()
		return

	if not replication_started:
		return

	replication_remaining = maxf(
		replication_remaining - delta,
		0.0
	)

	# Activate the warning during the final two seconds.
	if replication_remaining <= WARNING_DURATION:
		warning_active = true
		warning_timer += delta
	else:
		warning_active = false
		warning_timer = 0.0

	_update_replication_countdown()
	_replication_redraw_timer -= delta
	if _replication_redraw_timer <= 0.0:
		_replication_redraw_timer = REPLICATION_REDRAW_INTERVAL
		queue_redraw()

	# Burst when replication finishes.
	if replication_remaining <= 0.0:
		replication_started = false
		warning_active = false
		_update_replication_countdown()
		bursting = true
		burst_animation_time = 0.0

		prepare_fragments()
		queue_redraw()

		print("Replication complete!")
		print("Host cell burst!")
		
		release_chemical_alert()

		spawn_minions()
		replication_completed.emit(self)


func spawn_minions() -> void:
	if eliminated:
		return

	var main_scene := get_tree().current_scene

	if main_scene == null:
		return

	var minion_count := randi_range(
		MINION_MIN_COUNT,
		MINION_MAX_COUNT
	)

	for i in range(minion_count):
		var minion = MINION_SCENE.instantiate()

		var angle := randf_range(0.0, TAU)
		var spawn_offset := Vector2(
			cos(angle),
			sin(angle)
		) * (cell_radius + 25.0)

		main_scene.add_child(minion)
		minion.global_position = global_position + spawn_offset

		# Ownership: the NKT cell removes exactly the minions produced by the
		# host cell it destroys, never the whole level's population.
		minion.set("source_cell", self)
		minion.set("owner_cell_id", get_instance_id())

	print("%d viral minion(s) spawned!" % minion_count)
	
func release_chemical_alert() -> void:
	var main_scene := get_tree().current_scene

	if main_scene == null:
		return

	for i in range(CYTOKINE_PARTICLE_COUNT):
		var particle := CYTOKINE_PARTICLE_SCRIPT.new() as Node2D

		main_scene.add_child(particle)
		particle.setup(global_position)

	print(
		"Host cell released %d chemical signaling particles!"
		% CYTOKINE_PARTICLE_COUNT
	)


# --------------------------------------------------------------------------
# Elimination (NKT cell)
# --------------------------------------------------------------------------

func is_eliminated() -> bool:
	return eliminated


## Destroy this host cell and every minion it produced. Safe to call twice and
## safe while the cell is replicating or bursting: the collapse runs once and
## the node frees itself exactly once.
func eliminate(source: Node = null) -> void:
	if eliminated:
		return

	eliminated = true
	elimination_timer = 0.0

	# Stop infection behaviour immediately so no new minions can appear.
	replication_started = false
	replication_remaining = 0.0
	warning_active = false
	_update_replication_countdown()
	bursting = false

	# Leave the host_cells group at once: minimap, registry and the player's
	# interact scan must never see this cell again.
	remove_from_group("host_cells")
	remove_from_group("uninfected_host_cells")

	_eject_player()
	_dissolve_owned_minions()

	destroyed.emit(self)

	var killer_name := "immune cell"
	if is_instance_valid(source) and source is Node:
		killer_name = (source as Node).name

	print("Host cell eliminated by %s!" % killer_name)
	queue_redraw()


func _eject_player() -> void:
	var player := get_tree().get_first_node_in_group("player")

	if not is_instance_valid(player):
		return

	if player.get("host_cell") != self:
		return

	if player.has_method("force_eject"):
		player.force_eject(self)


func _dissolve_owned_minions() -> void:
	var cell_id := get_instance_id()

	for node in get_tree().get_nodes_in_group("minions"):
		if not is_instance_valid(node):
			continue

		var owned: bool = int(node.get("owner_cell_id")) == cell_id
		var linked: bool = node.get("source_cell") == self

		if owned or linked:
			if node.has_method("dissolve"):
				node.dissolve()
