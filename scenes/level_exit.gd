
extends Area2D

@export var player_group: String = "player"
@onready var exit_visual: Sprite2D = $ExitVisual

var completed := false
var exit_locked := true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func set_exit_locked(locked: bool) -> void:
	var was_locked := exit_locked
	exit_locked = locked

	if was_locked and not exit_locked:
		play_unlock_animation()
	else:
		update_exit_visual()

	if exit_locked:
		print("Exit is locked. Defeat all Neutrophils first.")
	else:
		print("Exit is now unlocked!")


func play_unlock_animation() -> void:
	# Make the mucus plug shake.
	var shake := create_tween()
	shake.tween_property(exit_visual, "rotation", 0.08, 0.08)
	shake.tween_property(exit_visual, "rotation", -0.08, 0.08)
	shake.tween_property(exit_visual, "rotation", 0.05, 0.08)
	shake.tween_property(exit_visual, "rotation", 0.0, 0.08)

	# Wait until the shaking finishes.
	await shake.finished

	# Create the mucus splash.
	create_mucus_splash()

	# Reveal the open passage.
	update_exit_visual()

	# Give the open passage a little pulse.
	var original_scale := exit_visual.scale
	var pulse := create_tween()
	pulse.tween_property(exit_visual, "scale", original_scale * 1.15, 0.15)
	pulse.tween_property(exit_visual, "scale", original_scale, 0.2)


func create_mucus_splash() -> void:
	for i in range(10):
		var droplet := Polygon2D.new()
		var points := PackedVector2Array()

		for j in range(12):
			var angle := j * TAU / 12
			points.append(Vector2(cos(angle), sin(angle)) * randf_range(3.0, 6.0))

		droplet.polygon = points
		droplet.color = Color(0.65, 0.85, 0.12, 1.0)
		droplet.position = exit_visual.position
		get_parent().add_child(droplet)

		var angle := randf_range(0.0, TAU)
		var distance := randf_range(25.0, 65.0)
		var destination := droplet.position + Vector2(cos(angle), sin(angle)) * distance

		var splash := create_tween()
		splash.set_parallel(true)
		splash.tween_property(droplet, "position", destination, 0.45)
		splash.tween_property(droplet, "modulate:a", 0.0, 0.45)
		splash.tween_property(droplet, "scale", Vector2.ZERO, 0.45)

		splash.chain().tween_callback(droplet.queue_free)


func _on_body_entered(body: Node2D) -> void:
	if completed or exit_locked:
		return

	if body.is_in_group(player_group):
		completed = true
		show_completion_popup()


func show_completion_popup() -> void:
	GameManager.show_level_completion_dialog(1)


func update_exit_visual() -> void:
	var region := exit_visual.region_rect

	if exit_locked:
		region.position.x = 0
	else:
		region.position.x = 887

	exit_visual.region_rect = region
