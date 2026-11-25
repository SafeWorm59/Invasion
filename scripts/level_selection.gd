extends Control

const UISafeArea := preload("res://scripts/ui_safe_area.gd")

var selected_level_id: int = 1
var card_instances: Array[LevelCard] = []

@onready var main_layout: VBoxContainer = $MainLayout
@onready var scroll_container: ScrollContainer = $MainLayout/ScrollContainer
@onready var cards_container: HBoxContainer = $MainLayout/ScrollContainer/CardsHBox
@onready var footer_box: HBoxContainer = $MainLayout/FooterBox
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
	get_viewport().size_changed.connect(_fit_to_viewport)

	_fit_to_viewport()
	populate_level_cards()
	_fit_to_viewport()
	select_level(1)


func _fit_to_viewport() -> void:
	var viewport_size := get_viewport_rect().size
	var safe_rect := UISafeArea.get_safe_rect(viewport_size)
	var horizontal_margin := minf(40.0, maxf(16.0, safe_rect.size.x * 0.03))
	var vertical_margin := minf(24.0, maxf(12.0, safe_rect.size.y * 0.03))
	main_layout.anchor_left = 0.0
	main_layout.anchor_top = 0.0
	main_layout.anchor_right = 1.0
	main_layout.anchor_bottom = 1.0
	main_layout.offset_left = safe_rect.position.x + horizontal_margin
	main_layout.offset_top = safe_rect.position.y + vertical_margin
	main_layout.offset_right = safe_rect.end.x - viewport_size.x - horizontal_margin
	main_layout.offset_bottom = safe_rect.end.y - viewport_size.y - vertical_margin

	var footer_spacing := minf(20.0, maxf(8.0, safe_rect.size.x * 0.02))
	footer_box.add_theme_constant_override("separation", roundi(footer_spacing))
	var content_width := maxf(280.0, safe_rect.size.x - horizontal_margin * 2.0)
	var footer_width := maxf(280.0, content_width - footer_spacing)
	var width_scale := minf(1.0, footer_width / 460.0)
	back_button.custom_minimum_size = Vector2(maxf(120.0, 200.0 * width_scale), 48.0)
	launch_button.custom_minimum_size = Vector2(maxf(160.0, footer_width - back_button.custom_minimum_size.x), 48.0)
	back_button.add_theme_font_size_override("font_size", maxi(13, roundi(16.0 * width_scale)))
	launch_button.add_theme_font_size_override("font_size", maxi(12, roundi(16.0 * width_scale)))

	var card_gap := minf(16.0, maxf(8.0, safe_rect.size.x * 0.015))
	cards_container.add_theme_constant_override("separation", roundi(card_gap))
	var card_width := clampf((content_width - card_gap * 4.0) / 5.0, 170.0, 230.0)
	var card_height := minf(420.0, maxf(360.0, safe_rect.size.y - 310.0))
	scroll_container.custom_minimum_size.y = minf(410.0, maxf(240.0, safe_rect.size.y - 310.0))
	scroll_container.vertical_scroll_mode = 1 if safe_rect.size.y < 720.0 else 0
	for card in card_instances:
		card.set_responsive_size(card_width, card_height)


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
		var previous_level_id := id - 1
		var previous_level_available := (
			previous_level_id > 0
			and GameManager.is_level_available(previous_level_id)
		)
		if previous_level_available:
			info_status.text = "STATUS: COMPLETE LEVEL %02d TO UNLOCK" % previous_level_id
			launch_button.text = "COMPLETE LEVEL %02d TO UNLOCK" % previous_level_id
		else:
			info_status.text = "STATUS: LOCKED / COMING SOON"
			launch_button.text = "LEVEL LOCKED"
		info_status.add_theme_color_override("font_color", Color(0.7, 0.5, 0.5))
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
