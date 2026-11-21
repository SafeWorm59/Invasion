extends Node

# Minimal game progress save/load system
# Saves: current level ID, defeated count, player health

const SAVE_FILE_PATH: String = "user://save_game.cfg"


func save_game(current_level_id: int, defeated_count: int, player_health: float) -> void:
	var config := ConfigFile.new()
	config.set_value("game", "current_level_id", current_level_id)
	config.set_value("game", "defeated_count", defeated_count)
	config.set_value("game", "player_health", player_health)
	var err := config.save(SAVE_FILE_PATH)
	if err != OK:
		print("SaveManager: Failed to save game, error: %d" % err)
	else:
		print("SaveManager: Game saved successfully to '%s'." % SAVE_FILE_PATH)


func load_game() -> void:
	var config := ConfigFile.new()
	var err := config.load(SAVE_FILE_PATH)
	if err == OK:
		print("SaveManager: Game loaded from '%s'." % SAVE_FILE_PATH)
	else:
		print("SaveManager: No saved game found, starting new.")