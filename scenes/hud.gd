
extends CanvasLayer

const Minimap := preload("res://scenes/minimap.gd")

@onready var follow_button: Button = $CommandButtons/VBoxContainer/FollowButton
@onready var capture_button: Button = $CommandButtons/VBoxContainer/CaptureButton
@onready var defend_button: Button = $CommandButtons/VBoxContainer/DefendButton
@onready var health_label: Label = $HealthPanel/HealthLayout/HealthLabel
@onready var health_bar: ProgressBar = $HealthPanel/HealthLayout/HealthBar

var objective_panel: PanelContainer
var objective_label: Label
var objective_bar: ProgressBar
var objective_status: Label

var join_attack_button: Button
var nearby_target: Node2D = null

var objective_name: String = "HOST CELLS"

var notification_box: VBoxContainer
var _notification_cooldowns: Dictionary = {}


func _ready() -> void:
	add_to_group("hud")

	follow_button.pressed.connect(_on_follow_button_pressed)
	capture_button.pressed.connect(_on_capture_button_pressed)
	defend_button.pressed.connect(_on_defend_button_pressed)

	update_player_health(100, 100)
	create_objective_display()
	create_notification_display()

	# Reusable level minimap, pinned to the top-right corner.
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	add_child(minimap)

	# Create the Join Attack button dynamically.
	join_attack_button = Button.new()
	join_attack_button.name = "JoinAttackButton"
	join_attack_button.text = "JOIN ATTACK"
	join_attack_button.custom_minimum_size = Vector2(180, 60)
	join_attack_button.position = Vector2(20, 100)
	join_attack_button.visible = false
	add_child(join_attack_button)

	join_attack_button.pressed.connect(_on_join_attack_pressed)


var _join_attack_check_timer: float = 0.0

func _process(delta: float) -> void:
	_join_attack_check_timer -= delta
	if _join_attack_check_timer <= 0.0:
		_join_attack_check_timer = 0.1
		update_join_attack_button()


func update_player_health(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current

	health_label.text = "VIRUS HEALTH: %d / %d" % [
		current,
		maximum
	]


# FOLLOW COMMAND
func _on_follow_button_pressed() -> void:
	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(0)

	print("Follow command issued to %d minions." % minions.size())


# CAPTURE COMMAND
func _on_capture_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		print("Cannot capture: Player not found.")
		return

	var selected_target: Node2D = null
	var nearest_distance: float = INF

	# Select one Neutrophil nearest to the player.
	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node) or not node is Node2D:
			continue

		if node.get("defeated") == true:
			continue

		var distance := player.global_position.distance_to(
			node.global_position
		)

		if distance < nearest_distance:
			nearest_distance = distance
			selected_target = node as Node2D

	if not is_instance_valid(selected_target):
		print("No available Neutrophils to capture.")
		return

	var minions := get_tree().get_nodes_in_group("minions")
	var assigned_count: int = 0

	# Assign the exact same target to every minion.
	for minion in minions:
		if not is_instance_valid(minion):
			continue

		if minion.has_method("set_capture_target"):
			minion.set_capture_target(selected_target)
			assigned_count += 1

	print(
		"Capture command: %d minions assigned to one Neutrophil."
		% assigned_count
	)


# DEFEND COMMAND
func _on_defend_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		return

	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(2, player.global_position)

	print("Defend command issued to %d minions." % minions.size())


# JOIN ATTACK BUTTON
func update_join_attack_button() -> void:
	nearby_target = null

	if not is_instance_valid(join_attack_button):
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player) or not player.visible:
		join_attack_button.visible = false
		return

	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node):
			continue

		if not node.has_method("can_player_join"):
			continue

		if node.can_player_join():
			nearby_target = node
			break

	join_attack_button.visible = is_instance_valid(nearby_target)

	if not is_instance_valid(nearby_target):
		return

	if nearby_target.get("player_assisting") == true:
		join_attack_button.text = "ATTACKING!"
		join_attack_button.disabled = true
	else:
		join_attack_button.text = "JOIN ATTACK"
		join_attack_button.disabled = false


