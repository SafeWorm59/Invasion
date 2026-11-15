
extends Node2D

@export var particle_count: int = 35
@export var level_bounds: Rect2 = Rect2(-1700, -3150, 3500, 4650)
@export var drift_speed: float = 9.0

var particles: Array[Dictionary] = []


func _ready() -> void:
	randomize()
	_resolve_bounds()
	create_particles()


func _resolve_bounds() -> void:
	var floor_node := get_parent().get_node_or_null("Floor") as Polygon2D
	if floor_node and floor_node.polygon.size() > 0:
		var min_pos := Vector2(INF, INF)
		var max_pos := Vector2(-INF, -INF)
		for pt in floor_node.polygon:
			var g: Vector2 = to_local(floor_node.to_global(pt))
			min_pos.x = min(min_pos.x, g.x)
			min_pos.y = min(min_pos.y, g.y)
			max_pos.x = max(max_pos.x, g.x)
			max_pos.y = max(max_pos.y, g.y)
		level_bounds = Rect2(min_pos, max_pos - min_pos)


func create_particles() -> void:
	particles.clear()

	var player = get_tree().get_first_node_in_group("player")
	var player_pos: Vector2 = to_local(player.global_position) if player else level_bounds.get_center()

	var floor_node := get_parent().get_node_or_null("Floor") as Polygon2D
	var pocket_node := get_parent().get_node_or_null("Pocket1") as Polygon2D
	var floor_poly := floor_node.polygon if floor_node else PackedVector2Array()
	var pocket_poly := pocket_node.polygon if pocket_node else PackedVector2Array()

	# Place several particles in the initial camera view around the player
	# so they are immediately visible on game start.
	var initial_view_count: int = 6
	var general_count: int = max(0, particle_count - initial_view_count)

	for i in range(initial_view_count):
		var offset := Vector2(
			randf_range(-550.0, 550.0),
			randf_range(-300.0, 300.0)
		)
		_add_particle(player_pos + offset)

	# Distribute the remaining particles across the playable level corridor
	for i in range(general_count):
		var pt := _get_random_level_point(floor_node, pocket_node, floor_poly, pocket_poly)
		_add_particle(pt)

	queue_redraw()


func _get_random_level_point(
	floor_node: Polygon2D,
	pocket_node: Polygon2D,
	floor_poly: PackedVector2Array,
	pocket_poly: PackedVector2Array
) -> Vector2:
	# Try sampling inside the level geometry
	for attempt in range(25):
		var candidate := Vector2(
			randf_range(level_bounds.position.x, level_bounds.end.x),
			randf_range(level_bounds.position.y, level_bounds.end.y)
		)
		if floor_node and Geometry2D.is_point_in_polygon(floor_node.to_local(to_global(candidate)), floor_poly):
			return candidate
		if pocket_node and Geometry2D.is_point_in_polygon(pocket_node.to_local(to_global(candidate)), pocket_poly):
			return candidate

	# Fallback within level bounds
	return Vector2(
		randf_range(level_bounds.position.x, level_bounds.end.x),
		randf_range(level_bounds.position.y, level_bounds.end.y)
	)


func _add_particle(pos: Vector2) -> void:
	particles.append({
		"position": pos,
		"origin": pos,
		"radius": randf_range(2.0, 4.0),
		"color": Color(
			randf_range(0.94, 0.98),
			randf_range(0.86, 0.92),
			randf_range(0.86, 0.92),
			randf_range(0.18, 0.28)
		),
		"speed_y": randf_range(drift_speed * 0.7, drift_speed * 1.3),
		"sway_speed": randf_range(0.8, 1.8),
		"sway_amplitude": randf_range(2.0, 5.0),
		"phase": randf_range(0.0, TAU),
		"time": randf_range(0.0, 100.0),
		"vertical_range": randf_range(300.0, 500.0)
	})


func _process(delta: float) -> void:
	for particle in particles:
		particle.time += delta * particle.sway_speed
		particle.position.y -= particle.speed_y * delta
		particle.position.x += cos(particle.time + particle.phase) * particle.sway_amplitude * delta

		# Soft wrap within its world zone so particles stay distributed in place
		if particle.position.y < particle.origin.y - particle.vertical_range:
			particle.position.y = particle.origin.y + particle.vertical_range

	queue_redraw()


func _draw() -> void:
	for particle in particles:
		draw_circle(
			particle.position,
			particle.radius,
			particle.color
		)
