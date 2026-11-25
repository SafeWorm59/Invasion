extends Node2D

# Level 4: Trachea gameplay manager.
#
# Spawns the host cells that make up the objective, distributes neutrophils and
# macrophages as ordinary resistance, and adds the new NKT-cell surveillance
# enemy. The NKT cells do not chase the player: they systematically visit the
# host cells of their own section of the airway, inspect them, and eliminate
# only the ones that are actually infected - together with the minions that
# those cells produced.
#
# Chamber indices refer to MAP.CHAMBERS (19 total across five regions):
#   Upper trachea 0-3, Mid trachea 4-7, Lower trachea 8-11, Carina 12-14,
#   Distal bronchioles 15-18.
# Population: 18 host cells, 16 neutrophils, 7 macrophages, 3 NKT cells.

const MAP := preload("res://scenes/trachea_map.gd")
const HOST_CELL_SCENE := preload("res://scenes/cell.tscn")
const NEUTROPHIL_SCENE := preload("res://scenes/neutrophil.tscn")
const MACROPHAGE_SCENE := preload("res://scenes/macrophage.tscn")
const B_CELL_SCENE := preload("res://scenes/b_cell.tscn")
const DENDRITIC_SCENE := preload("res://scenes/dendritic_cell.tscn")
const NKT_SCENE := preload("res://scenes/nkt_cell.tscn")
const REGISTRY_SCRIPT := preload("res://scenes/nkt_host_registry.gd")
const RESTRAINT_SCAN_INTERVAL: float = 0.25

# chamber -> how many host cells. Every chamber gets at least one so the
# objective spans the whole windpipe, including the carina and both bronchi.
const HOST_CELL_PLAN := {
	0: 1, 1: 1, 2: 1, 3: 1,        # Upper trachea (4)
	4: 1, 5: 1, 6: 1, 7: 1,        # Mid trachea (4)
	8: 1, 9: 1, 10: 1, 11: 1,      # Lower trachea (4)
	12: 1, 13: 1,                  # Carina + left main bronchus (2)
	15: 1, 16: 1, 17: 1, 18: 1,    # Distal side chambers (4)
}

# chamber -> how many neutrophils.
const NEUTROPHIL_PLAN := {
	0: 1, 1: 1, 2: 1, 3: 1,        # Upper trachea (4)
	4: 1, 5: 1, 6: 1,               # Mid trachea (3)
	8: 1, 9: 1, 10: 1, 11: 1,      # Lower trachea (4)
	12: 1,                          # Carina (1)
	15: 1, 16: 1, 17: 1, 18: 1,    # Distal side chambers (4)
}

# chamber -> how many macrophages.
const MACROPHAGE_PLAN := {
	6: 1, 8: 1, 10: 1, 12: 1, 14: 1, 15: 1, 17: 1,
}

# chamber -> how many NKT cells. One per anatomical section, so their patrol
# routes cover different parts of the airway instead of duplicating work.
const NKT_PLAN := {
	1: 1,   # Upper trachea
	5: 1,   # Mid trachea
	10: 1,  # Lower trachea / carina approach
}

# Which MAP regions each NKT is responsible for.
const NKT_SECTIONS := [
	[0],        # NKT 0: upper trachea
	[1],        # NKT 1: mid trachea
	[2, 3, 4],  # NKT 2: lower trachea, bronchi and distal side chambers
]

const EXIT_RADIUS := 64.0

var _hud: Node = null
var _registry: Node = null
var _total_cells: int = 0
var _completed_cells: int = 0
var _cell_ids_by_region: Dictionary = {}
var _exit: Area2D = null
var _exit_visual: Polygon2D = null
var _exit_locked: bool = true
var _level_complete: bool = false


func _ready() -> void:
	add_to_group("trachea_gameplay")
	_hud = get_tree().get_first_node_in_group("hud")

	_spawn_host_cells()
	_create_registry()
	_spawn_neutrophils()
	_spawn_macrophages()
	_spawn_nkt_cells()
	_create_exit()
	_update_objective()

	print(
		"[Trachea] Gameplay ready - %d host cells, %d neutrophils, %d macrophages, %d NKT cells."
		% [
			_total_cells,
			_count_plan(NEUTROPHIL_PLAN),
			_count_plan(MACROPHAGE_PLAN),
			_count_plan(NKT_PLAN),
		]
	)


func _count_plan(plan: Dictionary) -> int:
	var total := 0
	for key in plan:
		total += int(plan[key])
	return total


# --------------------------------------------------------------------------
# Spawning
# --------------------------------------------------------------------------

func _spawn_host_cells() -> void:
	var seed_offset := 0

	for chamber in HOST_CELL_PLAN:
		var count: int = HOST_CELL_PLAN[chamber]
		var region := MAP.chamber_region(chamber)

		for spawn_pos in _scatter(chamber, count, seed_offset, 0.58, 40.0):
			var cell := HOST_CELL_SCENE.instantiate() as Node2D
			cell.global_position = spawn_pos
			add_child(cell)

			_total_cells += 1
			if cell.has_signal("objective_completed"):
				cell.objective_completed.connect(_on_host_cell_infected)

			if not _cell_ids_by_region.has(region):
				_cell_ids_by_region[region] = []
			_cell_ids_by_region[region].append(cell.get_instance_id())

		seed_offset += 3