func _on_join_attack_pressed() -> void:
	if not is_instance_valid(nearby_target):
		return

	if nearby_target.has_method("set_player_assisting"):
		nearby_target.set_player_assisting(true)

	update_join_attack_button()


# OBJECTIVE DISPLAY
func create_objective_display() -> void:
	objective_panel = PanelContainer.new()
	objective_panel.name = "ObjectivePanel"

	objective_panel.anchor_left = 0.5
	objective_panel.anchor_right = 0.5
	objective_panel.anchor_top = 0.0
	objective_panel.anchor_bottom = 0.0

	objective_panel.offset_left = -180
	objective_panel.offset_right = 180
	objective_panel.offset_top = 20
	objective_panel.offset_bottom = 115

	add_child(objective_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 5)
	objective_panel.add_child(layout)

	objective_label = Label.new()
	objective_label.text = "MISSION OBJECTIVE"
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(objective_label)

	objective_bar = ProgressBar.new()
	objective_bar.min_value = 0
	objective_bar.max_value = 1
	objective_bar.value = 0
	objective_bar.show_percentage = false
	objective_bar.custom_minimum_size = Vector2(320, 14)
	layout.add_child(objective_bar)

	objective_status = Label.new()
	objective_status.text = "Exit locked: eliminate all " + objective_name + "."
	objective_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(objective_status)


# General objective display: an explicit title line, a status line, and a
# progress bar. Lets a level drive a multi-stage objective (see Level 2).
func set_objective(title: String, status: String, current: int, total: int) -> void:
	if not is_instance_valid(objective_panel):
		return

	objective_bar.max_value = maxi(total, 1)
	objective_bar.value = current
	objective_label.text = title
	objective_status.text = status


func update_level_objective(defeated_count: int, total_count: int, custom_name: String = "NEUTROPHILS") -> void:
	var title := "%s: %d / %d" % [custom_name, defeated_count, total_count]

	if defeated_count >= total_count:
		set_objective(title, "EXIT UNLOCKED! Reach the exit.", defeated_count, total_count)
	else:
		set_objective(title, "Exit locked: eliminate all " + custom_name + ".", defeated_count, total_count)


# --------------------------------------------------------------------------
# Brief gameplay notifications (Level 4 NKT feedback)
# --------------------------------------------------------------------------

func create_notification_display() -> void:
	notification_box = VBoxContainer.new()
	notification_box.name = "Notifications"
	notification_box.anchor_left = 0.5
	notification_box.anchor_right = 0.5
	notification_box.anchor_top = 1.0
	notification_box.anchor_bottom = 1.0
	notification_box.offset_left = -280.0
	notification_box.offset_right = 280.0
	notification_box.offset_top = -176.0
	notification_box.offset_bottom = -96.0
	notification_box.alignment = BoxContainer.ALIGNMENT_END
	notification_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_box.add_theme_constant_override("separation", 2)
	add_child(notification_box)


## Short, throttled message near the bottom of the screen. Reusing the same
## text within a few seconds is dropped so several NKT cells cannot spam it.
func show_notification(text: String, color: Color = Color(1.0, 0.85, 0.45)) -> void:
	if not is_instance_valid(notification_box):
		create_notification_display()

	if not is_instance_valid(notification_box):
		return

	var now := float(Time.get_ticks_msec()) / 1000.0
	if _notification_cooldowns.has(text):
		if now - float(_notification_cooldowns[text]) < 3.0:
			return
	_notification_cooldowns[text] = now

	# Keep at most four messages alive at once.
	while notification_box.get_child_count() >= 4:
		var oldest := notification_box.get_child(0)
		notification_box.remove_child(oldest)
		oldest.queue_free()

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_box.add_child(label)

	var tween := create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)
