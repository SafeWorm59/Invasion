
extends Node2D

const MINION_SCENE = preload("res://scenes/minion.tscn")
const MINION_MIN_COUNT: int = 1
const MINION_MAX_COUNT: int = 2
const CYTOKINE_PARTICLE_SCRIPT = preload(
	"res://scenes/cytokine_particle.gd"
)

const CYTOKINE_PARTICLE_COUNT: int = 24

signal replication_completed(cell: Node2D)

var player_nearby: bool = false
var nearby_player: Node2D = null

@export var cell_color: Color = Color("#b94f72")
@export var cell_radius: float = 34.0

var infected: bool = false
var bursting: bool = false
var burst_animation_time: float = 0.0

var warning_active: bool = false
var warning_timer: float = 0.0

const WARNING_DURATION: float = 2.0

const BURST_DURATION: float = 0.2
const FRAGMENT_COUNT: int = 7

var replication_time: float = 8.0
var replication_started: bool = false
var replication_remaining: float = 0.0

var fragment_angles: Array[float] = []
var fragment_distances: Array[float] = []
var fragment_rotations: Array[float] = []


func _ready() -> void:
	randomize()


func _draw() -> void:
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

	# Display the replication countdown above the cell.
	if replication_started:
		var seconds_left: int = int(ceil(replication_remaining))
		var timer_text: String = str(maxi(seconds_left, 0))

		var font := ThemeDB.fallback_font
		var font_size: int = 18
		var text_size: Vector2 = font.get_string_size(
			timer_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size
		)

		var text_color: Color = Color.WHITE

		if warning_active:
			text_color = Color("#ff4545")

		draw_string(
			font,
			Vector2(-text_size.x / 2.0, -cell_radius - 12.0),
			timer_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			text_color
		)


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


func try_enter(player: Node2D) -> bool:
	if not player_nearby:
		return false

	if nearby_player != player:
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
	queue_redraw()

	print("Host cell infected! Replication can begin.")
	return true


func start_replication() -> void:
	if replication_started or bursting:
		return

	replication_started = true
	replication_remaining = replication_time
	warning_active = false
	warning_timer = 0.0

	print("Replication started!")


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

	queue_redraw()

	# Burst when replication finishes.
	if replication_remaining <= 0.0:
		replication_started = false
		warning_active = false
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