func _create_registry() -> void:
	_registry = Node.new()
	_registry.name = "NKTHostRegistry"
	_registry.set_script(REGISTRY_SCRIPT)
	add_child(_registry)

	# The registry also refreshes itself every 1.5 s, but build it explicitly
	# now that the host-cell population exists so the NKT cells start informed.
	if _registry.has_method("refresh"):
		_registry.refresh()


func _spawn_neutrophils() -> void:
	var seed_offset := 17

	for chamber in NEUTROPHIL_PLAN:
		var count: int = NEUTROPHIL_PLAN[chamber]
		for spawn_pos in _scatter(chamber, count, seed_offset, 0.56, 55.0):
			var neutrophil := NEUTROPHIL_SCENE.instantiate() as Node2D
			neutrophil.global_position = spawn_pos
			add_child(neutrophil)
			if neutrophil.has_method("set_restraint_scan_interval"):
				neutrophil.set_restraint_scan_interval(RESTRAINT_SCAN_INTERVAL)

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


func _spawn_nkt_cells() -> void:
	var seed_offset := 73
	var index := 0

	for chamber in NKT_PLAN:
		var count: int = NKT_PLAN[chamber]
		for spawn_pos in _scatter(chamber, count, seed_offset, 0.42, 46.0):
			var nkt := NKT_SCENE.instantiate() as Node2D
			nkt.global_position = spawn_pos
			add_child(nkt)

			if nkt.has_method("setup"):
				nkt.setup(_registry, index, _count_plan(NKT_PLAN), 1.5 + float(index) * 2.2)

			if nkt.has_method("assign_subset"):
				nkt.assign_subset(_ids_for_section(index))

			index += 1

		seed_offset += 11


func _ids_for_section(index: int) -> Array:
	var out: Array = []
	if index < 0 or index >= NKT_SECTIONS.size():
		return out

	for region in NKT_SECTIONS[index]:
		if _cell_ids_by_region.has(region):
			out.append_array(_cell_ids_by_region[region])

	return out


# Deterministic scatter inside a chamber, snapped to the nearest walkable spot
# with the requested body clearance so nothing spawns inside a wall.
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


func _walkable_near(target: Vector2, clearance: float = 30.0) -> Vector2:
	if MAP.walkable(target, clearance):
		return target

	for ring in range(1, 9):
		for step in range(8):
			var angle := TAU * float(step) / 8.0
			var probe := target + Vector2(cos(angle), sin(angle)) * float(ring) * 40.0
			if MAP.walkable(probe, clearance):
				return probe

	return target


# --------------------------------------------------------------------------
# Objective and exit
# --------------------------------------------------------------------------

func _on_host_cell_infected(cell: Node2D) -> void:
	# cell.gd emits this exactly once per cell, at infection. Elimination by an
	# NKT cell never decrements it, so completed progress is cumulative and a
	# destroyed infected cell cannot softlock the level.
	_completed_cells += 1
	_update_objective()

	print("[Trachea] Host cell infected: %d / %d" % [_completed_cells, _total_cells])

	if _completed_cells >= _total_cells and _total_cells > 0:
		set_exit_locked(false)
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player) and player.has_method("request_exit_after_entry"):
			player.request_exit_after_entry(cell)


func set_exit_locked(locked: bool) -> void:
	_exit_locked = locked
	if is_instance_valid(_exit):
		_exit.set_meta("exit_unlocked", not locked)
	_apply_exit_visual()
	var minimap := get_tree().get_first_node_in_group("minimap")
	if is_instance_valid(minimap):
		minimap.queue_redraw()
	if not locked:
		call_deferred("_check_exit_overlap_after_unlock")
	print("Exit locked. Infect every host cell first." if locked else "Exit unlocked!")


func _check_exit_overlap_after_unlock() -> void:
	if _exit_locked or _level_complete or not is_instance_valid(_exit):
		return
	for body in _exit.get_overlapping_bodies():
		_on_exit_body_entered(body)
		if _level_complete:
			return


func is_exit_locked() -> bool:
	return _exit_locked


func get_progress() -> Dictionary:
	return {
		"infected": _completed_cells,
		"total": _total_cells,
	}


func _create_exit() -> void:
	_exit = Area2D.new()
	_exit.name = "LevelExit"
	_exit.add_to_group("level_exit")
	_exit.set_meta("exit_unlocked", not _exit_locked)
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
				"INFECT THE TRACHEA",
				"Infect the host cells throughout the trachea.",
				0,
				_total_cells
			)
		elif _completed_cells >= _total_cells:
			_hud.set_objective(
				"%d/%d infected — Reach the exit!"
				% [_completed_cells, _total_cells],
				"The unlocked exit is marked on your minimap.",
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
	GameManager.show_level_completion_dialog(4)
