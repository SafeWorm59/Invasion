extends Node

signal settings_changed

const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const PROGRESS_FILE_PATH: String = "user://progress.cfg"
const DEFAULT_HIGHEST_UNLOCKED_LEVEL: int = 4
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_audio_buses()
	load_settings()
	load_progress()


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


func load_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func load_level_selection() -> void:
	get_tree().change_scene_to_file("res://scenes/level_selection.tscn")


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
		print("GameManager: Settings loaded from '%s'." % SETTINGS_FILE_PATH)
	else:
		print("GameManager: No existing settings file, using defaults.")
	apply_audio_settings()
	apply_display_settings()
