extends CharacterBody2D

const SPEED: float = 200.0
const SPIKE_COUNT: int = 12
const DEATH_ANIMATION_DURATION: float = 0.4

const CELL_TRANSITION_DURATION: float = 0.35

var is_transitioning: bool = false
var transition_timer: float = 0.0
var transition_type: String = ""
var transition_start_position: Vector2 = Vector2.ZERO
var transition_end_position: Vector2 = Vector2.ZERO

var max_health: int = 100
var health: int = 100

var inside_cell: bool = false
var host_cell: Node2D = null

var is_dead: bool = false
var death_timer: float = 0.0
var death_fragment_angles: Array[float] = []
var death_fragment_distances: Array[float] = []

# Team attack animation.
var team_attack_target: Node2D = null
var team_attack_timer: float = 0.0
var team_attack_animation_timer: float = 0.0
var is_team_attacking: bool = false
var team_attack_direction: Vector2 = Vector2.RIGHT

const TEAM_ATTACK_INTERVAL: float = 0.7
const TEAM_ATTACK_ANIMATION_DURATION: float = 0.25
const TEAM_ATTACK_DAMAGE: int = 10
const TEAM_ATTACK_LUNGE_DISTANCE: float = 12.0

@onready var health_label: Label = get_node_or_null(
	"/root/Main/HUD/HealthLabel"
)


func _ready() -> void:
	add_to_group("player")
	update_health_label()


func _process(delta: float) -> void:
	if is_dead:
		death_timer += delta
		queue_redraw()

		if death_timer >= DEATH_ANIMATION_DURATION:
			visible = false
			show_game_over()

		return
		
	if is_transitioning:
		transition_timer += delta

		var progress: float = clampf(
			transition_timer / CELL_TRANSITION_DURATION,
			0.0,
			1.0
		)

		if transition_type == "enter":
			scale = Vector2.ONE * (1.0 - progress)
			modulate.a = 1.0 - progress
		elif transition_type == "exit":
			scale = Vector2.ONE * progress
			modulate.a = progress

		global_position = transition_start_position.lerp(
			transition_end_position,
			progress
		)

		queue_redraw()

		if progress >= 1.0:
			finish_cell_transition()

		return

	if is_team_attacking:
		team_attack_animation_timer += delta

		if team_attack_animation_timer >= TEAM_ATTACK_ANIMATION_DURATION:
			is_team_attacking = false
			team_attack_animation_timer = 0.0

		queue_redraw()


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return

	if inside_cell:
		velocity = Vector2.ZERO

		if Input.is_action_just_pressed("interact"):
			if is_instance_valid(host_cell):
				var exit_position: Vector2 = get_cell_exit_position(
					host_cell
				)

				start_cell_transition(
					"exit",
					global_position,
					exit_position
				)

		return

	var direction := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	# If the player has joined a team attack, move toward their
	# assigned circle position when no movement key is pressed.
	team_attack_target = find_player_assisted_target()

	if is_instance_valid(team_attack_target):
		if direction.length() > 0.1:
			# Manual movement always takes priority.
			velocity = direction * SPEED
		else:
			var slot_position: Vector2 = (
				team_attack_target.get_player_slot_position()
			)
			var distance_to_slot := global_position.distance_to(slot_position)

			if distance_to_slot > 5.0:
				velocity = global_position.direction_to(slot_position) * SPEED
			else:
				velocity = Vector2.ZERO

		update_team_attack(delta)
	else:
		velocity = direction * SPEED
		is_team_attacking = false
		team_attack_timer = 0.0

	move_and_slide()

	if Input.is_action_just_pressed("interact"):
		var cells = get_tree().get_nodes_in_group("host_cells")

		for cell in cells:
			if cell.has_method("try_enter") and cell.try_enter(self):
				inside_cell = true
				host_cell = cell

				start_cell_transition(
					"enter",
					global_position,
					cell.global_position
				)

				if cell.has_signal("replication_completed"):
					var callback := Callable(
						self,
						"_on_host_cell_replication_completed"
					)

					if not cell.is_connected(
						"replication_completed",
						callback
					):
						cell.connect(
							"replication_completed",
							callback
						)

				break


func find_player_assisted_target() -> Node2D:
	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node):
			continue

		if node.get("player_assisting") != true:
			continue

		if node.has_method("is_restrained") and node.is_restrained():
			return node as Node2D

	return null


func update_team_attack(delta: float) -> void:
	if not is_instance_valid(team_attack_target):
		is_team_attacking = false
		return

	team_attack_timer -= delta

	if team_attack_timer <= 0.0:
		team_attack_timer = TEAM_ATTACK_INTERVAL

		team_attack_direction = global_position.direction_to(
			team_attack_target.global_position
		)

		is_team_attacking = true
		team_attack_animation_timer = 0.0

		if team_attack_target.has_method("take_damage"):
			team_attack_target.take_damage(TEAM_ATTACK_DAMAGE)
			print("Player attacks alongside the viral minions!")

		queue_redraw()


