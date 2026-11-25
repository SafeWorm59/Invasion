extends Node

signal settings_changed

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const PROGRESS_FILE_PATH: String = "user://progress.cfg"
const CONTROL_LAYOUT_FILE_PATH: String = "user://mobile_controls.cfg"
const LEVEL_SELECTION_SCENE_PATH: String = "res://scenes/level_selection.tscn"
const CONTROL_NAMES: Array[String] = ["joystick", "infect", "follow", "capture", "defend"]
const WASD_MOVEMENT_BINDINGS: Dictionary = {
	"ui_left": KEY_A,
	"ui_right": KEY_D,
	"ui_up": KEY_W,
	"ui_down": KEY_S,
}
const DEFAULT_CONTROL_LAYOUT: Dictionary = {
	"joystick": {"position": Vector2(0.10, 0.80), "scale": 1.0, "opacity": 0.78},
	"infect": {"position": Vector2(0.90, 0.80), "scale": 1.0, "opacity": 0.85},
	"follow": {"position": Vector2(0.72, 0.60), "scale": 1.0, "opacity": 0.88},
	"capture": {"position": Vector2(0.72, 0.76), "scale": 1.0, "opacity": 0.88},
	"defend": {"position": Vector2(0.72, 0.92), "scale": 1.0, "opacity": 0.88},
}
const DEFAULT_HIGHEST_UNLOCKED_LEVEL: int = 1
const MAX_LEVEL_ID: int = 5

var levels: Array[Dictionary] = [
	{"id": 1, "name": "NASAL PASSAGE", "subtitle": "ENTRY POINT", "description": "The first stage of the invasion, taking place inside the nasal passage. Penetrate the mucosal barrier and overwhelm the initial immune defenses.", "status": "AVAILABLE", "locked": false, "scene_path": "res://scenes/nasal_passage.tscn", "thumbnail_path": "res://assets/level_thumbnails/level1.png", "accent_color": Color(0.92, 0.35, 0.45, 1.0)},
	{"id": 2, "name": "PHARYNX", "subtitle": "RESPIRATORY JUNCTION", "description": "The invasion continues through the pharynx, introducing new anatomical regions and challenges. Defeat the dense concentration of defensive leukocytes.", "status": "AVAILABLE", "locked": false, "scene_path": "res://scenes/pharynx.tscn", "thumbnail_path": "res://assets/level_thumbnails/level2.png", "accent_color": Color(0.85, 0.28, 0.60, 1.0)},
	{"id": 3, "name": "LARYNX", "subtitle": "VOICE BOX", "description": "The invasion continues through the larynx, introducing dendritic cell immune surveillance and new anatomical challenges. Detect and respond to the advanced immune sentinel.", "status": "AVAILABLE", "locked": false, "scene_path": "res://scenes/level3.tscn", "thumbnail_path": "res://assets/level_thumbnails/level3.png", "accent_color": Color(0.90, 0.55, 0.20, 1.0)},
	{"id": 4, "name": "TRACHEA", "subtitle": "WINDPIPE", "description": "The invasion descends into the trachea, where NKT cells patrol the host cells, inspect them, and destroy any infected cell together with the minions it produced. Stay mobile and infect the airway before the surveillance catches up.", "status": "AVAILABLE", "locked": false, "scene_path": "res://scenes/level4.tscn", "thumbnail_path": "res://assets/level_thumbnails/level4.png", "accent_color": Color(0.62, 0.32, 0.85, 1.0)},
	{"id": 5, "name": "LUNGS", "subtitle": "PULMONARY AIRWAYS & ALVEOLI", "description": "The invasion reaches the left and right lungs. Infect every host cell across the branching airways while avoiding patrolling immune cells and ranged B-cell antibody attacks.", "status": "LOCKED", "locked": true, "scene_path": "res://scenes/level5.tscn", "thumbnail_path": "", "accent_color": Color(0.32, 0.72, 0.72, 1.0)}
]

var highest_unlocked_level: int = DEFAULT_HIGHEST_UNLOCKED_LEVEL
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 0.8
var is_fullscreen: bool = false
var mobile_controls_preview_on_desktop: bool = false
var mobile_control_layout: Dictionary = DEFAULT_CONTROL_LAYOUT.duplicate(true)
var _completion_dialog: AcceptDialog = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_wasd_movement_bindings()
	ensure_audio_buses()
	load_settings()
	load_mobile_control_layout()
	load_progress()


