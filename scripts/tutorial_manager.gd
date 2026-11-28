extends Node

const TUTORIAL_OVERLAY_SCRIPT := preload("res://scenes/tutorial_overlay.gd")

const ENEMY_INTRODUCTIONS: Dictionary = {
	2: {
		"group": "macrophages",
		"title": "NEW THREAT: MACROPHAGE",
		"body": "Macrophages guard areas, pursue nearby targets, and attack or engulf at close range. Keep moving, direct minions with FOLLOW/CAPTURE/DEFEND, and join their attack when one is restrained.",
	},
	3: {
		"group": "dendritic_cells",
		"title": "NEW THREAT: DENDRITIC CELL",
		"body": "Dendritic cells patrol and alert nearby immune cells when they detect you. Stay clear of their contact, avoid detection where possible, and move away if an alert draws defenders to your position.",
	},
	4: {
		"group": "nkt_cells",
		"title": "NEW THREAT: NKT CELL",
		"body": "NKT cells inspect host cells rather than chase you. They damage you on contact and destroy infected cells and their minions; keep moving and don't count on an infection staying safe.",
	},
	5: {
		"group": "b_cells",
		"title": "NEW THREAT: B CELL",
		"body": "B cells keep their distance and fire three-shot spreads of antibody projectiles at you. Keep moving to evade the volley and use your minions for support.",
	},
}

var _active: bool = false
var _information_modal_open: bool = false
var _continue_enabled: bool = false
var _previous_tree_paused: bool = false
var _range_check_timer: float = 0.0
var _infection_prompt_in_range: bool = false
var _level_id: int = 0
var _step_index: int = -1
var _current_action: String = ""
var _hud: Node = null
var _overlay: TutorialOverlay = null
var _steps: Array[Dictionary] = []
var _host_cell: Node2D = null
var _player: Node2D = null
var _level_exit: Node2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().scene_changed.connect(_on_scene_changed)


func start_for_current_level(hud: Node) -> void:
	if _active or not is_instance_valid(hud):
		return

	var current_scene := get_tree().current_scene
	if not is_instance_valid(current_scene):
		return

	var level_id := 0
	for level in GameManager.get_levels():
		if String(level.get("scene_path", "")) == current_scene.scene_file_path:
			level_id = int(level.get("id", 0))
			break
	if level_id == 0 or GameManager.is_tutorial_completed(level_id):
		return

	_hud = hud
	_level_id = level_id
	if level_id == 1:
		_start_level_one_tutorial(current_scene)
	else:
		_start_enemy_introduction(level_id)


