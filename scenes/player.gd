
extends CharacterBody2D

const SPEED: float = 200.0
const SPIKE_COUNT: int = 12
const DEATH_ANIMATION_DURATION: float = 0.4
const CELL_TRANSITION_DURATION: float = 0.35

# Configure this to match the physics layer used by your walls.
@export_flags_2d_physics var wall_collision_mask: int = 1

@export var safe_exit_distance: float = 55.0
@export var safe_exit_search_step: float = 20.0
@export var safe_exit_search_attempts: int = 12
@export var player_clearance_radius: float = 14.0

var max_health: int = 100
var health: int = 100

var is_transitioning: bool = false
var transition_timer: float = 0.0
var transition_type: String = ""
var transition_start_position: Vector2 = Vector2.ZERO
var transition_end_position: Vector2 = Vector2.ZERO

var inside_cell: bool = false
var host_cell: Node2D = null
var _exit_after_entry_cell: Node2D = null

var is_dead: bool = false
var death_timer: float = 0.0
var death_fragment_angles: Array[float] = []
var death_fragment_distances: Array[float] = []

var team_attack_target: Node2D = null
var team_attack_timer: float = 0.0
var team_attack_animation_timer: float = 0.0
var is_team_attacking: bool = false
var team_attack_direction: Vector2 = Vector2.RIGHT
var _assisted_target_scan_timer: float = 0.0
var _assisted_target_cache: Node2D = null
var network_movement_input: Vector2 = Vector2.ZERO

const TEAM_ATTACK_INTERVAL: float = 0.7
const TEAM_ATTACK_ANIMATION_DURATION: float = 0.25
const TEAM_ATTACK_DAMAGE: int = 10
const TEAM_ATTACK_LUNGE_DISTANCE: float = 12.0

var hud: Node = null


func _enter_tree() -> void:
	if not MultiplayerSession.is_session_active:
		return

	var authority_id := multiplayer.get_unique_id()
	if has_meta("network_peer_id"):
		authority_id = int(get_meta("network_peer_id"))
	set_multiplayer_authority(authority_id, true)


func _ready() -> void:
	if MultiplayerSession.is_session_active:
		var camera := get_node_or_null("Camera2D") as Camera2D
		var is_local_player := is_multiplayer_authority()
		if camera != null:
			camera.enabled = is_local_player
		if not is_local_player:
			set_process(false)
			set_physics_process(false)
			return

	add_to_group("player")
	find_hud()
	update_health_label()
	if MultiplayerSession.is_session_active:
		call_deferred("_register_multiplayer_player")


func _register_multiplayer_player() -> void:
	if (
		MultiplayerSession.is_session_active
		and is_multiplayer_authority()
	):
		MultiplayerSession.register_local_player(self)


func _process(delta: float) -> void:
	if not is_instance_valid(hud):
		find_hud()
		update_health_label()

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
	if MultiplayerSession.is_session_active and not is_multiplayer_authority():
		return

	if is_dead:
		network_movement_input = Vector2.ZERO
		velocity = Vector2.ZERO
		return

	if inside_cell:
		network_movement_input = Vector2.ZERO
		velocity = Vector2.ZERO

		if Input.is_action_just_pressed("interact"):
			perform_context_interaction()

		return

	if is_transitioning:
		network_movement_input = Vector2.ZERO
		velocity = Vector2.ZERO
		return

	var direction := Input.get_vector(
		"ui_left",
		"ui_right",
		"ui_up",
		"ui_down"
	)

	team_attack_target = find_player_assisted_target(delta)

	if is_instance_valid(team_attack_target):
		if direction.length() > 0.1:
			velocity = direction * SPEED
		else:
			var slot_position: Vector2 = (
				team_attack_target.get_player_slot_position()
			)

			var distance_to_slot := global_position.distance_to(
				slot_position
			)

			if distance_to_slot > 5.0:
				velocity = (
					global_position.direction_to(slot_position) * SPEED
				)
			else:
				velocity = Vector2.ZERO

		update_team_attack(delta)
	else:
		velocity = direction * SPEED
		is_team_attacking = false
		team_attack_timer = 0.0

	network_movement_input = (velocity / SPEED).limit_length(1.0)
	move_and_slide()

	if Input.is_action_just_pressed("interact"):
		perform_context_interaction()


func perform_context_interaction() -> void:
	if is_dead or is_transitioning:
		return

	if inside_cell:
		if is_instance_valid(host_cell):
			var exit_position: Vector2 = get_cell_exit_position(host_cell)
			start_cell_transition("exit", global_position, exit_position)
		return

	for node in get_tree().get_nodes_in_group("host_cells"):
		if (
			not is_instance_valid(node)
			or not node.has_method("can_player_enter")
			or not node.has_method("try_enter")
		):
			continue

		var cell := node as Node2D
		if not cell.can_player_enter(self) or not cell.try_enter(self):
			continue

		inside_cell = true
		host_cell = cell
		start_cell_transition("enter", global_position, cell.global_position)

		if cell.has_signal("replication_completed"):
			var callback := Callable(self, "_on_host_cell_replication_completed")
			if not cell.is_connected("replication_completed", callback):
				cell.connect("replication_completed", callback)
		return

	if is_instance_valid(hud) and hud.has_method("perform_join_attack"):
		hud.perform_join_attack(self)


