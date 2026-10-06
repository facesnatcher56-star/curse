class_name TownPanel
extends Control
## The window that opens when the hero talks to someone or uses something in town: the trader's wares, the job board, the healer,
## the recruit and the stash. Built in code from TownState; every button is an ordinary focusable Button, so a controller's
## D-pad and A/B drive it. The world is paused while it is open.

signal closed

const POTION_PRICE := 15
const FOOD_PRICE := 6
const FOOD_PACK := 3

var town: Node            # the TownScene (for its sim and the hero)
var current: String = ""  # which page is showing: "npc:<id>", "board", "stash"
var notice: String = ""

var _dim: ColorRect
var _box: VBoxContainer
var _scroll: ScrollContainer
var _detail: Label
var _footer: VBoxContainer
var _opened_frame: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.BORDER, 2, 4, 22))
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 9)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	outer.add_child(_footer)

func is_open() -> bool:
	return visible or Engine.get_process_frames() == _opened_frame

func open_npc(id: String) -> void:
	current = "npc:" + id
	notice = ""
	_show()

func open_board() -> void:
	current = "board"
	notice = ""
	_show()

func open_stash() -> void:
	current = "stash"
	notice = ""
	_show()

func close() -> void:
	if not visible:
		return
	visible = false
	_opened_frame = Engine.get_process_frames()
	get_tree().paused = false
	closed.emit()

func _show() -> void:
	_scroll.custom_minimum_size = Vector2(0, minf(get_viewport_rect().size.y * 0.74, 640.0))
	visible = true
	get_tree().paused = true
	_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()

# --- Pages ---------------------------------------------------------------------------------------------------------------

func _rebuild() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if current.begins_with("npc:"):
		_page_npc(current.substr(4))
	elif current == "board":
		_page_board()
	elif current == "stash":
		_page_stash()
	for child in _footer.get_children():
		_footer.remove_child(child)
		child.queue_free()
	if notice != "":
		var note := Label.new()
		note.text = notice
		note.add_theme_color_override("font_color", UiTheme.ACCENT)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_footer.add_child(note)
	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_theme_font_size_override("font_size", 15)
	_detail.custom_minimum_size = Vector2(0, 40)
	_footer.add_child(_detail)
	var done := UiTheme.button("Close", 200.0)
	done.pressed.connect(close)
	_footer.add_child(done)
	# The controller needs something selected; the first action button, not "Close", when there is one.
	UiTheme.focus_first.call_deferred(_box)

func _page_npc(id: String) -> void:
	var def: NpcDef = TownDb.npc(id)
	var mood: float = TownState.happiness(id)
	_box.add_child(UiTheme.title_label(def.display_name, 38))
	_text("%s    Mood: %s" % [def.title, TownState.mood_word(mood)], UiTheme.TEXT_DIM)
	_text("\"%s\"" % town.sim.line_for(id, "greet"), UiTheme.TEXT)
	var trait_names: Array[String] = []
	for t in TownState.traits_of(id):
		trait_names.append(TownDb.trait_def(t).display_name)
	_text("Nature: " + ", ".join(trait_names), UiTheme.TEXT_DIM)
	_add_gap(6)
	match def.role:
		"vendor":
			_page_vendor(id)
		"smith":
			_page_smith(id)
		"keeper":
			_page_jobs()
			_page_report()
		"healer":
			_page_healer(id)
		"recruit":
			_page_recruit(id, def)
	_add_gap(4)
	_page_opinions(id)

