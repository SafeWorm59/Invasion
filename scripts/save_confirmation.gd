extends Control

# Dialog buttons - initialized from parent scene
var save_exit_btn: Button
var exit_without_save_btn: Button
var cancel_btn: Button

func _ready() -> void:
	# Find buttons using full scene paths
	save_exit_btn = get_node("main_panel/button_container/save_exit_btn") as Button
	exit_without_save_btn = get_node("main_panel/button_container/exit_without_save_btn") as Button
	cancel_btn = get_node("main_panel/button_container/cancel_btn") as Button
	
	# Connect button signals
	save_exit_btn.pressed.connect(_on_save_exit)
	exit_without_save_btn.pressed.connect(_on_exit_without_save)
	cancel_btn.pressed.connect(_on_cancel)

func _on_save_exit() -> void:
	hide()

func _on_exit_without_save() -> void:
	hide()

func _on_cancel() -> void:
	hide()
