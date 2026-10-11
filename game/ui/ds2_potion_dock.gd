class_name Ds2PotionDock
extends Control
## Dungeon Siege II-style bottom-left potion and utility dock.
## The game's single real consumable lives here; mana is already represented
## by the party bars and has no separate potion inventory.

const HEALTH_FLASK_TEX := preload("res://assets/ui/ds2/potion_flask_health.png")

var player: Player
var _hp_flask: TextureRect
var _hp_count_lbl: Label
var _hp_key_lbl: Label

signal potion_requested

func _init() -> void:
	custom_minimum_size = Vector2(176, 32)
	size = Vector2(176, 32)

func _ready() -> void:
	var screen: Vector2 = get_viewport_rect().size
	var bar_height: float = 72.0
	position = Vector2(28.0, screen.y - bar_height + (bar_height - 32.0) * 0.5)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	# 1. Health Flask Button (28x28 circular button)
	var hp_box := Control.new()
	hp_box.custom_minimum_size = Vector2(28, 28)
	hp_box.size = Vector2(28, 28)
	hp_box.mouse_filter = Control.MOUSE_FILTER_PASS
	hp_box.gui_input.connect(_on_hp_input)
	hbox.add_child(hp_box)

	_hp_flask = TextureRect.new()
	_hp_flask.texture = HEALTH_FLASK_TEX
	_hp_flask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hp_flask.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hp_flask.custom_minimum_size = Vector2(28, 28)
	_hp_flask.size = Vector2(28, 28)
	_hp_flask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_box.add_child(_hp_flask)

	_hp_count_lbl = Label.new()
	_hp_count_lbl.text = "1"
	_hp_count_lbl.position = Vector2(10, 12)
	_hp_count_lbl.size = Vector2(16, 14)
	_hp_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_count_lbl.add_theme_font_override("font", UiTheme.heading_font())
	_hp_count_lbl.add_theme_font_size_override("font_size", 10)
	_hp_count_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_hp_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_box.add_child(_hp_count_lbl)

	_hp_key_lbl = Label.new()
	_hp_key_lbl.text = "3"
	_hp_key_lbl.position = Vector2(2, 0)
	_hp_key_lbl.size = Vector2(12, 12)
	_hp_key_lbl.add_theme_font_size_override("font_size", 9)
	_hp_key_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65))
	_hp_key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_box.add_child(_hp_key_lbl)

	# Utility buttons (Bag/Inventory 'I', Character 'C', Journal 'J')
	for btn_info in [["I", "Inventory"], ["C", "Character"], ["J", "Journal"]]:
		var u_box := Control.new()
		u_box.custom_minimum_size = Vector2(24, 24)
		u_box.size = Vector2(24, 24)
		u_box.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.add_child(u_box)

		var u_bg := ColorRect.new()
		u_bg.size = Vector2(22, 22)
		u_bg.position = Vector2(1, 1)
		u_bg.color = Color(0.16, 0.14, 0.13, 0.95)
		u_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		u_box.add_child(u_bg)

		var u_border := ReferenceRect.new()
		u_border.size = Vector2(22, 22)
		u_border.position = Vector2(1, 1)
		u_border.border_color = Color(0.48, 0.42, 0.32, 0.9)
		u_border.border_width = 1.0
		u_border.editor_only = false
		u_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		u_box.add_child(u_border)

		var u_lbl := Label.new()
		u_lbl.text = btn_info[0]
		u_lbl.size = Vector2(22, 22)
		u_lbl.position = Vector2(1, 1)
		u_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		u_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		u_lbl.add_theme_font_override("font", UiTheme.heading_font())
		u_lbl.add_theme_font_size_override("font_size", 11)
		u_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 0.65))
		u_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		u_box.add_child(u_lbl)

func update_dock(p: Player) -> void:
	if p == null:
		return
	player = p
	var screen: Vector2 = get_viewport_rect().size
	var bar_height: float = 72.0
	position = Vector2(28.0, screen.y - bar_height + (bar_height - 32.0) * 0.5)
	var potions: int = int(p.stats.potions) if "potions" in p.stats else 1
	_hp_count_lbl.text = str(potions)
	_hp_key_lbl.text = GameSettings.short_binding_text("use_potion")
	_hp_flask.modulate = Color(1, 1, 1, 1.0 if potions > 0 else 0.45)

func _on_hp_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if player != null and player.skills != null:
			player.skills.drink_potion()
		potion_requested.emit()