func _page_vendor(id: String) -> void:
	var price_mult: float = TownSim.mood_price_mult(id)
	_text("Gold: %d      Trader's coin: %d      Food: %d      Potions: %d" % [TownState.gold, TownState.vendor_gold,
		TownState.food, TownState.potions], UiTheme.ACCENT)
	if price_mult != 1.0:
		_text("Prices are %s today." % ("lower" if price_mult < 1.0 else "higher"), UiTheme.TEXT_DIM)
	if TownState.stock.is_empty():
		_restock()
	var wares := HFlowContainer.new()
	wares.add_theme_constant_override("h_separation", 18)
	_box.add_child(wares)
	for i in TownState.stock.size():
		var entry: Dictionary = TownState.stock[i]
		var price: int = int(round(int(entry["price"]) * price_mult))
		wares.add_child(_item_card(entry["item"], "Buy  %dg" % price, TownState.gold < price, func() -> void: _buy(i, price)))
	_row("Food (+%d)" % FOOD_PACK, "Buy  %dg" % int(round(FOOD_PRICE * price_mult)), TownState.gold < int(round(FOOD_PRICE * price_mult)),
		func() -> void: _buy_supply("food", int(round(FOOD_PRICE * price_mult))))
	_row("Health potion", "Buy  %dg" % int(round(POTION_PRICE * price_mult)), TownState.gold < int(round(POTION_PRICE * price_mult)),
		func() -> void: _buy_supply("potion", int(round(POTION_PRICE * price_mult))))
	if not TownState.stash.is_empty():
		_text("Sell from your stash (half price, while his coin lasts):", UiTheme.TEXT_DIM)
		var sells := HFlowContainer.new()
		sells.add_theme_constant_override("h_separation", 18)
		_box.add_child(sells)
		for i in TownState.stash.size():
			var item: Dictionary = TownState.stash[i]
			var offer: int = int(TownState.item_price(item) / 2)
			sells.add_child(_item_card(item, "Sell  %dg" % offer, TownState.vendor_gold < offer, func() -> void: _sell(i, offer)))

## The smith sells weapons and armour only (never trinkets or supplies) and buys the same from the stash. Later: reforging,
## repairs, salvage.
func _page_smith(id: String) -> void:
	var price_mult: float = TownSim.mood_price_mult(id)
	_text("Gold: %d      Smith's coin: %d" % [TownState.gold, TownState.smith_gold], UiTheme.ACCENT)
	if price_mult != 1.0:
		_text("Prices are %s today." % ("lower" if price_mult < 1.0 else "higher"), UiTheme.TEXT_DIM)
	if TownState.smith_stock.is_empty():
		_restock_smith()
	var wares := HFlowContainer.new()
	wares.add_theme_constant_override("h_separation", 18)
	_box.add_child(wares)
	for i in TownState.smith_stock.size():
		var entry: Dictionary = TownState.smith_stock[i]
		var price: int = int(round(int(entry["price"]) * price_mult))
		wares.add_child(_item_card(entry["item"], "Buy  %dg" % price, TownState.gold < price, func() -> void: _smith_buy(i, price, id)))
	var sellable: Array[int] = []
	for i in TownState.stash.size():
		if int(TownState.stash[i]["slot"]) != Items.Slot.TRINKET:
			sellable.append(i)
	if not sellable.is_empty():
		_text("Sell weapons and armour from your stash (half price, while his coin lasts):", UiTheme.TEXT_DIM)
		var sells := HFlowContainer.new()
		sells.add_theme_constant_override("h_separation", 18)
		_box.add_child(sells)
		for i in sellable:
			var item: Dictionary = TownState.stash[i]
			var offer: int = int(TownState.item_price(item) / 2)
			sells.add_child(_item_card(item, "Sell  %dg" % offer, TownState.smith_gold < offer, func() -> void: _smith_sell(i, offer)))

func _restock_smith() -> void:
	TownState.smith_stock = []
	var none: Array[String] = []
	var names: Array[String] = []
	var rare_chance: float = minf(0.25 + 0.1 * TownState.jobs_done, 0.6)
	for attempt in 80:
		if TownState.smith_stock.size() >= 4:
			break
		var item: Dictionary = Items.roll_one(1 + TownState.jobs_done, 0.0, rare_chance, none)
		if int(item["slot"]) == Items.Slot.TRINKET or String(item["name"]) in names:
			continue
		names.append(String(item["name"]))
		TownState.smith_stock.append({"item": item, "price": TownState.item_price(item)})

func _smith_buy(index: int, price: int, id: String) -> void:
	if index >= TownState.smith_stock.size() or TownState.gold < price:
		return
	var item: Dictionary = (TownState.smith_stock[index] as Dictionary)["item"]
	TownState.gold -= price
	TownState.smith_gold += price
	TownState.smith_stock.remove_at(index)
	var old: Variant = town.equip_town_item(item)
	if old != null:
		TownState.stash_item(old as Dictionary)
	TownState.add_happiness(id, 1.0)
	notice = "Bought %s. It is yours to wear; the old piece went to the stash." % item["name"]
	TownState.save()
	_rebuild()