func _start_level_one_tutorial(current_scene: Node) -> void:
	_player = get_tree().get_first_node_in_group("player") as Node2D
	_host_cell = _nearest_group_node("host_cells", _player)
	if not is_instance_valid(_host_cell):
		_host_cell = _nearest_group_node("uninfected_host_cells", _player)
	if not is_instance_valid(_host_cell):
		push_warning("TutorialManager: Level 1 has no available host cell to introduce.")
		return

	var neutrophil := _nearest_group_node("neutrophils", _player)
	_level_exit = current_scene.get_node_or_null("LevelExit") as Node2D
	if not is_instance_valid(_level_exit):
		_level_exit = _nearest_group_node("level_exit", _player)

	_steps = [
		{
			"title": "MOVEMENT & CAMERA",
			"body": "Move the virus to get started. The camera follows automatically; there are no manual camera controls.",
			"hint": "WASD / ARROW KEYS  |  ANDROID: ON-SCREEN JOYSTICK",
			"control": "joystick",
			"action": "move",
			"show_continue": false,
			"enabled": false,
			"pause": false,
		},
		{
			"title": "HOST CELLS",
			"body": "Host cells are the virus's foothold. Infecting one lets it produce viral minions that can fight immune cells. Move toward the highlighted cell.",
			"hint": "KEEP MOVING - THE CELL WILL NOT BE INFECTED FOR YOU",
			"target": _host_cell,
			"action": "continue",
			"button": "NEXT",
			"enabled": true,
			"pause": false,
		},
		{
			"title": "INFECTION",
			"body": "Move close to the highlighted host cell. The infection action only works when you are in range.",
			"hint": "MOVE CLOSER TO THE HIGHLIGHTED CELL",
			"target": _host_cell,
			"action": "infect",
			"show_continue": false,
			"enabled": false,
			"pause": false,
		},
		{
			"title": "FIRST ENEMY: NEUTROPHIL",
			"body": "Neutrophils patrol, chase nearby viruses, and damage your health with close-range strikes. Keep moving to evade them. When your minions restrain one, use the context action to join their attack.",
			"hint": "E / INFECT BUTTON  |  ANDROID: CONTEXT BUTTON",
			"target": neutrophil,
			"action": "wait_exit",
			"button": "GOT IT",
			"enabled": true,
			"pause": true,
		},
		{
			"title": "LEVEL EXIT",
			"body": "Defeat every neutrophil to unlock the Level 1 exit, then reach it to finish the level. This tutorial will not complete the level for you.",
			"hint": "OBJECTIVE: DEFEAT ALL NEUTROPHILS, THEN REACH THE EXIT",
			"target": _level_exit,
			"action": "complete",
			"button": "GOT IT",
			"enabled": true,
			"pause": true,
		},
	]
	_begin_tutorial()


func _start_enemy_introduction(level_id: int) -> void:
	if not ENEMY_INTRODUCTIONS.has(level_id):
		return

	var introduction: Dictionary = ENEMY_INTRODUCTIONS[level_id]
	_player = get_tree().get_first_node_in_group("player") as Node2D
	var enemy := _nearest_group_node(String(introduction["group"]), _player)
	if not is_instance_valid(enemy):
		return

	_steps = [
		{
			"title": String(introduction["title"]),
			"body": String(introduction["body"]),
			"hint": "NEW ENEMY TYPE - KEEP MOVING AND USE YOUR EXISTING CONTROLS",
			"target": enemy,
			"action": "complete",
			"button": "GOT IT",
			"enabled": true,
			"pause": true,
		},
	]
	_begin_tutorial()


func _begin_tutorial() -> void:
	if _steps.is_empty():
		return

	_active = true
	_overlay = TUTORIAL_OVERLAY_SCRIPT.new() as TutorialOverlay
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.continue_requested.connect(_on_continue_requested)
	_overlay.skip_requested.connect(skip_tutorial)
	_hud.add_child(_overlay)
	_show_step(0)


func _show_step(index: int) -> void:
	if index < 0 or index >= _steps.size():
		_finish_tutorial()
		return

	_step_index = index
	var step: Dictionary = _steps[index]
	_current_action = String(step.get("action", "continue"))
	_continue_enabled = bool(step.get("enabled", true))
	_range_check_timer = 0.0
	_infection_prompt_in_range = false

	var target := step.get("target") as Node2D
	if _level_id == 1 and index == 3:
		target = _nearest_group_node("neutrophils", _player)
	var highlight_control := String(step.get("control", ""))
	var modal := bool(step.get("pause", false))
	_set_information_modal(modal)
	if is_instance_valid(_overlay):
		_overlay.present_step(
			step,
			target,
			_hud,
			_level_id,
			index + 1,
			_steps.size(),
			highlight_control
		)


func _process(delta: float) -> void:
	if not _active:
		return
	if _current_action == "await_exit":
		_range_check_timer -= delta
		if _range_check_timer > 0.0:
			return
		_range_check_timer = 0.25
		if (
			is_instance_valid(_level_exit)
			and bool(_level_exit.get("exit_locked")) == false
		):
			_show_step(_step_index + 1)
		return
	if _current_action != "infect":
		return
	_range_check_timer -= delta
	if _range_check_timer > 0.0:
		return
	_range_check_timer = 0.15
	_update_infection_prompt()


