extends Node2D

const Map := preload("res://scenes/larynx_map.gd")
const LevelGameplay := preload("res://scenes/larynx_level.gd")

# Pharynx-style Level 3 (Larynx) environment: frames the anatomical camera,
# reports region/chamber transitions, spawns the gameplay layer, and provides
# the minimap outline for the shared HUD.

const CAMERA_MARGIN := 200.0

var _player: Node2D = null
var _region: int = -1
var _chamber: int = -1


func _ready() -> void:
	add_to_group("level_manager")
	_player = get_node_or_null("Player") as Node2D
	if _player != null:
		_player.global_position = Map.spawn_point()
	_configure_camera()
	_configure_hud()
	print(
		"[Larynx] Level 3 ready - %d chambers, %d passages, %d folds, %.0f px main route (%.1f s)."
		% [
			Map.chamber_count(), Map.corridor_count(), Map.barrier_count(),
			Map.route_length(), Map.route_seconds(),
		]
	)
	if _player != null:
		_report(_player.global_position)

	var gameplay := LevelGameplay.new()
	gameplay.name = "LevelGameplay"
	add_child(gameplay)


func _configure_camera() -> void:
	var cam := get_node_or_null("Player/Camera2D") as Camera2D
	if cam == null:
		push_warning("[Larynx] Player camera not found; keeping defaults.")
		return
	var box := Map.bounds()
	cam.limit_left = int(box.position.x - CAMERA_MARGIN)
	cam.limit_right = int(box.end.x + CAMERA_MARGIN)
	cam.limit_top = int(box.position.y - CAMERA_MARGIN)
	cam.limit_bottom = int(box.end.y + CAMERA_MARGIN)
	cam.reset_smoothing()


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


func _report(p: Vector2) -> void:
	var region := Map.region_at(p)
	if region != _region:
		_region = region
		print("[Larynx] Entered region: ", Map.region_name(region))
	var chamber := Map.nearest_chamber(p)
	if chamber != _chamber:
		_chamber = chamber
		print(
			"[Larynx] Entered chamber: ", Map.chamber_name(chamber),
			" (", Map.region_name(Map.chamber_region(chamber)), ")"
		)


# --------------------------------------------------------------------------
# Minimap provider (duck-typed: the shared minimap reads these two)
# --------------------------------------------------------------------------

func minimap_bounds() -> Rect2:
	return Map.bounds()


func minimap_outline() -> Array:
	var polys: Array = []
	for i in range(Map.chamber_count()):
		var c := Map.chamber_center(i)
		var r := Map.chamber_radii(i)
		polys.append(_ellipse(c, r.x, r.y, 64))
	for i in range(Map.corridor_count()):
		polys.append(_capsule(Map.corridor_a(i), Map.corridor_b(i), Map.corridor_width(i)))
	return polys


func _ellipse(c: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _capsule(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var dir := b - a
	if dir.length() < 0.0001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var n := Vector2(-dir.y, dir.x)
	var cap := 16
	pts.append(a + n * w)
	for i in range(cap + 1):
		var t := PI * float(i) / float(cap)
		pts.append(b + (n * cos(t) + dir * sin(t)) * w)
	for i in range(cap + 1):
		var t := PI * float(i) / float(cap)
		pts.append(a - (n * cos(t) + dir * sin(t)) * w)
	pts.remove_at(pts.size() - 1)
	return pts


# --------------------------------------------------------------------------
# Save confirmation dialog (same pattern as Levels 1 and 2)
# --------------------------------------------------------------------------
const SAVE_CONFIRMATION_SCENE: String = "res://scenes/save_confirmation.tscn"

static var _dialog_instance: Control = null
static var _is_showing: bool = false


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
	_close_dialog()
	print("Game: Saving progress before returning to main menu")
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