func _smith_sell(index: int, offer: int) -> void:
	if index >= TownState.stash.size() or TownState.smith_gold < offer:
		return
	var item: Dictionary = TownState.stash[index]
	TownState.stash.remove_at(index)
	TownState.smith_gold -= offer
	TownState.gold += offer
	notice = "Sold %s for %dg." % [item["name"], offer]
	TownState.save()
	_rebuild()

func _restock() -> void:
	TownState.stock = []
	var owned: Array[String] = []
	for item in TownState.gear.values():
		if int((item as Dictionary)["rarity"]) == Items.Rarity.UNIQUE:
			owned.append(String((item as Dictionary)["name"]))
	for item in Items.roll_choices(1 + TownState.jobs_done, false, owned):
		TownState.stock.append({"item": item, "price": TownState.item_price(item)})

func _buy(index: int, price: int) -> void:
	if index >= TownState.stock.size() or TownState.gold < price:
		return
	var item: Dictionary = (TownState.stock[index] as Dictionary)["item"]
	TownState.gold -= price
	TownState.vendor_gold += price
	TownState.stock.remove_at(index)
	var old: Variant = town.equip_town_item(item)
	if old != null:
		TownState.stash_item(old as Dictionary)
	TownState.add_happiness("marlow", 1.0)
	notice = "Bought %s. It is yours to wear; the old piece went to the stash." % item["name"]
	TownState.save()
	_rebuild()

func _sell(index: int, offer: int) -> void:
	if index >= TownState.stash.size() or TownState.vendor_gold < offer:
		return
	var item: Dictionary = TownState.stash[index]
	TownState.stash.remove_at(index)
	TownState.vendor_gold -= offer
	TownState.gold += offer
	notice = "Sold %s for %dg." % [item["name"], offer]
	TownState.save()
	_rebuild()

func _buy_supply(kind: String, price: int) -> void:
	if TownState.gold < price:
		return
	TownState.gold -= price
	TownState.vendor_gold += price
	if kind == "food":
		TownState.food += FOOD_PACK
		notice = "Food +%d." % FOOD_PACK
	else:
		town.change_potions(1)
		notice = "Potion +1."
	TownState.save()
	_rebuild()

func _page_jobs() -> void:
	_text("Posted quests. Every one is already yours: go out and do it, then come back and I will pay you.", UiTheme.TEXT_DIM)
	for offer in TownState.board:
		var ready: bool = bool(offer.get("ready", false))
		var stage: int = int(JobObjective.stages(offer)) if ready else town.quest_stage()
		var status: String = "Done. Waiting for you to collect." if ready else JobObjective.progress_text(offer, {"stage": stage})
		var title: String = "%s  -  %s  -  %dg\n%s" % [offer["name"], JobObjective.describe(offer), int(offer["reward"]), status]
		_row(title, "Collect reward" if ready else "In progress", not ready, _claim)
		for m in offer.get("modifiers", []):
			_text("      " + TownDb.modifier(m).display_name + ": " + TownDb.modifier(m).description, UiTheme.TEXT_DIM)

## Hale pays what is done (the world posts the next quest and puts the road back as it was).
func _claim() -> void:
	var paid: Dictionary = town.claim_rewards()
	notice = "Paid: %dg. A new quest is posted." % int(paid["gold"]) if int(paid["count"]) > 0 else "Nothing to collect yet."
	TownState.save()
	_rebuild()

func _page_report() -> void:
	_add_gap(4)
	_text("Town: food %d (%s), %d people, gold %d." % [TownState.food, "rationing" if TownState.rationing() else "enough for now",
		TownState.member_ids().size(), TownState.gold], UiTheme.TEXT_DIM)
	var shown: int = 0
	for i in range(town.sim.history.size() - 1, -1, -1):
		if shown >= 3:
			break
		_text("- " + town.sim.history[i], UiTheme.TEXT_DIM)
		shown += 1

func _page_healer(id: String) -> void:
	_text("Gold: %d      Potions: %d" % [TownState.gold, TownState.potions], UiTheme.ACCENT)
	var hero: Player = town.player
	var hurt: bool = hero.health < hero.max_health - 0.5
	_row("Tend your wounds", "Heal", not hurt, func() -> void:
		hero.health = hero.max_health
		TownState.add_happiness(id, 1.0)
		notice = "Maren binds you up. You are whole again."
		_rebuild())
	var price: int = int(round(12 * TownSim.mood_price_mult(id)))
	_row("Health potion", "Buy  %dg" % price, TownState.gold < price, func() -> void: _buy_supply("potion", price))