func _update_infection_prompt() -> void:
	if not is_instance_valid(_overlay):
		return

	var in_range: bool = (
		is_instance_valid(_player)
		and is_instance_valid(_host_cell)
		and _host_cell.has_method("can_player_enter")
		and _host_cell.can_player_enter(_player)
	)
	if in_range == _infection_prompt_in_range:
		return
	_infection_prompt_in_range = in_range
	if in_range:
		_overlay.set_body_text(
			"In range. Press E or use the highlighted INFECT button. "
			+ "Your virus hides while the host cell replicates for 8 seconds "
			+ "and releases 1-2 minions, then emerges. Infection is never automatic."
		)
		_overlay.set_hint_text("WINDOWS: E OR CLICK INFECT  |  ANDROID: TAP INFECT")
		_overlay.set_highlight_control("infect")
	else:
		_overlay.set_body_text(
			"Move close to the highlighted host cell. "
			+ "The infection action only works when you are in range."
		)
		_overlay.set_hint_text("MOVE CLOSER TO THE HIGHLIGHTED CELL")
		_overlay.set_highlight_control("")


func _on_continue_requested() -> void:
	if not _active or not _continue_enabled:
		return
	if _current_action == "complete":
		_finish_tutorial()
	elif _current_action == "continue":
		_show_step(_step_index + 1)
	elif _current_action == "wait_exit":
		_current_action = "await_exit"
		_range_check_timer = 0.0
		_set_information_modal(false)
		if is_instance_valid(_overlay):
			_overlay.present_waiting_for_exit(
				_level_id,
				_step_index + 1,
				_steps.size()
			)


func report_player_moved() -> void:
	if _active and _current_action == "move":
		_show_step(_step_index + 1)


func report_host_cell_infected(_cell: Node2D) -> void:
	if _active and _current_action == "infect":
		_show_step(_step_index + 1)


func is_local_gameplay_blocked() -> bool:
	return (
		_active
		and _information_modal_open
		and MultiplayerSession.is_session_active
	)


func is_tutorial_active() -> bool:
	return _active


func is_local_player_protected() -> bool:
	return is_local_gameplay_blocked()


func skip_tutorial() -> void:
	if _active:
		_finish_tutorial()


func _finish_tutorial() -> void:
	if not _active:
		return

	if not GameManager.mark_tutorial_completed(_level_id):
		push_error(
			"TutorialManager: Could not save completion for Level %d."
			% _level_id
		)
	_active = false
	_set_information_modal(false)
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_hud = null
	_host_cell = null
	_player = null
	_level_exit = null
	_steps.clear()
	_step_index = -1
	_current_action = ""


func _set_information_modal(open: bool) -> void:
	if _information_modal_open == open:
		return
	_information_modal_open = open

	if not MultiplayerSession.is_session_active:
		if open:
			_previous_tree_paused = get_tree().paused
			get_tree().paused = true
		else:
			get_tree().paused = _previous_tree_paused

	if is_instance_valid(_hud) and _hud.has_method("set_tutorial_input_suspended"):
		_hud.set_tutorial_input_suspended(open)


func _nearest_group_node(group_name: String, origin: Node2D) -> Node2D:
	var nearest: Node2D = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group(group_name):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		var candidate := node as Node2D
		var distance := (
			origin.global_position.distance_to(candidate.global_position)
			if is_instance_valid(origin)
			else 0.0
		)
		if distance < nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _on_scene_changed() -> void:
	if _active:
		_active = false
		_set_information_modal(false)
		if is_instance_valid(_overlay):
			_overlay.queue_free()
		_overlay = null
		_hud = null
		_host_cell = null
		_player = null
		_level_exit = null
		_steps.clear()
		_step_index = -1
		_current_action = ""