func find_hud() -> void:
	hud = get_tree().get_first_node_in_group("hud")


func find_player_assisted_target(delta: float) -> Node2D:
	if (
		is_instance_valid(_assisted_target_cache)
		and _assisted_target_cache.get("player_assisting") == true
		and _assisted_target_cache.has_method("is_restrained")
		and _assisted_target_cache.is_restrained()
	):
		return _assisted_target_cache

	_assisted_target_cache = null
	_assisted_target_scan_timer -= delta
	if _assisted_target_scan_timer > 0.0:
		return null
	_assisted_target_scan_timer = 0.1

	for node in get_tree().get_nodes_in_group("immune_cells"):
		if not is_instance_valid(node):
			continue

		if node.get("player_assisting") != true:
			continue

		if node.has_method("is_restrained") and node.is_restrained():
			_assisted_target_cache = node as Node2D
			return _assisted_target_cache

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
			if OS.is_debug_build():
				print("Player attacks alongside the viral minions!")

		queue_redraw()


# Finds a position near the cell that does not overlap walls.
func get_cell_exit_position(cell: Node2D) -> Vector2:
	var space_state := get_world_2d().direct_space_state

	var directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.DOWN,
		Vector2.UP,
		Vector2(1, 1).normalized(),
		Vector2(-1, 1).normalized(),
		Vector2(1, -1).normalized(),
		Vector2(-1, -1).normalized()
	]

	# Try the closest positions first.
	for attempt in range(safe_exit_search_attempts):
		var distance: float = (
			safe_exit_distance
			+ float(attempt) * safe_exit_search_step
		)

		for direction in directions:
			var candidate: Vector2 = (
				cell.global_position + direction * distance
			)

			if is_position_clear(candidate, space_state):
				print("Found a safe cell exit position: ", candidate)
				return candidate

	# If no candidate is available, keep the player at the cell's
	# current location rather than placing them beyond a wall.
	push_warning(
		"No clear cell exit position found. Using cell position."
	)

	return cell.global_position


func is_position_clear(
	position_to_check: Vector2,
	space_state: PhysicsDirectSpaceState2D
) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = player_clearance_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, position_to_check)
	query.collision_mask = wall_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 1.0

	var results: Array[Dictionary] = space_state.intersect_shape(
		query,
		8
	)

	return results.is_empty()


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

	if is_team_attacking:
		var progress: float = clampf(
			team_attack_animation_timer / TEAM_ATTACK_ANIMATION_DURATION,
			0.0,
			1.0
		)

		var lunge: float = (
			sin(progress * PI) * TEAM_ATTACK_LUNGE_DISTANCE
		)

		var attack_tip: Vector2 = (
			team_attack_direction * (24.0 + lunge)
		)

		draw_line(
			Vector2.ZERO,
			attack_tip,
			Color("#ffd166"),
			5.0,
			true
		)

		draw_circle(attack_tip, 4.0, Color("#fff1b8"))

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

	draw_circle(Vector2.ZERO, 14.0, Color("#d71935"))
	draw_circle(Vector2(-4, -4), 4.0, Color("#ff9b91"))
	draw_circle(Vector2(4, 3), 2.5, Color("#8c1025"))


func update_health_label() -> void:
	if not is_instance_valid(hud):
		find_hud()

	if is_instance_valid(hud) and hud.has_method("update_player_health"):
		hud.update_player_health(health, max_health)


func take_damage(amount: int) -> void:
	# The virus is protected for the full host-cell visit, including the fade
	# transitions where it may still be visible to enemy targeting code.
	if amount <= 0 or is_dead or inside_cell:
		return

	print("[PLAYER DAMAGE] Received: ", amount, " HP")

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
	var hud_layer := get_tree().get_first_node_in_group("hud") as CanvasLayer

	if hud_layer == null or hud_layer.has_node("GameOverOverlay"):
		return

	var overlay := ColorRect.new()
	overlay.name = "GameOverOverlay"
	overlay.color = Color(0.02, 0.02, 0.05, 0.92)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_layer.add_child(overlay)

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


## Lets a level that completes its infection objective on entry leave the final
## host without waiting for that cell's replication timer.
func request_exit_after_entry(cell: Node2D) -> void:
	if not is_instance_valid(cell):
		return
	if inside_cell and host_cell == cell:
		if is_transitioning and transition_type == "enter":
			_exit_after_entry_cell = cell
		else:
			force_eject(cell)
		return
	_exit_after_entry_cell = cell


## Called by a host cell that an NKT cell has just destroyed. The virus is
## pushed out of the dying cell instead of being trapped inside a freed node.
func force_eject(cell: Node2D) -> void:
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

	print("Host cell destroyed! Virus forced out!")


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
		if is_instance_valid(_exit_after_entry_cell) and host_cell == _exit_after_entry_cell:
			var cell_to_exit := host_cell
			_exit_after_entry_cell = null
			start_cell_transition(
				"exit",
				global_position,
				get_cell_exit_position(cell_to_exit)
			)
			return
	else:
		visible = true
		inside_cell = false
		host_cell = null
		print("Virus emerged from the host cell!")

	transition_type = ""
