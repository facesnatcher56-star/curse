extends PanelContainer

var hero: Player
var _equipping: bool = false
var _bag_tiles: Array[ItemTile] = []
var _bag_scroll: ScrollContainer
var level_label: Label
var xp_label: Label
var xp_bar: Control
var classes_label: Label    # the four DS2 class skills and their levels
var attributes_label: Label  # STR, DEX, INT, life and mana

func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	position = Vector2(40, 70)
	size = Vector2(minf(900, get_viewport_rect().size.x - 80), minf(590, get_viewport_rect().size.y - 180))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	row.add_child(left)
	left.add_child(ItemTile._label(hero.display_name + " — Character", 24, UiTheme.TEXT))
	_add_progression(left)
	var portrait := SubViewportContainer.new()
	portrait.custom_minimum_size = Vector2(280, 160)
	portrait.stretch = true
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(portrait)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(280, 160)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	portrait.add_child(viewport)
	var model: Node3D = hero.visual.duplicate()
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		(animation as AnimationPlayer).play("game/idle_alert")
	viewport.add_child(model)
	model.position = Vector3.ZERO
	model.rotation.y = 0.35
	var camera := Camera3D.new()
	var bounds: AABB = CharacterModel._bounds_of(hero.visual)
	var centre: Vector3 = bounds.get_center()
	camera.fov = 35
	camera.position = centre + Vector3(0, 0, maxf(bounds.size.y, 1.0) * 2.0)
	viewport.add_child(camera)
	camera.look_at(centre)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_color = Color(0.92, 0.79, 0.61)
	light.light_energy = 2.0
	viewport.add_child(light)
	var skills_button: Button = UiTheme.button("Skills (%d)" % TownState.skill_points_left(), 140)
	skills_button.name = "skills"
	skills_button.pressed.connect(func() -> void: (get_parent() as Hud).open_skills())
	left.add_child(skills_button)
	left.add_child(ItemTile._label(gear_text(), 14, UiTheme.TEXT))
	_add_paper_doll(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var bag_head := HBoxContainer.new()
	right.add_child(bag_head)
	var bag_title: Label = ItemTile._label("Bag — %d items" % hero.stats.bag.size(), 24, UiTheme.TEXT)
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(bag_title)
	right.add_child(ItemTile._label("Confirm to equip" if Gamepad.active else "Right-click or double-click to equip", 14, UiTheme.TEXT_DIM))
	var scroll := ScrollContainer.new()
	_bag_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = clampi(int((size.x - 350) / 110), 1, 4)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for i in hero.stats.bag.size():
		var item: Dictionary = hero.stats.bag[i]
		var column := VBoxContainer.new()
		grid.add_child(column)
		var tile := ItemTile.create(item, hero.stats.equipment.get(int(item["slot"])), 56)
		tile.equip_hint = true   # (no Equip button under it: the card says how, "(R-click to equip)", and a pad confirms on it)
		column.add_child(tile)
		_bag_tiles.append(tile)
		tile.gui_input.connect(_item_input.bind(item, tile))
		var item_name := ItemTile.name_label(item, hero.stats.equipment.get(int(item["slot"])), true, true)
		column.add_child(item_name)
		item_name.gui_input.connect(_item_input.bind(item, item_name))
	if hero.stats.bag.is_empty():
		grid.add_child(ItemTile._label("Your bag is empty.", 16, UiTheme.TEXT))
	var close := UiTheme.button("Close", 110)
	right.add_child(close)
	close.pressed.connect(func() -> void:
		(get_parent() as Hud).close_character())
	close.grab_focus()

## Where each worn place sits on the paper doll (DS2's full gear: weapon, shield, helm, body, gloves, boots, amulet and two rings).
const DOLL: Array[int] = [Items.Slot.RING, Items.Slot.HELM, Items.Slot.AMULET, Items.Slot.WEAPON, Items.Slot.ARMOR, Items.Slot.SHIELD,
	Items.Slot.GLOVES, Items.Slot.BOOTS, Items.Slot.RING2]
var _doll_tiles: Array[Control] = []

func _add_paper_doll(parent: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for place in DOLL:
		var worn: Variant = hero.stats.equipment.get(place)
		var tile: Control
		if worn != null:
			var item_tile := ItemTile.create(worn, null, 48)
			item_tile.show_compare = false
			item_tile.tooltip_text = "%s (R-click to take off)" % Items.SLOT_NAMES[place]
			item_tile.gui_input.connect(_worn_input.bind(place, item_tile))
			tile = item_tile
		else:
			tile = _empty_place(Items.SLOT_NAMES[place])
		_doll_tiles.append(tile)
		grid.add_child(tile)

## An empty place on the doll: a dim frame with its name.
static func _empty_place(title: String) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(48, 48)
	box.tooltip_text = "%s: nothing worn" % title
	box.draw.connect(func() -> void:
		box.draw_rect(Rect2(Vector2.ZERO, box.size), Color(0.05, 0.048, 0.06, 0.6))
		box.draw_rect(Rect2(Vector2(1, 1), box.size - Vector2(2, 2)), Color(0.42, 0.4, 0.37, 0.35), false, 1.0)
		var font: Font = ThemeDB.fallback_font
		box.draw_string(font, Vector2(0, box.size.y * 0.5 + 4.0), title, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 10, Color(UiTheme.TEXT_DIM, 0.6)))
	return box

## "Armor 34   Block 0%   Fire resist 0%   Magic find 0%": what the gear adds up to.
func gear_text() -> String:
	return "Armor %d   Block %d%%   Fire resist %d%%   Magic find %d%%" % [int(hero.armor), int(round(hero.block_chance * 100.0)),
		int(round(hero.fire_resist * 100.0)), int(hero.stats.magic_find())]

## Right-click, double-click or confirm on a worn piece takes it off, into the bag.
func _worn_input(event: InputEvent, place: int, control: Control) -> void:
	var click := event as InputEventMouseButton
	var activate: bool = click != null and click.pressed and (click.button_index == MOUSE_BUTTON_RIGHT or (click.button_index == MOUSE_BUTTON_LEFT and click.double_click))
	if activate or (event.is_action_pressed("ui_accept") and not event.is_echo()):
		control.accept_event()
		_take_off(place)

func _take_off(place: int) -> void:
	if _equipping or hero.stats.bag.size() >= PlayerStats.MAX_BAG:
		if hero.stats.bag.size() >= PlayerStats.MAX_BAG:
			hero._say("Your bag is full")
		return
	var off: Variant = hero.stats.unequip(place)
	if off == null:
		return
	_equipping = true
	hero.stats.bag.append(off)
	if hero.get_parent() is TownScene:
		TownState.take_gear(hero.stats.equipment)
		TownState.save()
	(get_parent() as Hud)._open_character()
	if Gamepad.active:
		(get_parent() as Hud).character_panel.call_deferred("_focus_doll", DOLL.find(place))

func _focus_doll(index: int) -> void:
	if index >= 0 and index < _doll_tiles.size() and _doll_tiles[index].focus_mode != Control.FOCUS_NONE:
		_doll_tiles[index].grab_focus()

## The hero's permanent level and how far through it, read from TownState (the only place it lives). At the cap: "MAX LEVEL" and a full bar.
## It follows the progression events while the screen is open (no polling), so XP earned in play shows without closing it.
func _add_progression(parent: Control) -> void:
	var xp: int = TownState.hero_xp
	TownState.events.hero_xp_changed.connect(_on_xp_changed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	level_label = ItemTile._label("Level %d" % TownState.hero_level, 20, UiTheme.BRONZE_LIGHT.lightened(0.3))
	row.add_child(level_label)
	xp_label = ItemTile._label(HeroProgression.progress_text(xp), 15, UiTheme.TEXT_DIM)
	xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(xp_label)
	xp_bar = Control.new()
	xp_bar.custom_minimum_size = Vector2(280, 10)
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.draw.connect(func() -> void:
		UiTheme.draw_bar(xp_bar, Rect2(Vector2(2, 1), xp_bar.size - Vector2(4, 2)), HeroProgression.level_fraction(TownState.hero_xp), UiTheme.EMBER.darkened(0.2), "", ThemeDB.fallback_font))
	parent.add_child(xp_bar)
	classes_label = ItemTile._label(classes_text(), 14, UiTheme.TEXT)
	parent.add_child(classes_label)
	attributes_label = ItemTile._label(attributes_text(), 14, UiTheme.TEXT_DIM)
	parent.add_child(attributes_label)

## "Melee 4   Ranged 1   Combat Magic 0   Nature Magic 0": the DS2 class skills, which rise with use.
static func classes_text() -> String:
	var levels: Dictionary = HeroAttributes.levels_from_xp(TownState.class_xp)
	var parts: PackedStringArray = []
	for id in HeroAttributes.CLASSES:
		parts.append("%s %d" % [HeroAttributes.CLASS_NAMES[id], int(levels[id])])
	return "   ".join(parts)

## "STR 24  DEX 15  INT 15    Life 118  Mana 76".
func attributes_text() -> String:
	var a: Vector3 = hero.stats.attributes if hero != null else HeroAttributes.START
	return "STR %d  DEX %d  INT %d    Life %d  Mana %d" % [int(a.x), int(a.y), int(a.z), int(hero.max_health if hero != null else 0.0),
		int(hero.stats.max_mana if hero != null else 0.0)]

func _on_xp_changed(_old_xp: int, new_xp: int) -> void:
	if level_label == null:
		return
	level_label.text = "Level %d" % HeroProgression.level_for_xp(new_xp)
	xp_label.text = HeroProgression.progress_text(new_xp)
	xp_bar.queue_redraw()
	classes_label.text = classes_text()
	attributes_label.text = attributes_text()

func _exit_tree() -> void:
	if TownState.events.hero_xp_changed.is_connected(_on_xp_changed):
		TownState.events.hero_xp_changed.disconnect(_on_xp_changed)

func _item_input(event: InputEvent, item: Dictionary, control: Control) -> void:
	var click := event as InputEventMouseButton
	var activate: bool = click != null and click.pressed and (click.button_index == MOUSE_BUTTON_RIGHT or (click.button_index == MOUSE_BUTTON_LEFT and click.double_click))
	if activate or (event.is_action_pressed("ui_accept") and not event.is_echo()):
		control.accept_event()
		_equip_item(item)

func _equip_item(item: Dictionary) -> void:
	var index: int = hero.stats.bag.find(item)
	if _equipping or index < 0:
		return
	var off: Variant = hero.stats.equip(item)   # null: the weapon is out in the world, or he cannot wear it yet (he says why)
	if off == null:
		return
	_equipping = true
	hero.stats.bag.remove_at(index)
	for old in off:
		hero.stats.bag.append(old)
	var town := hero.get_parent() as TownScene
	if town != null:
		TownState.take_gear(hero.stats.equipment)
		TownState.save()
	(get_parent() as Hud)._open_character()
	if Gamepad.active:
		(get_parent() as Hud).character_panel.call_deferred("_focus_bag_item", index)

func _focus_bag_item(index: int) -> void:
	if not _bag_tiles.is_empty():
		var tile: ItemTile = _bag_tiles[clampi(index, 0, _bag_tiles.size() - 1)]
		tile.grab_focus()
		_bag_scroll.ensure_control_visible(tile)
