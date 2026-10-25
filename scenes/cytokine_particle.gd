
extends Node2D

@export var particle_speed: float = 78.0
@export var particle_lifetime: float = 12.0
@export var detection_radius: float = 42.0

const TRAIL_POINT_INTERVAL: float = 0.07
const MAX_TRAIL_POINTS: int = 24
const FOLLOW_DISTANCE_MIN: float = 28.0
const FOLLOW_DISTANCE_MAX: float = 65.0
const FOLLOW_RANGE: float = 190.0

var source_position: Vector2 = Vector2.ZERO
var travel_direction: Vector2 = Vector2.RIGHT
var remaining_lifetime: float = 12.0
var particle_size: float = 2.0

var is_leader: bool = false
var personal_speed: float = 78.0
var side_offset: float = 0.0
var movement_phase: float = 0.0

var trail_points: Array[Vector2] = []
var trail_timer: float = 0.0


func setup(origin: Vector2) -> void:
	source_position = origin
	global_position = origin
	remaining_lifetime = particle_lifetime

	add_to_group("cytokine_particles")

	if get_tree().get_nodes_in_group("cytokine_leaders").is_empty():
		is_leader = true
	elif randf() < 0.22:
		is_leader = true

	if is_leader:
		add_to_group("cytokine_leaders")

	personal_speed = particle_speed * randf_range(0.75, 1.25)
	particle_size = randf_range(1.5, 2.5)
	side_offset = randf_range(-55.0, 55.0)
	movement_phase = randf_range(0.0, TAU)

	travel_direction = Vector2.RIGHT.rotated(
		randf_range(0.0, TAU)
	)

	if not is_leader:
		var leader := find_nearest_leader()

		if is_instance_valid(leader):
			travel_direction = leader.travel_direction.rotated(
				randf_range(-0.7, 0.7)
			)

	trail_points.append(global_position)
	queue_redraw()


func find_nearest_leader() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = FOLLOW_RANGE

	for node in get_tree().get_nodes_in_group("cytokine_leaders"):
		if not is_instance_valid(node) or node == self:
			continue

		if not node is Node2D:
			continue

		var distance: float = global_position.distance_to(
			node.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = node

	return nearest


func find_nearest_immune_cell() -> Node2D:
	var nearest: Node2D = null
	var nearest_distance: float = INF

	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		if node.get("defeated") == true:
			continue

		var distance: float = global_position.distance_to(
			node.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			nearest = node

	return nearest


func _process(delta: float) -> void:
	remaining_lifetime -= delta

	if remaining_lifetime <= 0.0:
		queue_free()
		return

	movement_phase += delta

	var desired_direction: Vector2 = travel_direction

	if is_leader:
		var wandering: float = sin(
			movement_phase * 1.8 + side_offset
		) * 0.75

		desired_direction = travel_direction.rotated(
			wandering * delta
		)

		var immune_cell := find_nearest_immune_cell()

		if is_instance_valid(immune_cell):
			var distance_to_immune: float = global_position.distance_to(
				immune_cell.global_position
			)

			if distance_to_immune < 260.0:
				var toward_immune := global_position.direction_to(
					immune_cell.global_position
				)

				desired_direction = desired_direction.lerp(
					toward_immune,
					minf(delta * 0.8, 0.15)
				).normalized()

	else:
		var leader := find_nearest_leader()

		if is_instance_valid(leader):
			var leader_direction: Vector2 = leader.travel_direction

			var trailing_position: Vector2 = (
				leader.global_position
				- leader_direction * randf_range(
					FOLLOW_DISTANCE_MIN,
					FOLLOW_DISTANCE_MAX
				)
				+ leader_direction.rotated(PI / 2.0) * side_offset
			)

			if global_position.distance_to(trailing_position) > 10.0:
				var toward_trail := global_position.direction_to(
					trailing_position
				)

				desired_direction = travel_direction.lerp(
					toward_trail,
					minf(delta * 1.5, 0.12)
				).normalized()

			desired_direction = desired_direction.rotated(
				sin(movement_phase * 2.0 + side_offset)
				* delta * 0.45
			)

	travel_direction = desired_direction.normalized()
	global_position += travel_direction * personal_speed * delta

	update_trail(delta)
	check_immune_cell_detection()
	queue_redraw()


func update_trail(delta: float) -> void:
	trail_timer += delta

	if trail_timer < TRAIL_POINT_INTERVAL:
		return

	trail_timer = 0.0
	trail_points.append(global_position)

	while trail_points.size() > MAX_TRAIL_POINTS:
		trail_points.pop_front()


func check_immune_cell_detection() -> void:
	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		if node.get("defeated") == true:
			continue

		var immune_cell := node as Node2D

		var distance: float = global_position.distance_to(
			immune_cell.global_position
		)

		# Alert immediately when the particle gets close enough.
		if distance > detection_radius:
			continue

		if immune_cell.has_method("receive_chemical_alert"):
			immune_cell.receive_chemical_alert(source_position)

			print(
				"Chemical particle alerted an immune cell! Distance: ",
				distance
			)

			# Only this particle disappears.
			queue_free()
			return


func _draw() -> void:
	for i in range(1, trail_points.size()):
		var start_point: Vector2 = to_local(trail_points[i - 1])
		var end_point: Vector2 = to_local(trail_points[i])

		var progress: float = float(i) / float(trail_points.size())

		draw_line(
			start_point,
			end_point,
			Color(1.0, 0.72, 0.12, progress * 0.55),
			1.0 + progress * 1.5,
			true
		)

	var glow_color := Color(1.0, 0.75, 0.1, 0.22)
	var core_color := Color("#ffd84d")

	if is_leader:
		glow_color = Color(1.0, 0.8, 0.15, 0.32)
		core_color = Color("#fff09a")

	draw_circle(Vector2.ZERO, particle_size + 2.0, glow_color)
	draw_circle(Vector2.ZERO, particle_size, core_color)

	draw_circle(
		Vector2(-0.5, -0.5),
		particle_size * 0.4,
		Color("#fffbe0")
	)
