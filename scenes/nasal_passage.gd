
extends Node2D

var total_neutrophils: int = 0
var defeated_neutrophils: int = 0
var hud: Node = null

@onready var level_exit: Area2D = $LevelExit


func _ready() -> void:
	add_to_group("level_manager")

	level_exit.set_exit_locked(true)

	var neutrophils := get_tree().get_nodes_in_group("immune_cells")

	total_neutrophils = neutrophils.size()
	
	hud = get_tree().get_first_node_in_group("hud")

	update_objective_display()

	print("Level objective: Defeat ", total_neutrophils, " Neutrophils.")

	for neutrophil in neutrophils:
		if neutrophil.has_signal("defeated_signal"):
			neutrophil.defeated_signal.connect(_on_neutrophil_defeated)

	if total_neutrophils == 0:
		unlock_exit()


func _on_neutrophil_defeated() -> void:
	defeated_neutrophils += 1
	update_objective_display()

	print(
        "Neutrophils defeated: %d / %d"
		% [defeated_neutrophils, total_neutrophils]
	)

	if defeated_neutrophils >= total_neutrophils:
		unlock_exit()


func unlock_exit() -> void:
	level_exit.set_exit_locked(false)
	update_objective_display()
	print("All Neutrophils defeated! Exit unlocked.")

func update_objective_display() -> void:
	if is_instance_valid(hud) and hud.has_method("update_level_objective"):
		hud.update_level_objective(
			defeated_neutrophils,
			total_neutrophils
		)