func ensure_wasd_movement_bindings() -> void:
	for action_value in WASD_MOVEMENT_BINDINGS:
		var action_name: String = str(action_value)
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(WASD_MOVEMENT_BINDINGS[action_name])
		if not InputMap.action_has_event(action_name, key_event):
			InputMap.action_add_event(action_name, key_event)


func get_mobile_control_layout() -> Dictionary:
	return mobile_control_layout.duplicate(true)


func save_mobile_control_layout(layout: Dictionary) -> bool:
	var validated := DEFAULT_CONTROL_LAYOUT.duplicate(true)
	for control_name in CONTROL_NAMES:
		var entry: Dictionary = layout.get(control_name, {})
		if entry.has("position") and entry["position"] is Vector2:
			entry = entry.duplicate(true)
			var normalized_position: Vector2 = entry["position"]
			entry["position"] = normalized_position.clamp(Vector2.ZERO, Vector2.ONE)
			entry["scale"] = clampf(float(entry.get("scale", 1.0)), 0.65, 1.5)
			entry["opacity"] = clampf(float(entry.get("opacity", 0.85)), 0.3, 1.0)
			validated[control_name] = entry
	var config := ConfigFile.new()
	config.set_value("controls", "layout", validated)
	var err := config.save(CONTROL_LAYOUT_FILE_PATH)
	if err != OK:
		push_error("GameManager: Failed to save mobile controls layout, error: %d" % err)
		return false
	mobile_control_layout = validated
	return true


func reset_mobile_control_layout() -> Dictionary:
	return DEFAULT_CONTROL_LAYOUT.duplicate(true)


func load_mobile_control_layout() -> void:
	var config := ConfigFile.new()
	if config.load(CONTROL_LAYOUT_FILE_PATH) != OK:
		mobile_control_layout = DEFAULT_CONTROL_LAYOUT.duplicate(true)
		return
	var saved: Variant = config.get_value("controls", "layout", {})
	if saved is Dictionary:
		mobile_control_layout = DEFAULT_CONTROL_LAYOUT.duplicate(true)
		for control_name in CONTROL_NAMES:
			var entry: Variant = saved.get(control_name, {})
			if entry is Dictionary and entry.get("position") is Vector2:
				var normalized_position: Vector2 = entry["position"]
				mobile_control_layout[control_name] = {
					"position": normalized_position.clamp(Vector2.ZERO, Vector2.ONE),
					"scale": clampf(float(entry.get("scale", 1.0)), 0.65, 1.5),
					"opacity": clampf(float(entry.get("opacity", 0.85)), 0.3, 1.0),
				}


func ensure_audio_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		var bus_idx := AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, "Music")
		AudioServer.set_bus_send(bus_idx, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		var bus_idx := AudioServer.bus_count
		AudioServer.add_bus(bus_idx)
		AudioServer.set_bus_name(bus_idx, "SFX")
		AudioServer.set_bus_send(bus_idx, "Master")


func get_levels() -> Array[Dictionary]:
	return levels


func get_level(id: int) -> Dictionary:
	for lvl in levels:
		if lvl.id == id:
			return lvl
	return {}


func is_level_available(id: int) -> bool:
	var lvl := get_level(id)
	return not lvl.is_empty() and not lvl.locked and lvl.scene_path != ""


func unlock_level(id: int) -> void:
	var found := false
	for lvl in levels:
		if int(lvl.get("id", 0)) == id:
			found = true
			break
	if not found:
		push_error("GameManager: Cannot unlock unknown level ID %d." % id)
		return

	highest_unlocked_level = clampi(
		maxi(highest_unlocked_level, id),
		DEFAULT_HIGHEST_UNLOCKED_LEVEL,
		MAX_LEVEL_ID
	)
	_apply_level_unlock_state()
	if not OS.is_debug_build():
		save_progress()


func _apply_level_unlock_state() -> void:
	for i in range(levels.size()):
		var level_id := int(levels[i].get("id", 0))
		var available := level_id <= highest_unlocked_level
		levels[i]["locked"] = not available
		levels[i]["status"] = "AVAILABLE" if available else "LOCKED"


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "highest_unlocked_level", highest_unlocked_level)
	var err := config.save(PROGRESS_FILE_PATH)
	if err != OK:
		push_error("GameManager: Failed to save progress to '%s', error: %d" % [PROGRESS_FILE_PATH, err])


