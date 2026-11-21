extends Control

var selected_level_id: int = 1
var card_instances: Array[LevelCard] = []

@onready var cards_container: HBoxContainer = $MainLayout/ScrollContainer/CardsHBox
@onready var back_button: Button = $MainLayout/FooterBox/BackButton
@onready var launch_button: Button = $MainLayout/FooterBox/LaunchButton
@onready var info_title: Label = $MainLayout/DetailPanel/Margin/VBox/DetailTitle
@onready var info_desc: Label = $MainLayout/DetailPanel/Margin/VBox/DetailDesc
@onready var info_status: Label = $MainLayout/DetailPanel/Margin/VBox/DetailStatus

const CARD_SCENE := preload("res://scenes/level_card.tscn")


func _ready() -> void:
	UIThemeHelper.style_button(back_button, false)
	UIThemeHelper.style_button(launch_button, true)

	var detail_panel := $MainLayout/DetailPanel as PanelContainer
	detail_panel.add_theme_stylebox_override("panel", UIThemeHelper.create_panel_style(Color(0.10, 0.03, 0.06, 0.92), Color(0.65, 0.20, 0.30, 0.7), 10))

	back_button.pressed.connect(_on_back_pressed)
	launch_button.pressed.connect(_on_launch_pressed)

	populate_level_cards()
	select_level(1)


func populate_level_cards() -> void:
	# Clear existing children
	for child in cards_container.get_children():
		child.queue_free()
	card_instances.clear()

	var levels: Array[Dictionary] = GameManager.get_levels()
	for lvl in levels:
		var card := CARD_SCENE.instantiate() as LevelCard
		cards_container.add_child(card)
		card.setup(lvl)
		card.level_selected.connect(_on_card_selected)
		card.level_launched.connect(_on_card_launched)
		card_instances.append(card)


func _on_card_selected(level_data: Dictionary) -> void:
	select_level(level_data.get("id", 1))


func _on_card_launched(level_id: int) -> void:
	select_level(level_id)
	_on_launch_pressed()


func select_level(id: int) -> void:
	selected_level_id = id
	var lvl: Dictionary = GameManager.get_level(id)
	if lvl.is_empty():
		return

	for card in card_instances:
		card.set_selected(card.level_data.get("id", 0) == id)

	var is_locked: bool = lvl.get("locked", true)
	info_title.text = "PHASE %02d: %s" % [id, lvl.get("name", "")]
	info_desc.text = lvl.get("description", "")

	if is_locked:
		info_status.text = "STATUS: LOCKED / COMING SOON"
		info_status.add_theme_color_override("font_color", Color(0.7, 0.5, 0.5))
		launch_button.text = "LEVEL LOCKED"
		launch_button.disabled = true
	else:
		info_status.text = "STATUS: INFILTRATION VECTOR AVAILABLE"
		info_status.add_theme_color_override("font_color", Color(0.35, 0.95, 0.60))
		launch_button.text = "INFILTRATE TARGET (LEVEL %02d)" % id
		launch_button.disabled = false


func _on_launch_pressed() -> void:
	if GameManager.is_level_available(selected_level_id):
		GameManager.load_level(selected_level_id)


func _on_back_pressed() -> void:
	GameManager.load_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