func _draw() -> void:
	if is_dead:
		var progress: float = clampf(
			death_timer / DEATH_ANIMATION_DURATION,
			0.0,
			1.0
		)

		for i in range(death_fragment_angles.size()):
			var angle: float = death_fragment_angles[i]
			var distance: float = death_fragment_distances[i] * progress

			var fragment_position := Vector2(
				cos(angle),
				sin(angle)
			) * distance

			var fragment_size: float = 5.0 * (1.0 - progress)

			var points := PackedVector2Array([
				fragment_position + Vector2(-fragment_size, -fragment_size),
				fragment_position + Vector2(fragment_size, 0.0),
				fragment_position + Vector2(0.0, fragment_size)
			])

			draw_colored_polygon(points, Color("#ff453a"))

		return

	# Draw the player's attack lunge.
	if is_team_attacking:
		var progress: float = clampf(
			team_attack_animation_timer / TEAM_ATTACK_ANIMATION_DURATION,
			0.0,
			1.0
		)

		var lunge: float = sin(progress * PI) * TEAM_ATTACK_LUNGE_DISTANCE
		var attack_tip: Vector2 = team_attack_direction * (24.0 + lunge)

		draw_line(
			Vector2.ZERO,
			attack_tip,
			Color("#ffd166"),
			5.0,
			true
		)
		draw_circle(attack_tip, 4.0, Color("#fff1b8"))

	# Draw the pathogen's spikes.
	for i in range(SPIKE_COUNT):
		var angle := TAU * float(i) / float(SPIKE_COUNT)
		var inner_radius := 11.0
		var outer_radius := 22.0

		var inner_left := angle - 0.16
		var inner_right := angle + 0.16

		var points := PackedVector2Array([
			Vector2(cos(inner_left), sin(inner_left)) * inner_radius,
			Vector2(cos(angle), sin(angle)) * outer_radius,
			Vector2(cos(inner_right), sin(inner_right)) * inner_radius
		])

		draw_colored_polygon(points, Color("#ff453a"))

	# Main body.
	draw_circle(Vector2.ZERO, 14.0, Color("#d71935"))
	draw_circle(Vector2(-4, -4), 4.0, Color("#ff9b91"))
	draw_circle(Vector2(4, 3), 2.5, Color("#8c1025"))


func update_health_label() -> void:
	if health_label:
		health_label.text = "Health: %d / %d" % [health, max_health]


func take_damage(amount: int) -> void:
	if amount <= 0 or is_dead:
		return

	health = max(health - amount, 0)
	update_health_label()

	if health <= 0:
		die()


func die() -> void:
	if is_dead:
		return

	is_dead = true
	inside_cell = false
	host_cell = null
	velocity = Vector2.ZERO
	visible = true
	death_timer = 0.0
	is_team_attacking = false

	death_fragment_angles.clear()
	death_fragment_distances.clear()

	for i in range(12):
		death_fragment_angles.append(randf_range(0.0, TAU))
		death_fragment_distances.append(randf_range(15.0, 40.0))

	print("The virus has been eliminated!")
	queue_redraw()


func heal(amount: int) -> void:
	if amount <= 0 or is_dead:
		return

	health = min(health + amount, max_health)
	update_health_label()


func show_game_over() -> void:
	var hud := get_node_or_null("/root/Main/HUD") as CanvasLayer

	if hud == null or hud.has_node("GameOverOverlay"):
		return

	var overlay := ColorRect.new()
	overlay.name = "GameOverOverlay"
	overlay.color = Color(0.02, 0.02, 0.05, 0.92)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.add_child(overlay)

	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 20)
	overlay.add_child(layout)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#ff453a"))
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(title)

	var message := Label.new()
	message.text = "Your virus has been eliminated."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	layout.add_child(message)

	var restart_button := Button.new()
	restart_button.text = "Restart"
	restart_button.custom_minimum_size = Vector2(180, 48)
	restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_button.pressed.connect(_on_restart_pressed)
	layout.add_child(restart_button)


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_host_cell_replication_completed(cell: Node2D) -> void:
	if is_dead:
		return

	if not inside_cell or host_cell != cell:
		return

	var exit_position: Vector2 = get_cell_exit_position(cell)

	start_cell_transition(
		"exit",
		global_position,
		exit_position
	)

	print("Replication complete! Virus is emerging!")

func start_cell_transition(
	transition: String,
	start_position: Vector2,
	end_position: Vector2
) -> void:
	is_transitioning = true
	transition_type = transition
	transition_timer = 0.0
	transition_start_position = start_position
	transition_end_position = end_position

	velocity = Vector2.ZERO
	scale = Vector2.ONE
	modulate.a = 1.0
	visible = true


func finish_cell_transition() -> void:
	is_transitioning = false
	transition_timer = 0.0
	scale = Vector2.ONE
	modulate.a = 1.0
	global_position = transition_end_position

	if transition_type == "enter":
		visible = false
	else:
		visible = true
		inside_cell = false
		host_cell = null
		print("Virus emerged from the host cell!")

	transition_type = ""


func get_cell_exit_position(cell: Node2D) -> Vector2:
	return cell.global_position + Vector2(50.0, 0.0)
