extends Node2D

# Level 3: Larynx gameplay manager.
#
# Spawns the host cells that make up the objective, distributes neutrophils,
# macrophages and the new dendritic-cell sentinels as resistance, tracks how
# many host cells the player has infected, and keeps the level exit locked
# until every host cell is infected.
#
# Chamber indices refer to MAP.CHAMBERS (15 total across three regions):
#   Supraglottis 0-4, Glottis 5-8, Subglottis 9-14.
# Population targets: 20 host cells, 16 neutrophils, 7 macrophages,
# 5 dendritic cells.

const MAP := preload("res://scenes/larynx_map.gd")
const HOST_CELL_SCENE := preload("res://scenes/cell.tscn")
const NEUTROPHIL_SCENE := preload("res://scenes/neutrophil.tscn")
const MACROPHAGE_SCENE := preload("res://scenes/macrophage.tscn")
const DENDRITIC_SCENE := preload("res://scenes/dendritic_cell.tscn")

# chamber -> how many host cells.
const HOST_CELL_PLAN := {
	0: 1, 1: 1, 2: 2,          # Supraglottis
	3: 2, 4: 2,                # Vestibular folds
	6: 2, 7: 2, 8: 1,          # Ventricles / vocal folds
	9: 2, 10: 2,               # Subglottis / cricoid
	11: 1, 12: 1, 13: 1,       # Cricoid alcoves / trachea
}

# chamber -> how many neutrophils.
const NEUTROPHIL_PLAN := {
	1: 1, 2: 2, 3: 2, 4: 2,    # Supraglottis
	5: 1, 6: 1, 7: 1, 8: 2,    # Glottis
	9: 1, 10: 2,               # Subglottis / cricoid
}

# chamber -> how many macrophages.
const MACROPHAGE_PLAN := {
	2: 1, 5: 1, 6: 1, 7: 1, 9: 1, 10: 2,
}

# chamber -> how many dendritic sentinels. Placed on vantage points that cover
# the major passages: the inlet, the vestibule, the glottis, the subglottis and
# the trachea approach.
const DENDRITIC_PLAN := {
	1: 1, 2: 1, 5: 1, 9: 1, 13: 1,
}

const EXIT_RADIUS := 64.0

var _hud: Node = null
var _total_cells: int = 0
var _completed_cells: int = 0
var _exit: Area2D = null
var _exit_visual: Polygon2D = null
var _exit_locked: bool = true
var _level_complete: bool = false


func _ready() -> void:
	add_to_group("larynx_gameplay")
	_hud = get_tree().get_first_node_in_group("hud")

	_spawn_host_cells()
	_spawn_neutrophils()
	_spawn_macrophages()
	_spawn_dendritic_cells()
	_create_exit()
	_update_objective()

	print(
		"[Larynx] Gameplay ready - %d host cells, %d neutrophils, %d macrophages, %d dendritic cells."
		% [
			_total_cells,
			_count_plan(NEUTROPHIL_PLAN),
			_count_plan(MACROPHAGE_PLAN),
			_count_plan(DENDRITIC_PLAN),
		]
	)


func _count_plan(plan: Dictionary) -> int:
	var total := 0
	for key in plan:
		total += int(plan[key])
	return total


func _spawn_host_cells() -> void:
	var seed_offset := 0

	for chamber in HOST_CELL_PLAN:
		var count: int = HOST_CELL_PLAN[chamber]
		for spawn_pos in _scatter(chamber, count, seed_offset, 0.58, 40.0):
			var cell := HOST_CELL_SCENE.instantiate() as Node2D
			cell.global_position = spawn_pos
			add_child(cell)

			_total_cells += 1
			if cell.has_signal("objective_completed"):
				cell.objective_completed.connect(_on_host_cell_infected)

		seed_offset += 3


func _spawn_neutrophils() -> void:
	var seed_offset := 17

	for chamber in NEUTROPHIL_PLAN:
		var count: int = NEUTROPHIL_PLAN[chamber]
		for spawn_pos in _scatter(chamber, count, seed_offset, 0.56, 55.0):
			var neutrophil := NEUTROPHIL_SCENE.instantiate() as Node2D
			neutrophil.global_position = spawn_pos
			add_child(neutrophil)

		seed_offset += 5


func _spawn_macrophages() -> void:
	var seed_offset := 41

	for chamber in MACROPHAGE_PLAN:
		var count: int = MACROPHAGE_PLAN[chamber]
		for spawn_pos in _scatter(chamber, count, seed_offset, 0.48, 70.0):
			var macrophage := MACROPHAGE_SCENE.instantiate() as Node2D
			macrophage.global_position = spawn_pos
			add_child(macrophage)

		seed_offset += 7


