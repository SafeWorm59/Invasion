extends Node2D

const MAP := preload("res://scenes/lungs_map.gd")
const HOST_CELL_SCENE := preload("res://scenes/cell.tscn")
const NEUTROPHIL_SCENE := preload("res://scenes/neutrophil.tscn")
const MACROPHAGE_SCENE := preload("res://scenes/macrophage.tscn")
const B_CELL_SCENE := preload("res://scenes/b_cell.tscn")

const HOST_CELL_PLAN := {
	5: 1, 6: 1, 7: 1, 8: 1,
	9: 2, 10: 2, 11: 2, 12: 2,
	13: 2, 14: 2, 15: 2, 16: 2,
}

const NEUTROPHIL_PLAN := {
	2: 1, 3: 1, 4: 1, 5: 2, 6: 1,
	7: 2, 8: 1, 9: 1, 10: 1, 13: 1, 15: 1,
}

const MACROPHAGE_PLAN := {
	5: 1, 6: 1, 8: 1, 12: 1, 16: 1,
}

const B_CELL_PLAN := {
	3: 1, 4: 1, 5: 1, 8: 1, 10: 1, 14: 1,
}

const EXIT_RADIUS := 64.0
const GOLDEN_ANGLE := 2.399963229728653

var _hud: Node = null
var _total_cells: int = 0
var _completed_cells: int = 0
var _exit: Area2D = null
var _exit_visual: Polygon2D = null
var _exit_ring: Line2D = null
var _exit_label: Label = null
var _exit_locked: bool = true
var _level_complete: bool = false


func _ready() -> void:
	add_to_group("lungs_gameplay")
	_hud = get_tree().get_first_node_in_group("hud")
	_spawn_host_cells()
	_spawn_neutrophils()
	_spawn_macrophages()
	_spawn_b_cells()
	_create_exit()
	_update_objective()
	print(
		"[Lungs] Gameplay ready - %d host cells, %d neutrophils, %d macrophages, %d B cells."
		% [
			_total_cells,
			_count_plan(NEUTROPHIL_PLAN),
			_count_plan(MACROPHAGE_PLAN),
			_count_plan(B_CELL_PLAN),
		]
	)


func _count_plan(plan: Dictionary) -> int:
	var total := 0
	for chamber in plan:
		total += int(plan[chamber])
	return total


func _spawn_host_cells() -> void:
	var seed_offset := 0
	for chamber in HOST_CELL_PLAN:
		var count: int = HOST_CELL_PLAN[chamber]
		for spawn_position in _scatter(chamber, count, seed_offset, 0.52, 62.0):
			var cell := HOST_CELL_SCENE.instantiate() as Node2D
			cell.global_position = spawn_position
			add_child(cell)
			_total_cells += 1
			if cell.has_signal("objective_completed"):
				cell.objective_completed.connect(_on_host_cell_infected)
		seed_offset += 3


func _spawn_neutrophils() -> void:
	var seed_offset := 17
	for chamber in NEUTROPHIL_PLAN:
		var count: int = NEUTROPHIL_PLAN[chamber]
		for spawn_position in _scatter(chamber, count, seed_offset, 0.50, 58.0):
			var neutrophil := NEUTROPHIL_SCENE.instantiate() as Node2D
			neutrophil.global_position = spawn_position
			add_child(neutrophil)
		seed_offset += 5


func _spawn_macrophages() -> void:
	var seed_offset := 41
	for chamber in MACROPHAGE_PLAN:
		var count: int = MACROPHAGE_PLAN[chamber]
		for spawn_position in _scatter(chamber, count, seed_offset, 0.42, 72.0):
			var macrophage := MACROPHAGE_SCENE.instantiate() as Node2D
			macrophage.global_position = spawn_position
			add_child(macrophage)
		seed_offset += 7


func _spawn_b_cells() -> void:
	var seed_offset := 67
	for chamber in B_CELL_PLAN:
		var count: int = B_CELL_PLAN[chamber]
		for spawn_position in _scatter(chamber, count, seed_offset, 0.36, 68.0):
			var b_cell := B_CELL_SCENE.instantiate() as Node2D
			b_cell.global_position = spawn_position
			add_child(b_cell)
		seed_offset += 11


