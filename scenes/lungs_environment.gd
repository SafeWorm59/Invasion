extends Node2D

const Map := preload("res://scenes/lungs_map.gd")
const LevelGameplay := preload("res://scenes/lungs_level.gd")
const CAMERA_MARGIN := 220.0
const CAP_SEGMENTS := 16
const SAVE_CONFIRMATION_SCENE := "res://scenes/save_confirmation.tscn"

var _player: Node2D = null
var _region: int = -1
var _chamber: int = -1

static var _dialog_instance: Control = null
static var _is_showing: bool = false


func _ready() -> void:
	add_to_group("level_manager")
	_player = get_node_or_null("Player") as Node2D
	if _player != null:
		_player.global_position = Map.spawn_point()
	_configure_camera()
	_configure_hud()
	print(
		"[Lungs] Level 5 ready - %d chambers, %d passages, %.0f px route (%.1f s)."
		% [Map.chamber_count(), Map.corridor_count(), Map.route_length(), Map.route_seconds()]
	)
	if _player != null:
		_report(_player.global_position)

	var gameplay := LevelGameplay.new()
	gameplay.name = "LevelGameplay"
	add_child(gameplay)


func _configure_camera() -> void:
	var camera := get_node_or_null("Player/Camera2D") as Camera2D
	if camera == null:
		push_warning("[Lungs] Player camera not found; keeping defaults.")
		return
	var box := Map.bounds()
	camera.limit_left = int(box.position.x - CAMERA_MARGIN)
	camera.limit_right = int(box.end.x + CAMERA_MARGIN)
	camera.limit_top = int(box.position.y - CAMERA_MARGIN)
	camera.limit_bottom = int(box.end.y + CAMERA_MARGIN)
	camera.reset_smoothing()


func _configure_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var panel: Variant = hud.get("objective_panel")
	if panel is Control:
		(panel as Control).visible = true


func _process(_delta: float) -> void:
	if _player == null:
		_player = get_node_or_null("Player") as Node2D
		if _player == null:
			return
	_report(_player.global_position)


func _report(point: Vector2) -> void:
	var region := Map.region_at(point)
	if region != _region:
		_region = region
		print("[Lungs] Entered region: ", Map.region_name(region))
	var chamber := Map.nearest_chamber(point)
	if chamber != _chamber:
		_chamber = chamber
		print("[Lungs] Entered chamber: ", Map.chamber_name(chamber))


func minimap_bounds() -> Rect2:
	return Map.bounds()


func minimap_outline() -> Array:
	var polygons: Array = []
	for i in range(Map.chamber_count()):
		var center := Map.chamber_center(i)
		var radii := Map.chamber_radii(i)
		polygons.append(_ellipse(center, radii.x, radii.y, 64))
	for i in range(Map.corridor_count()):
		polygons.append(_capsule(Map.corridor_a(i), Map.corridor_b(i), Map.corridor_width(i)))
	return polygons


func _ellipse(center: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	return points


func _capsule(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var direction := b - a
	if direction.length() < 0.0001:
		direction = Vector2.DOWN
	direction = direction.normalized()
	var normal := Vector2(-direction.y, direction.x)
	points.append(a + normal * width)
	for i in range(CAP_SEGMENTS + 1):
		var angle := PI * float(i) / float(CAP_SEGMENTS)
		points.append(b + (normal * cos(angle) + direction * sin(angle)) * width)
	for i in range(CAP_SEGMENTS + 1):
		var angle := PI * float(i) / float(CAP_SEGMENTS)
		points.append(a - (normal * cos(angle) + direction * sin(angle)) * width)
	points.remove_at(points.size() - 1)
	return points


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _is_showing:
		open_save_confirmation()


func open_save_confirmation() -> void:
	if _is_showing or _dialog_instance != null:
		return
	_is_showing = true
	_dialog_instance = preload(SAVE_CONFIRMATION_SCENE).instantiate()
	add_child(_dialog_instance)
	_dialog_instance.save_exit_btn.pressed.connect(_on_save_exit_pressed)
	_dialog_instance.exit_without_save_btn.pressed.connect(_on_exit_without_save_pressed)
	_dialog_instance.cancel_btn.pressed.connect(_on_cancel_pressed)


func _on_save_exit_pressed() -> void:
	_close_dialog()
	print("Game: Returning to the main menu.")
	transition_to_main_menu()


func _on_exit_without_save_pressed() -> void:
	_close_dialog()
	transition_to_main_menu()


func _on_cancel_pressed() -> void:
	_close_dialog()


func _close_dialog() -> void:
	_is_showing = false
	if is_instance_valid(_dialog_instance):
		remove_child(_dialog_instance)
		_dialog_instance.free()
	_dialog_instance = null


func transition_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