func _spawn_dendritic_cells() -> void:
	var seed_offset := 73

	for chamber in DENDRITIC_PLAN:
		var count: int = DENDRITIC_PLAN[chamber]
		for spawn_pos in _scatter(chamber, count, seed_offset, 0.42, 46.0):
			var dendritic := DENDRITIC_SCENE.instantiate() as Node2D
			dendritic.global_position = spawn_pos
			add_child(dendritic)

			# Generate chamber-wide strategic patrol waypoints
			var c_center := MAP.chamber_center(chamber)
			var c_radii := MAP.chamber_radii(chamber)
			var waypoints: Array[Vector2] = [spawn_pos]
			var angles := [0.0, PI * 0.5, PI, PI * 1.5]
			for a in angles:
				var candidate := c_center + Vector2(cos(a) * c_radii.x * 0.45, sin(a) * c_radii.y * 0.40)
				waypoints.append(_walkable_near(candidate, 46.0))

			if dendritic.has_method("setup_patrol"):
				dendritic.setup_patrol(waypoints)

		seed_offset += 11


# Deterministic scatter inside a chamber, snapped to the nearest walkable spot
# with the requested body clearance so nothing spawns inside a wall or fold.
func _scatter(
	chamber: int, count: int, seed_offset: int, radius_frac: float, clearance: float
) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var center := MAP.chamber_center(chamber)
	var radii := MAP.chamber_radii(chamber)
	var golden := 2.399963229728653

	for k in range(count):
		var angle := fposmod(float(seed_offset) * 1.9 + float(k) * golden, TAU)
		var spread := sqrt(0.30 + 0.70 * fposmod(float(k) * 0.6180339887 + float(seed_offset) * 0.11, 1.0))
		var frac := radius_frac * spread
		var candidate := center + Vector2(cos(angle) * radii.x * frac, sin(angle) * radii.y * frac)
		out.append(_walkable_near(candidate, clearance))

	return out


func _create_exit() -> void:
	_exit = Area2D.new()
	_exit.name = "LevelExit"
	_exit.add_to_group("level_exit")
	_exit.collision_layer = 0
	_exit.collision_mask = 0xFFFFFFFF

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = EXIT_RADIUS
	shape.shape = circle
	_exit.add_child(shape)

	_exit_visual = Polygon2D.new()
	_exit_visual.polygon = _circle_points(EXIT_RADIUS)
	_exit.add_child(_exit_visual)

	_exit.global_position = _walkable_near(_route_end(), 40.0)
	_exit.body_entered.connect(_on_exit_body_entered)
	add_child(_exit)

	_apply_exit_visual()


func _circle_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var segments := 28
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _route_end() -> Vector2:
	var route: Array = MAP.ROUTE
	return route[route.size() - 1]


func _walkable_near(target: Vector2, clearance: float = 30.0) -> Vector2:
	if MAP.walkable(target, clearance):
		return target
	# Reduced probe count: 8 rings × 8 steps = 64 checks (was 272).
	# Still covers the local area effectively while being ~4x faster.
	for ring in range(1, 9):
		for step in range(8):
			var angle := TAU * float(step) / 8.0
			var probe := target + Vector2(cos(angle), sin(angle)) * float(ring) * 40.0
			if MAP.walkable(probe, clearance):
				return probe
	return target


func _on_host_cell_infected(_cell: Node2D) -> void:
	_completed_cells += 1
	_update_objective()

	print("[Larynx] Host cell infected: %d / %d" % [_completed_cells, _total_cells])

	if _completed_cells >= _total_cells and _total_cells > 0:
		set_exit_locked(false)


func set_exit_locked(locked: bool) -> void:
	_exit_locked = locked
	_apply_exit_visual()
	print("Exit locked. Infect every host cell first." if locked else "Exit unlocked!")


func is_exit_locked() -> bool:
	return _exit_locked


func _apply_exit_visual() -> void:
	if _exit_visual == null:
		return
	if _exit_locked:
		_exit_visual.color = Color(0.90, 0.30, 0.30, 0.35)
	else:
		_exit_visual.color = Color(0.35, 0.90, 0.45, 0.45)


func _update_objective() -> void:
	if not is_instance_valid(_hud):
		return

	if _hud.has_method("set_objective"):
		if _completed_cells <= 0:
			_hud.set_objective(
				"INFECT THE LARYNX",
				"Infect the host cells throughout the larynx.",
				0,
				_total_cells
			)
		elif _completed_cells >= _total_cells:
			_hud.set_objective(
				"PRIMARY OBJECTIVE COMPLETE",
				"Reach the tracheal exit.",
				_total_cells,
				_total_cells
			)
		else:
			_hud.set_objective(
				"HOST CELLS INFECTED: %d/%d" % [_completed_cells, _total_cells],
				"Exit locked: infect all host cells.",
				_completed_cells,
				_total_cells
			)
	elif _hud.has_method("update_level_objective"):
		_hud.update_level_objective(_completed_cells, _total_cells, "HOST CELLS")


func _on_exit_body_entered(body: Node2D) -> void:
	if _level_complete or _exit_locked:
		return
	if not body.is_in_group("player"):
		return

	_level_complete = true
	_show_completion_popup()


func _show_completion_popup() -> void:
	GameManager.show_level_completion_dialog(3)