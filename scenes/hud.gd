
extends CanvasLayer

@onready var follow_button: Button = $CommandButtons/FollowButton
@onready var capture_button: Button = $CommandButtons/CaptureButton
@onready var defend_button: Button = $CommandButtons/DefendButton

var join_attack_button: Button
var nearby_target: Node2D = null


func _ready() -> void:
	follow_button.pressed.connect(_on_follow_button_pressed)
	capture_button.pressed.connect(_on_capture_button_pressed)
	defend_button.pressed.connect(_on_defend_button_pressed)

	join_attack_button = Button.new()
	join_attack_button.name = "JoinAttackButton"
	join_attack_button.text = "JOIN ATTACK"
	join_attack_button.custom_minimum_size = Vector2(180, 60)
	join_attack_button.position = Vector2(20, 100)
	join_attack_button.visible = false
	add_child(join_attack_button)

	join_attack_button.pressed.connect(_on_join_attack_pressed)


func _process(_delta: float) -> void:
	update_join_attack_button()


func _on_follow_button_pressed() -> void:
	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(0)

	print("Follow command issued to %d minions." % minions.size())


func _on_capture_button_pressed() -> void:
	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(1)

	print("Capture / Stun command issued to %d minions." % minions.size())


func _on_defend_button_pressed() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D

	if not is_instance_valid(player):
		return

	var minions := get_tree().get_nodes_in_group("minions")

	for minion in minions:
		if is_instance_valid(minion) and minion.has_method("set_command"):
			minion.set_command(2, player.global_position)

	print("Defend command issued to %d minions." % minions.size())


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