func _page_recruit(id: String, def: NpcDef) -> void:
	var member: bool = bool(TownState.npcs[id]["member"])
	_text("Skill: %s (+2 food every time the clan returns from a job)" % def.clan_skill.capitalize(), UiTheme.TEXT)
	if member:
		_text("%s has joined the clan." % def.display_name, UiTheme.ACCENT)
		return
	_row("Hire %s" % def.display_name, "Hire  %dg" % def.recruit_cost, TownState.gold < def.recruit_cost, func() -> void:
		TownState.gold -= def.recruit_cost
		TownState.npcs[id]["member"] = true
		TownState.add_happiness(id, 10.0)
		notice = town.sim.line_for(id, "hire")
		TownState.save()
		_rebuild())
	_text("Another mouth to feed: every job costs the clan more food.", UiTheme.TEXT_DIM)

func _page_opinions(id: String) -> void:
	var parts: Array[String] = []
	for other in TownState.present_ids():
		if other == id:
			continue
		parts.append("%s: %s" % [TownDb.npc(other).display_name, TownState.opinion_word(TownState.relation(id, other))])
	if not parts.is_empty():
		_text("Thinks of the others:  " + "    ".join(parts), UiTheme.TEXT_DIM)

func _page_board() -> void:
	_box.add_child(UiTheme.title_label("Job Board", 38))
	_page_jobs()
	_page_report()

func _page_stash() -> void:
	_box.add_child(UiTheme.title_label("Stash", 38))
	_text("Worn", UiTheme.TEXT_DIM)
	var worn_row := HBoxContainer.new()
	worn_row.add_theme_constant_override("separation", 14)
	_box.add_child(worn_row)
	for slot in 3:
		var worn: Variant = TownState.gear.get(slot)
		if worn != null:
			worn_row.add_child(ItemTile.create(worn, null))
	if worn_row.get_child_count() == 0:
		_text("Only the starting kit.", UiTheme.TEXT_DIM)
	_add_gap(6)
	_text("Stash: point at an item for its details", UiTheme.TEXT_DIM)
	if TownState.stash.is_empty():
		_text("Nothing stored. Gear you swap out ends up here.", UiTheme.TEXT_DIM)
	var stored := HFlowContainer.new()
	stored.add_theme_constant_override("h_separation", 18)
	_box.add_child(stored)
	for i in TownState.stash.size():
		var item: Dictionary = TownState.stash[i]
		stored.add_child(_item_card(item, "Wear", false, func() -> void: _wear(i)))

func _wear(index: int) -> void:
	if index >= TownState.stash.size():
		return
	var item: Dictionary = TownState.stash[index]
	TownState.stash.remove_at(index)
	var old: Variant = town.equip_town_item(item)
	if old != null:
		TownState.stash.append(old)
	notice = "Now wearing %s." % item["name"]
	TownState.save()
	_rebuild()

# --- Building blocks -----------------------------------------------------------------------------------------------------

func _text(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(label)

func _add_gap(pixels: int) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, pixels)
	_box.add_child(gap)

func _row(text: String, button_text: String, disabled: bool, action: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var button := UiTheme.button(button_text, 150.0)
	button.disabled = disabled
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(action)
	row.add_child(button)
	_box.add_child(row)

## An item as a picture over its button. Pointing at the picture shows the details and how it compares with what is worn; with a
## controller the button's focus shows the same details in the line at the foot of the panel.
func _item_card(item: Dictionary, button_text: String, disabled: bool, action: Callable) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	var tile: ItemTile = ItemTile.create(item, TownState.gear.get(int(item["slot"])), 84.0)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(tile)
	column.add_child(ItemTile.name_label(item, TownState.gear.get(int(item["slot"]))))
	var button := UiTheme.button(button_text, 110.0)
	button.disabled = disabled
	button.pressed.connect(action)
	ItemTile.decorate_button(button, item, TownState.gear.get(int(item["slot"])))
	column.add_child(button)
	return column

func _set_detail(item: Dictionary) -> void:
	if _detail != null:
		_detail.text = "%s (%s %s):  %s" % [item["name"], Items.RARITY_NAMES[int(item["rarity"])], Items.SLOT_NAMES[int(item["slot"])],
			"  ".join(Items.lines(item))]
		_detail.add_theme_color_override("font_color", Items.RARITY_COLORS[int(item["rarity"])])
