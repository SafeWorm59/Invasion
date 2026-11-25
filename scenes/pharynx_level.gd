extends Node2D

# Level 2: Pharynx gameplay manager.
#
# Spawns the host cells that make up the objective, distributes neutrophils and
# macrophages as resistance, tracks how many host cells the player has infected,
# and keeps the level exit locked until every host cell is infected.
#
# Chamber indices refer to MAP.CHAMBERS (18 total across three regions):
#   Nasopharynx 0-2, Oropharynx 3-7 (5 = left tonsil, 6 = right tonsil),
#   Laryngopharynx 8-17.
# Population targets: 24 host cells, 18 neutrophils, 6 macrophages.

const MAP := preload("res://scenes/pharynx_map.gd")
const HOST_CELL_SCENE := preload("res://scenes/cell.tscn")
const NEUTROPHIL_SCENE := preload("res://scenes/neutrophil.tscn")
const MACROPHAGE_SCENE := preload("res://scenes/macrophage.tscn")

const LEFT_TONSIL := 5
const RIGHT_TONSIL := 6

# chamber -> how many host cells. Tonsillar chambers carry the concentration.
const HOST_CELL_PLAN := {
	0: 2, 1: 1, 2: 1,           # Nasopharynx (4)
	3: 1, 4: 2, 7: 2,           # Oropharynx central (5)
	LEFT_TONSIL: 5,             # Left palatine tonsil (5)
	RIGHT_TONSIL: 4,            # Right palatine tonsil (4)
	8: 2, 10: 1, 12: 3,         # Laryngopharynx (6)
}

# chamber -> how many neutrophils. The tonsillar region is the hot zone.
const NEUTROPHIL_PLAN := {
	LEFT_TONSIL: 5,             # Left palatine tonsil / crypt
	RIGHT_TONSIL: 4,            # Right palatine tonsil / crypt
	4: 2, 7: 2, 3: 1,           # Oropharynx surrounding the tonsils
	1: 1, 2: 1,                 # Nasopharynx (avoid the spawn chamber 0)
	8: 1, 12: 1,                # Laryngopharynx
}

# chamber -> how many macrophages. Most guard the tonsils.
const MACROPHAGE_PLAN := {
	LEFT_TONSIL: 2,
	RIGHT_TONSIL: 2,
	4: 1,                       # OroMid
	8: 1,                       # LaryngoUpper
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
	add_to_group("pharynx_gameplay")
	_hud = get_tree().get_first_node_in_group("hud")

	_spawn_host_cells()
	_spawn_neutrophils()
	_spawn_macrophages()
	_create_exit()
	_update_objective()

	print(
		"[Pharynx] Gameplay ready - %d host cells, %d neutrophils, %d macrophages."
		% [
			_total_cells,
			_count_plan(NEUTROPHIL_PLAN),
			_count_plan(MACROPHAGE_PLAN),
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
		var frac := 0.70 if chamber == LEFT_TONSIL or chamber == RIGHT_TONSIL else 0.58

		for spawn_pos in _scatter(chamber, count, seed_offset, frac, 40.0):
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
		var frac := 0.68 if chamber == LEFT_TONSIL or chamber == RIGHT_TONSIL else 0.56

		for spawn_pos in _scatter(chamber, count, seed_offset, frac, 55.0):
			var neutrophil := NEUTROPHIL_SCENE.instantiate() as Node2D
			neutrophil.global_position = spawn_pos
			add_child(neutrophil)

		seed_offset += 5


func _spawn_macrophages() -> void:
	var seed_offset := 41

	for chamber in MACROPHAGE_PLAN:
		var count: int = MACROPHAGE_PLAN[chamber]
		var frac := 0.55 if chamber == LEFT_TONSIL or chamber == RIGHT_TONSIL else 0.48

		for spawn_pos in _scatter(chamber, count, seed_offset, frac, 70.0):
			var macrophage := MACROPHAGE_SCENE.instantiate() as Node2D
			macrophage.global_position = spawn_pos
			add_child(macrophage)

		seed_offset += 7


# Deterministic (non-random) scatter of `count` points inside a chamber: points
# are spread by a golden-angle spiral so nothing stacks, then snapped to the
# nearest walkable spot with the requested body clearance so nothing spawns
# inside a wall or a mucosal fold. Placing along `radius_frac` of the chamber
# radius pushes the payload toward the epithelium in the tonsillar chambers.
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


# Finds the closest walkable point to `target` so nothing spawns inside a wall.
func _walkable_near(target: Vector2, clearance: float = 30.0) -> Vector2:
	if MAP.walkable(target, clearance):
		return target
	for ring in range(1, 18):
		for step in range(16):
			var angle := TAU * float(step) / 16.0
			var probe := target + Vector2(cos(angle), sin(angle)) * float(ring) * 40.0
			if MAP.walkable(probe, clearance):
				return probe
	return target


func _on_host_cell_infected(_cell: Node2D) -> void:
	_completed_cells += 1
	_update_objective()

	print("[Pharynx] Host cell infected: %d / %d" % [_completed_cells, _total_cells])

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
				"ESTABLISH THE INFECTION",
				"Infect the host cells throughout the pharynx.",
				0,
				_total_cells
			)
		elif _completed_cells >= _total_cells:
			_hud.set_objective(
				"PRIMARY OBJECTIVE COMPLETE",
				"Reach the lower esophageal exit.",
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
	GameManager.show_level_completion_dialog(2)