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

	for neuron in neutrophils:
		if neuron.has_signal("defeated_signal"):
			neuron.defeated_signal.connect(_on_neutrophil_defeated)

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


# --------------------------------------------------------------------------
# Minimap provider
# --------------------------------------------------------------------------

func minimap_bounds() -> Rect2:
	var floor_node := get_node_or_null("Floor") as Polygon2D

	if floor_node == null or floor_node.polygon.size() < 3:
		return Rect2(-1200.0, -3200.0, 3100.0, 4500.0)

	return _points_bounds(_world_points(floor_node))


func minimap_outline() -> Array:
	var polys: Array = []
	var floor_node := get_node_or_null("Floor") as Polygon2D

	if floor_node != null and floor_node.polygon.size() >= 3:
		polys.append(_world_points(floor_node))

	return polys


func _world_points(poly: Polygon2D) -> PackedVector2Array:
	var out := PackedVector2Array()

	for p in poly.polygon:
		out.append(poly.global_transform * p)

	return out


func _points_bounds(points: PackedVector2Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)

	for p in points:
		mn = mn.min(p)
		mx = mx.max(p)

	return Rect2(mn, mx - mn)


# --------------------------------------------------------------------------
# Save confirmation dialog handling
# --------------------------------------------------------------------------
const SAVE_CONFIRMATION_SCENE: String = "res://scenes/save_confirmation.tscn"

static var _dialog_instance: Control = null
static var _is_showing: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not _is_showing:
			open_save_confirmation()

func open_save_confirmation() -> void:
	if _is_showing or _dialog_instance != null:
		return
	_is_showing = true
	_dialog_instance = preload(SAVE_CONFIRMATION_SCENE).instantiate()
	add_child(_dialog_instance)
	# Connect to dialog buttons - use the button names from the scene
	var sd: Control = _dialog_instance
	sd.save_exit_btn.pressed.connect(_on_save_exit_pressed)
	sd.exit_without_save_btn.pressed.connect(_on_exit_without_save_pressed)
	sd.cancel_btn.pressed.connect(_on_cancel_pressed)

func _on_save_exit_pressed() -> void:
	_is_showing = false
	remove_child(_dialog_instance)
	_dialog_instance.free()
	_dialog_instance = null
	print("Game: Saving progress before returning to main menu")
	# TODO: Implement actual save using ConfigFile
	transition_to_main_menu()

func _on_exit_without_save_pressed() -> void:
	_is_showing = false
	remove_child(_dialog_instance)
	_dialog_instance.free()
	_dialog_instance = null
	transition_to_main_menu()

func _on_cancel_pressed() -> void:
	_is_showing = false
	remove_child(_dialog_instance)
	_dialog_instance.free()
	_dialog_instance = null
	pass

func transition_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