func load_progress() -> void:
	if OS.is_debug_build():
		highest_unlocked_level = MAX_LEVEL_ID
		_apply_level_unlock_state()
		return

	var config := ConfigFile.new()
	var err := config.load(PROGRESS_FILE_PATH)
	if err == ERR_FILE_NOT_FOUND:
		_apply_level_unlock_state()
		return
	if err != OK:
		push_error("GameManager: Failed to load progress from '%s', error: %d" % [PROGRESS_FILE_PATH, err])
		_apply_level_unlock_state()
		return

	highest_unlocked_level = clampi(
		int(config.get_value("progress", "highest_unlocked_level", DEFAULT_HIGHEST_UNLOCKED_LEVEL)),
		DEFAULT_HIGHEST_UNLOCKED_LEVEL,
		MAX_LEVEL_ID
	)
	_apply_level_unlock_state()


func load_level(id: int) -> bool:
	var lvl := get_level(id)
	if lvl.is_empty():
		push_error("GameManager: Level ID %d not found in registry." % id)
		return false
	if lvl.locked or lvl.scene_path == "":
		print("GameManager: Level %d is locked or coming soon." % id)
		return false
	if not ResourceLoader.exists(lvl.scene_path):
		push_error("GameManager: Scene file '%s' does not exist." % lvl.scene_path)
		return false
	print("GameManager: Loading level %d: %s (%s)..." % [id, lvl.name, lvl.scene_path])
	var err := get_tree().change_scene_to_file(lvl.scene_path)
	if err != OK:
		push_error("GameManager: Failed to change scene to '%s', error: %d" % [lvl.scene_path, err])
		return false
	return true


func reload_current_level() -> bool:
	if MultiplayerSession.is_session_active:
		push_warning("GameManager: Individual multiplayer level restarts are disabled.")
		return false

	var current_scene := get_tree().current_scene
	if not is_instance_valid(current_scene):
		push_error("GameManager: Cannot restart because there is no current scene.")
		return false

	var current_scene_path: String = current_scene.scene_file_path
	for level in levels:
		if String(level.get("scene_path", "")) == current_scene_path:
			return load_level(int(level.get("id", 0)))

	push_error(
		"GameManager: Current scene '%s' is not a registered level."
		% current_scene_path
	)
	return false


func show_level_completion_dialog(level_id: int) -> void:
	if is_instance_valid(_completion_dialog):
		return

	var level := get_level(level_id)
	if level.is_empty():
		push_error("GameManager: Cannot show completion for unknown level ID %d." % level_id)
		return

	var is_multiplayer_session: bool = MultiplayerSession.is_session_active
	var level_name: String = str(level.get("name", "")).to_lower().capitalize()
	var dialog_title: String
	var dialog_message: String
	var primary_button_text: String
	var primary_action: StringName
	var secondary_button_text: String = "MAIN MENU"
	var secondary_action: StringName = &"main_menu"

	if is_multiplayer_session:
		dialog_title = "MULTIPLAYER PROGRESSION UNAVAILABLE"
		dialog_message = (
			"Level progression is not synchronized in multiplayer yet. "
			+ "Continue playing this match, or leave to the main menu."
		)
		primary_button_text = "CONTINUE MATCH"
		primary_action = &"continue_match"
		secondary_button_text = "LEAVE TO MAIN MENU"
		secondary_action = &"leave_to_main_menu"
	elif level_id == MAX_LEVEL_ID:
		dialog_title = "CONGRATULATIONS! YOU COMPLETED INVASION!"
		dialog_message = "You have completed all five levels of INVASION."
		primary_button_text = "REPLAY"
		primary_action = &"replay"
	else:
		var next_level_id: int = level_id + 1
		var next_level: Dictionary = get_level(next_level_id)
		if not next_level.is_empty():
			unlock_level(next_level_id)

		var next_level_name: String = str(next_level.get("name", "")).to_lower().capitalize()
		var next_scene_path: String = str(next_level.get("scene_path", ""))
		var next_scene_available: bool = (
			not next_level.is_empty()
			and not next_scene_path.is_empty()
			and ResourceLoader.exists(next_scene_path)
		)

		dialog_title = "LEVEL %d COMPLETED!" % level_id
		dialog_message = "Congratulations! You have completed the %s." % level_name
		if next_scene_available:
			dialog_message += "\n\nNext destination: %s." % next_level_name
			primary_button_text = "NEXT LEVEL"
			primary_action = &"next_level"
		else:
			var unavailable_level_name: String = (
				next_level_name if not next_level_name.is_empty() else "The next level"
			)
			dialog_message += (
				"\n\n%s is unavailable because its scene is missing. "
				+ "Use Level Selection to choose another available level."
			) % unavailable_level_name
			primary_button_text = "LEVEL SELECTION"
			primary_action = &"level_selection"

	var dialog := AcceptDialog.new()
	_completion_dialog = dialog
	dialog.title = dialog_title
	dialog.dialog_text = dialog_message
	dialog.get_ok_button().text = primary_button_text
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var dialog_width: int = mini(680, maxi(280, roundi(viewport_size.x * 0.88)))
	var dialog_height: int = mini(340, maxi(210, roundi(viewport_size.y * 0.44)))
	var button_width: float = maxf(110.0, (float(dialog_width) - 72.0) / 2.0)
	dialog.get_ok_button().custom_minimum_size = Vector2(button_width, 52.0)
	dialog.get_ok_button().add_theme_font_size_override(
		"font_size",
		clampi(roundi(viewport_size.y * 0.026), 14, 22)
	)
	var secondary_button: Button = dialog.add_button(
		secondary_button_text,
		true,
		String(secondary_action)
	)
	secondary_button.custom_minimum_size = Vector2(button_width, 52.0)
	secondary_button.add_theme_font_size_override(
		"font_size",
		clampi(roundi(viewport_size.y * 0.026), 14, 22)
	)
	dialog.confirmed.connect(
		_on_completion_dialog_confirmed.bind(dialog, primary_action, level_id)
	)
	dialog.custom_action.connect(
		_on_completion_dialog_custom_action.bind(dialog, secondary_action)
	)
	dialog.canceled.connect(_on_completion_dialog_canceled.bind(dialog))
	add_child(dialog)
	dialog.popup_centered(Vector2i(dialog_width, dialog_height))


