extends PanelContainer

var hero: Player
var _equipping: bool = false
var _bag_tiles: Array[ItemTile] = []
var _bag_scroll: ScrollContainer
const BagRules := preload("res://game/inventory_grid.gd")
const BagView := preload("res://game/ui/inventory_grid_view.gd")
var level_label: Label
var xp_label: Label
var xp_bar: Control
var classes_label: Label    # the four DS2 class skills and their levels
var attributes_label: Label  # STR, DEX, INT, life and mana
var _portrait: TextureRect
var _portrait_viewport: SubViewport

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_meta("reserve_party_cards", true)
	add_theme_stylebox_override("panel", UiTheme.panel_box())
	UiTheme.crest(self)
	UiTheme.responsive_window(self, Vector2(560, 640))
	position = Vector2(260, 40)
	size = Vector2(560, 640) # Keep the window close to its content, with room for a larger preview.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 280
	left.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(left)
	left.add_child(ItemTile._label(hero.display_name + " — Character", 24, UiTheme.TEXT))
	_add_progression(left)
	var portrait := TextureRect.new()
	_portrait = portrait
	portrait.name = "CharacterPortrait"
	portrait.custom_minimum_size = Vector2(280, 180)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(portrait)
	var viewport := SubViewport.new()
	_portrait_viewport = viewport
	viewport.size = Vector2i(280, 160)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_2X
	portrait.add_child(viewport)
	portrait.texture = viewport.get_texture()
	var model: Node3D = hero.visual.duplicate()
	for animation in model.find_children("*", "AnimationPlayer", true, false):
		(animation as AnimationPlayer).play("game/idle_alert")
	viewport.add_child(model)
	model.position = Vector3.ZERO
	model.rotation.y = 0.35
	var camera := Camera3D.new()
	# Bone-mounted weapons/fists have unreliable rest AABBs; frame the known actor body instead.
	var centre := Vector3(0, hero.body_height * 0.5, 0)
	camera.fov = 35
	camera.position = centre + Vector3(0, 0, hero.body_height * 1.75)
	viewport.add_child(camera)
	camera.look_at(centre)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_color = Color(0.92, 0.79, 0.61)
	light.light_energy = 2.0
	viewport.add_child(light)
	var skills_button: Button = UiTheme.button("Skills (%d)" % TownState.skill_points_left({}, hero.member_id), 140)
	skills_button.name = "skills"
	skills_button.pressed.connect(func() -> void: (get_parent() as Hud).open_skills())
	left.add_child(skills_button)
	var gear_label := ItemTile._label(gear_text(), 14, UiTheme.TEXT)
	gear_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(gear_label)
	_add_paper_doll(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var bag_head := HBoxContainer.new()
	right.add_child(bag_head)
	var used: int = 0
	for item in hero.stats.bag: used += BagRules.footprint(item).x * BagRules.footprint(item).y
	var bag_title: Label = ItemTile._label("Backpack — %d / 65" % used, 20, UiTheme.TEXT)
	bag_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(bag_title)
	var hint := ItemTile._label(("Confirm: equip · Select: move" if Gamepad.active else "Right-click: equip · Drag: move")
		+ " · %s: rotate" % GameSettings.short_binding_text("inventory_rotate"), 13, UiTheme.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 200
	right.add_child(hint)
	var scroll := ScrollContainer.new()
	_bag_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var grid := BagView.new()
	grid.name = "BackpackGrid"
	grid.stats = hero.stats
	grid.cell_size = 34.0 # Fit the window as a whole; do not leave a narrow grid in a wide column.
	grid.item_activated.connect(_equip_bag_index)
	grid.equipment_dropped.connect(_take_off)
	scroll.add_child(grid)
	_bag_tiles.assign(grid.tiles)
	var sort_button := UiTheme.button("Sort backpack", 150)
	sort_button.pressed.connect(_sort_bag)
	right.add_child(sort_button)
	var close := UiTheme.button("Close", 110)
	right.add_child(close)
	close.pressed.connect(func() -> void:
		(get_parent() as Hud).close_character())
	close.grab_focus()

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _portrait == null: return
	# Render at displayed physical pixels, not a tiny fixed texture enlarged by
	# canvas/interface scaling. Keep the camera aspect equal to the actual slot.
	var transform := _portrait.get_screen_transform()
	var pixels := Vector2i((_portrait.size * Vector2(transform.x.length(), transform.y.length())).ceil())
	pixels = pixels.max(Vector2i(2, 2))
	if _portrait_viewport.size != pixels: _portrait_viewport.size = pixels

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
			item_tile.action_hint = "(R-click to take off)"
			item_tile.gui_input.connect(_worn_input.bind(place, item_tile))
			tile = item_tile
		else:
			tile = _empty_place(Items.SLOT_NAMES[place])
		tile.set_drag_forwarding(_drag_worn.bind(place), _can_drop_on_worn.bind(place), _drop_on_worn.bind(place))
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

func _take_off(place: int, cell: Vector2i = BagRules.NONE) -> void:
	if _equipping or not hero.stats.unequip_to_bag(place, cell): return
	_equipping = true
	if hero.get_parent() is TownScene:
		hero.capture_state()
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
	var xp: int = hero.character.xp
	TownState.events.member_xp_changed.connect(_on_member_xp_changed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	level_label = ItemTile._label("Level %d" % hero.character.level, 20, UiTheme.BRONZE_LIGHT.lightened(0.3))
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
		UiTheme.draw_bar(xp_bar, Rect2(Vector2(2, 1), xp_bar.size - Vector2(4, 2)), HeroProgression.level_fraction(hero.character.xp), UiTheme.EMBER.darkened(0.2), "", ThemeDB.fallback_font))
	parent.add_child(xp_bar)
	classes_label = ItemTile._label(classes_text(hero.member_id), 14, UiTheme.TEXT)
	classes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(classes_label)
	attributes_label = ItemTile._label(attributes_text(), 14, UiTheme.TEXT_DIM)
	attributes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(attributes_label)

## "Melee 4   Ranged 1   Combat Magic 0   Nature Magic 0": the DS2 class skills, which rise with use.
static func classes_text(member_id: String = "hero") -> String:
	var levels: Dictionary = HeroAttributes.levels_from_xp(PartyManager.current().member(member_id).class_xp)
	var parts: PackedStringArray = []
	for id in HeroAttributes.CLASSES:
		parts.append("%s %d" % [HeroAttributes.CLASS_NAMES[id], int(levels[id])])
	return "   ".join(parts)

## "STR 24  DEX 15  INT 15    Life 118  Mana 76".
func attributes_text() -> String:
	var a: Vector3 = hero.stats.attributes if hero != null else HeroAttributes.START
	return "STR %d  DEX %d  INT %d    Life %d  Mana %d" % [int(a.x), int(a.y), int(a.z), int(hero.max_health if hero != null else 0.0),
		int(hero.stats.max_mana if hero != null else 0.0)]

func _on_member_xp_changed(member_id: String, old_xp: int, new_xp: int) -> void:
	if is_instance_valid(hero) and hero.member_id == member_id: _on_xp_changed(old_xp, new_xp)

func _on_xp_changed(_old_xp: int, new_xp: int) -> void:
	if level_label == null:
		return
	level_label.text = "Level %d" % HeroProgression.level_for_xp(new_xp)
	xp_label.text = HeroProgression.progress_text(new_xp)
	xp_bar.queue_redraw()
	classes_label.text = classes_text(hero.member_id)
	attributes_label.text = attributes_text()

func _exit_tree() -> void:
	if TownState.events.member_xp_changed.is_connected(_on_member_xp_changed):
		TownState.events.member_xp_changed.disconnect(_on_member_xp_changed)

func _equip_bag_index(index: int, place: int = -1) -> void:
	if _equipping or not hero.stats.equip_from_bag(index, place): return
	_equipping = true
	var town := hero.get_parent() as TownScene
	if town != null:
		hero.capture_state()
		TownState.save()
	(get_parent() as Hud)._open_character()
	if Gamepad.active:
		(get_parent() as Hud).character_panel.call_deferred("_focus_bag_item", index)

func _sort_bag() -> void:
	var sorted: Array = hero.stats.bag.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := BagRules.footprint(a)
		var sb := BagRules.footprint(b)
		return sa.x * sa.y > sb.x * sb.y)
	if BagRules.NONE in BagRules.layout(sorted, false):
		hero._say("Cannot sort without losing an item")
		return
	hero.stats.bag.assign(sorted)
	BagRules.arrange(hero.stats.bag, false)
	(get_parent() as Hud)._open_character()

func _drag_worn(_at: Vector2, place: int) -> Variant:
	if not hero.stats.equipment.has(place): return null
	var item: Dictionary = hero.stats.equipment[place]
	_doll_tiles[DOLL.find(place)].set_drag_preview(ItemTile.create(item, null, 48))
	return {"stats": hero.stats, "place": place}

func _can_drop_on_worn(_at: Vector2, data: Variant, place: int) -> bool:
	if not data is Dictionary or data.get("stats") != hero.stats or not data.has("index"): return false
	var index: int = int(data.index)
	return index >= 0 and index < hero.stats.bag.size() and place in Items.places(int(hero.stats.bag[index]["slot"]))

func _drop_on_worn(_at: Vector2, data: Variant, place: int) -> void:
	_equip_bag_index(int(data.index), place)

func _focus_bag_item(index: int) -> void:
	if not _bag_tiles.is_empty():
		var tile: ItemTile = _bag_tiles[clampi(index, 0, _bag_tiles.size() - 1)]
		tile.grab_focus()
		_bag_scroll.ensure_control_visible(tile)
