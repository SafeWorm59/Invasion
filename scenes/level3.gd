extends Node2D

var total_host_cells: int = 0
var infected_host_cells: int = 0
var total_neutrophils: int = 0
var defeated_neutrophils: int = 0
var total_macrophages: int = 0
var defeated_macrophages: int = 0
var total_dendritic_cells: int = 0
var defeated_dendritic_cells: int = 0
var level_exit: Area2D = null
var hud: Node = null
var exit_locked: bool = true

func _ready() -> void:
	add_to_group("level_manager")

	# Find or create LevelExit
	level_exit = get_node_or_null("LevelExit") as Area2D
	if not is_instance_valid(level_exit):
		# Create LevelExit programmatically
		level_exit = Area2D.new()
		level_exit.name = "LevelExit"
		level_exit.position = Vector2(800, 1000)
		level_exit.scale = Vector2(2.0, 2.0)
		add_child(level_exit)

	exit_locked = true
	_update_exit_visual()

	# Initialize counts from spawned entities
	initialize_entity_counts()

	# Get HUD reference
	var hud_node = get_node_or_null("HUD")
	if is_instance_valid(hud_node):
		hud = hud_node
	else:
		hud = Node.new()
		add_child(hud_node)

	# Update objective display
	update_objective_display()

	print("Level 3 objective: Infect all host cells throughout the larynx.")

	# Connect defeat signals
	connect_defeat_signals()

	if total_host_cells == 0:
		unlock_exit()


func set_exit_locked(locked: bool) -> void:
	exit_locked = locked
	_update_exit_visual()


func _update_exit_visual() -> void:
	# Simple visual update for exit lock state
	if exit_locked:
		print("Exit is locked. Infect all host cells to unlock.")
	pass


func initialize_entity_counts() -> void:
	"""Count all entities in the scene."""
	# Count host cells
	var host_cells := get_tree().get_nodes_in_group("host_cells")
	total_host_cells = host_cells.size()

	# Count neutrophils
	var neutrophils := get_tree().get_nodes_in_group("neutrophils")
	total_neutrophils = neutrophils.size()

	# Count macrophages
	var macrophages := get_tree().get_nodes_in_group("macrophages")
	total_macrophages = macrophages.size()

	# Count dendritic cells
	var dendritic_cells := get_tree().get_nodes_in_group("dendritic_cells")
	total_dendritic_cells = dendritic_cells.size()

	print("Level 3 entity counts: %d host cells, %d neutrophils, %d macrophages, %d dendritic cells" % [
		total_host_cells, total_neutrophils, total_macrophages, total_dendritic_cells
	])


func connect_defeat_signals() -> void:
	"""Connect defeat signals from all immune cells."""
	# Neutrophil defeated signals
	var neutrophils := get_tree().get_nodes_in_group("neutrophils")
	for neuron in neutrophils:
		if neuron.has_signal("defeated_signal"):
			neuron.defeated_signal.connect(_on_neutrophil_defeated)

	# Macrophage defeated signals
	var macrophages := get_tree().get_nodes_in_group("macrophages")
	for macro in macrophages:
		if macro.has_signal("defeated_signal"):
			macro.defeated_signal.connect(_on_macrophage_defeated)

	# Dendritic cell defeated signals
	var dendritic_cells := get_tree().get_nodes_in_group("dendritic_cells")
	for dc in dendritic_cells:
		if dc.has_signal("defeated_signal"):
			dc.defeated_signal.connect(_on_dendritic_cell_defeated)


func _on_neutrophil_defeated() -> void:
	defeated_neutrophils += 1
	update_objective_display()

	if defeated_neutrophils >= total_neutrophils:
		print("Neutrophils all defeated!")

	# Check if exit can be unlocked (based on host cell infection, not neutrophil count)
	check_exit_unlock()


func _on_macrophage_defeated() -> void:
	defeated_macrophages += 1
	update_objective_display()


func _on_dendritic_cell_defeated() -> void:
	defeated_dendritic_cells += 1
	update_objective_display()


func check_exit_unlock() -> void:
	"""Check if exit should be unlocked based on host cell infection."""
	if infected_host_cells >= total_host_cells:
		unlock_exit()
		print("Exit unlocked: all host cells infected!")


func unlock_exit() -> void:
	exit_locked = false
	_update_exit_visual()
	update_objective_display()
	print("Exit unlocked! Reach the exit to complete the level.")


func update_objective_display() -> void:
	if is_instance_valid(hud) and hud.has_method("update_level_objective"):
		hud.update_level_objective(
			infected_host_cells,
			total_host_cells,
			"HOST CELLS"
		)


# Minimap provider - Level 3 (larynx)
func minimap_bounds() -> Rect2:
	# Try to find a Floor or similar polygon for bounds
	var floor_node := get_node_or_null("Floor") as Polygon2D

	if floor_node == null or floor_node.polygon.size() < 3:
		# Fallback: use a reasonable rectangle for larynx anatomy
		return Rect2(-1500.0, -3000.0, 4000.0, 3500.0)

	return _points_bounds(_world_points_floor(floor_node))


func minimap_outline() -> Array:
	var polys: Array = []
	var floor_node := get_node_or_null("Floor") as Polygon2D

	if floor_node != null and floor_node.polygon.size() >= 3:
		polys.append(_world_points_floor(floor_node))

	# Add anatomical outline polygons for larynx structures
	add_larynx_outline_polys(polys)

	return polys


func _world_points_floor(poly: Polygon2D) -> PackedVector2Array:
	var out := PackedVector2Array()

	for p in poly.polygon:
		out.append(p)

	return out


func add_larynx_outline_polys(polys: Array) -> void:
	"""Add larynx-specific anatomical outline polygons."""
	# Add a basic larynx-shaped outline
	var points := PackedVector2Array()

	# Create an outline representing the larynx region
	# Epiglottis at top, vocal folds in middle, trachea exit at bottom
	var center_x: float = 0.0
	var center_y: float = 0.0
	var radius: float = 1200.0

	# Divide into segments for larynx shape
	var segments: int = 32
	for i in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		# Larynx: narrower at vocal folds region, wider at epiglottis and trachea
		var segment_ratio: float = float(i) / float(segments)
		# Make it larynx-shaped: wider at top (epiglottis) and bottom (trachea),
		# narrower in middle (vocal folds)
		var effective_radius: float = radius
		if segment_ratio > 0.4 and segment_ratio < 0.6:
			# Vocal folds region - narrower
			effective_radius *= 0.6
		elif segment_ratio < 0.3:
			# Epiglottis region - wider
			effective_radius *= 1.1
		else:
			# Trachea region - wider
			effective_radius *= 1.05

		var x: float = center_x + sin(angle) * effective_radius
		var y: float = center_y - cos(angle) * effective_radius
		points.append(Vector2(x, y))

	if points.size() >= 3:
		polys.append(points)


func _points_bounds(points: PackedVector2Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)

	for p in points:
		mn = mn.min(p)
		mx = mx.max(p)

	return Rect2(mn, mx - mn)


# --------------------------------------------------------------------------
# Save confirmation dialog handling (same pattern as Level 1)
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