func _on_completion_dialog_confirmed(
	dialog: AcceptDialog,
	action: StringName,
	level_id: int
) -> void:
	_release_completion_dialog(dialog)
	match action:
		&"next_level":
			if not load_level(level_id + 1):
				load_level_selection()
		&"level_selection":
			load_level_selection()
		&"replay":
			if not load_level(1):
				load_level_selection()
		&"continue_match":
			pass


func _on_completion_dialog_custom_action(
	action: StringName,
	dialog: AcceptDialog,
	secondary_action: StringName
) -> void:
	if action != secondary_action:
		return

	_release_completion_dialog(dialog)
	if action == &"main_menu" or action == &"leave_to_main_menu":
		if MultiplayerSession.is_session_active:
			MultiplayerSession.cancel_session()
		load_main_menu()


func _on_completion_dialog_canceled(dialog: AcceptDialog) -> void:
	_release_completion_dialog(dialog)


func _release_completion_dialog(dialog: AcceptDialog) -> void:
	if _completion_dialog == dialog:
		_completion_dialog = null
	dialog.queue_free()


func load_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func load_level_selection() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECTION_SCENE_PATH)


func set_master_volume(vol: float) -> void:
	master_volume = clampf(vol, 0.0, 1.0)
	apply_audio_settings()


func set_music_volume(vol: float) -> void:
	music_volume = clampf(vol, 0.0, 1.0)
	apply_audio_settings()


func set_sfx_volume(vol: float) -> void:
	sfx_volume = clampf(vol, 0.0, 1.0)
	apply_audio_settings()


func set_fullscreen_mode(enabled: bool) -> void:
	is_fullscreen = enabled
	apply_display_settings()


func apply_audio_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx != -1:
		AudioServer.set_bus_mute(master_idx, master_volume <= 0.001)
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(master_volume))
	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx != -1:
		AudioServer.set_bus_mute(music_idx, music_volume <= 0.001)
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_mute(sfx_idx, sfx_volume <= 0.001)
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))
	settings_changed.emit()


func apply_display_settings() -> void:
	if is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	settings_changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "fullscreen", is_fullscreen)
	config.set_value("display", "mobile_controls_preview_on_desktop", mobile_controls_preview_on_desktop)
	var err := config.save(SETTINGS_FILE_PATH)
	if err != OK:
		push_error("GameManager: Failed to save settings to '%s', error: %d" % [SETTINGS_FILE_PATH, err])
	else:
		print("GameManager: Settings saved successfully to '%s'." % SETTINGS_FILE_PATH)


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(SETTINGS_FILE_PATH)
	if err == OK:
		master_volume = config.get_value("audio", "master_volume", 1.0)
		music_volume = config.get_value("audio", "music_volume", 0.8)
		sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
		is_fullscreen = config.get_value("display", "fullscreen", false)
		mobile_controls_preview_on_desktop = config.get_value("display", "mobile_controls_preview_on_desktop", false)
		print("GameManager: Settings loaded from '%s'." % SETTINGS_FILE_PATH)
	else:
		print("GameManager: No existing settings file, using defaults.")
	apply_audio_settings()
	apply_display_settings()