func _scatter(
	chamber: int, count: int, seed_offset: int, radius_fraction: float, clearance: float
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var center := MAP.chamber_center(chamber)
	var radii := MAP.chamber_radii(chamber)
	for i in range(count):
		var angle := fposmod(float(seed_offset) * 1.9 + float(i) * GOLDEN_ANGLE, TAU)
		var spread := sqrt(0.30 + 0.70 * fposmod(float(i) * 0.6180339887 + float(seed_offset) * 0.11, 1.0))
		var candidate := center + Vector2(
			cos(angle) * radii.x * radius_fraction * spread,
			sin(angle) * radii.y * radius_fraction * spread
		)
		positions.append(_walkable_near(candidate, clearance))
	return positions


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


func _on_host_cell_infected(_cell: Node2D) -> void:
	_completed_cells += 1
	_update_objective()
	print("[Lungs] Host cell infected: %d / %d" % [_completed_cells, _total_cells])
	if _completed_cells >= _total_cells and _total_cells > 0:
		set_exit_locked(false)


func set_exit_locked(locked: bool) -> void:
	_exit_locked = locked
	_apply_exit_visual()
	print("Exit locked. Infect every host cell first." if locked else "Lungs exit unlocked!")


func is_exit_locked() -> bool:
	return _exit_locked


func get_progress() -> Dictionary:
	return {"infected": _completed_cells, "total": _total_cells}


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

	_exit_ring = Line2D.new()
	_exit_ring.name = "ExitRing"
	_exit_ring.points = _closed_circle_points(EXIT_RADIUS + 14.0)
	_exit_ring.width = 7.0
	_exit_ring.joint_mode = Line2D.LINE_JOINT_ROUND
	_exit_ring.antialiased = true
	_exit.add_child(_exit_ring)

	_exit_visual = Polygon2D.new()
	_exit_visual.polygon = _circle_points(EXIT_RADIUS)
	_exit.add_child(_exit_visual)

	_exit_label = Label.new()
	_exit_label.name = "ExitLabel"
	_exit_label.position = Vector2(-120.0, -126.0)
	_exit_label.size = Vector2(240.0, 42.0)
	_exit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_exit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_exit_label.add_theme_font_size_override("font_size", 28)
	_exit_label.add_theme_color_override("font_color", Color.WHITE)
	_exit_label.add_theme_color_override("font_outline_color", Color("#35101D"))
	_exit_label.add_theme_constant_override("outline_size", 6)
	_exit.add_child(_exit_label)

	_exit.global_position = _walkable_near(MAP.route_end(), 40.0)
	_exit.body_entered.connect(_on_exit_body_entered)
	add_child(_exit)
	_apply_exit_visual()


func _closed_circle_points(radius: float) -> PackedVector2Array:
	var points := _circle_points(radius)
	points.append(points[0])
	return points


func _circle_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(28):
		var angle := TAU * float(i) / 28.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _apply_exit_visual() -> void:
	if _exit_visual == null or _exit_ring == null or _exit_label == null:
		return
	if _exit_locked:
		_exit_visual.color = Color(0.90, 0.30, 0.30, 0.35)
		_exit_ring.default_color = Color("#F46B76")
		_exit_label.text = "EXIT LOCKED"
		_exit_label.add_theme_color_override("font_color", Color("#FFE1E3"))
	else:
		_exit_visual.color = Color(0.35, 0.90, 0.45, 0.45)
		_exit_ring.default_color = Color("#86F0A2")
		_exit_label.text = "EXIT"
		_exit_label.add_theme_color_override("font_color", Color("#D9FFE0"))


func _update_objective() -> void:
	if not is_instance_valid(_hud):
		return
	if _hud.has_method("set_objective"):
		if _completed_cells <= 0:
			_hud.set_objective(
				"INFECT THE LEFT AND RIGHT LUNGS",
				"Infect host cells throughout both lung branches and alveoli.",
				0,
				_total_cells
			)
		elif _completed_cells >= _total_cells:
			_hud.set_objective(
				"PRIMARY OBJECTIVE COMPLETE",
				"Return to the tracheal entrance to complete the level.",
				_total_cells,
				_total_cells
			)
		else:
			_hud.set_objective(
				"HOST CELLS INFECTED: %d/%d" % [_completed_cells, _total_cells],
				"Exit locked: infect all host cells in both lungs.",
				_completed_cells,
				_total_cells
			)
	elif _hud.has_method("update_level_objective"):
		_hud.update_level_objective(_completed_cells, _total_cells, "HOST CELLS")


func _on_exit_body_entered(body: Node2D) -> void:
	if _level_complete or _exit_locked or not body.is_in_group("player"):
		return
	_level_complete = true
	_show_completion_popup()


func _show_completion_popup() -> void:
	var popup := AcceptDialog.new()
	popup.title = "LEVEL COMPLETED!"
	popup.dialog_text = "Both lungs cleared. Every host cell has been infected."
	popup.get_ok_button().text = "RETURN TO LEVEL SELECTION"
	get_tree().root.add_child(popup)
	popup.confirmed.connect(_on_completion_confirmed.bind(popup))
	popup.popup_centered()


func _on_completion_confirmed(popup: AcceptDialog) -> void:
	popup.queue_free()
	GameManager.load_level_selection()
