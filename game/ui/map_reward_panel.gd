class_name MapRewardPanel
extends PanelContainer
## Map mode's reward screen after a clear (issue #87): a panel docked to one side of the reopened map (never over the party), not modal. A header
## (the node's name and its chest's icon), the gold and potions with a quick count-up, and every item as a tile: its icon on a rarity frame with a
## glow, its name in the rarity colour, its slot, its one most important line (a legendary's effect in full on an orange band, else the trait, else
## the best modifier) and a verdict badge. Hovering or focusing a tile shows the shared item card (ItemTile.focus_card, #85). Nothing is worn by picking it up: an "Equip on" selector
## (one button per member) says who the verdicts, cards and Equip are for, and Equip wears the item on that member only (PlayerStats.equip_from_bag). Continue closes it (Space, or A
## while it has the controller focus); picking the next node fades it. The verdict is the shared comparison (Items.hero_can_wear, LootAppraisal.trend,
## Items.compare), never a copy of it.

signal continued()
signal equipped(item: Dictionary, member_id: String)
signal member_selected(member_id: String)

## WORN: worn by the selected member. WORN_OTHER: worn by the other one. CONFLICT: wearable, but it would push the other hand's piece off (a
## two-handed weapon over a shield, or the reverse).
enum State { WORN, UPGRADE, SIDEGRADE, DOWNGRADE, LOCKED, FULL, CONFLICT, WORN_OTHER }

const MEMBERS: Array[String] = ["hero", "cutter"]   # the party, in selector order
const MEMBER_COLORS := {"hero": Color(0.96, 0.78, 0.26), "cutter": Color(0.32, 0.82, 0.78)}   # gold and teal (no shared party colours exist yet)
const EQUIP_WIDTH := 132.0

const WIDTH := 470.0
const MARGIN := 16.0
const TOP := 24.0
const ICON := 56.0
const ICON_LEGENDARY := 80.0
const GREEN := Color(0.52, 0.93, 0.52)
const AMBER := Color(1.0, 0.80, 0.28)
const RED := ItemTile.UNMET_COLOR
const NEUTRAL := ItemTile.TEXT_COLOR
const DIM := ItemTile.MET_NEUTRAL
const LEGENDARY := ItemTile.LEGENDARY_COLOR
const COUNT_SECONDS := 0.8
const FADE_SECONDS := 0.35

var title: String = ""
var guard: String = ""
var bodies: Array = []
var items: Array = []        # the tally's items, in order
var gold: int = 0
var potions: int = 0
var tiles: Array[Dictionary] = []   # [{item, info, panel, icon, equip, badge}] what is on the panel now
var continue_button: Button
var selected: String = "hero"                    # the member every verdict, card and Equip on this panel is for; picking one never wears anything
var selector_buttons: Dictionary = {}            # member id -> Button
var equipped_log: Dictionary = {}                # item key -> {member, replaced}: what Equip did on this panel
var side: String = "right"
var subject: Dictionary = {}                     # the item the selector buttons summarise: the hovered or focused one, the first by default
var expanded_key: String = ""                    # the tile opened to its full details (one at a time)
var selector_summaries: Dictionary = {}          # member id -> RichTextLabel
var _selector_note: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _gold_label: Label
var _potion_label: Label
var _gold_shown: float = 0.0
var _potions_shown: float = 0.0
var _focus_index: int = -1
var _closing: bool = false
var _avoid: Array[Vector2] = []
var _last_screen := Vector2.ZERO

# ---- the verdict (pure: used by the panel and by the selftests) --------------------------------------------------------------------------------

## What the party can do with `item` now (it is worn, in the shared bag or left on the ground): {state, who, member, body, place, bag_index, need}.
## It is the shared comparison and nothing else: Items.hero_can_wear (can they wear it), LootAppraisal.trend (the item card's own better / same /
## worse), Items.requirement_card_text (what is lacking). `who` is the member's display name; `place` is where Equip puts it.
static func classify(item: Dictionary, party: Array) -> Dictionary:
	var key: String = MapAutoGear.key_of(item)
	for body in party:
		var b := body as Player
		if b == null or not is_instance_valid(b) or b.stats == null:
			continue
		for place in b.stats.equipment:
			if MapAutoGear.key_of(b.stats.equipment[place]) == key:
				return {"state": State.WORN, "who": b.display_name, "member": b.member_id, "body": b, "place": int(place), "bag_index": -1, "need": ""}
	var index: int = -1
	for body in party:
		var b := body as Player
		if b != null and is_instance_valid(b) and b.stats != null:
			for i in b.stats.bag.size():
				if MapAutoGear.key_of(b.stats.bag[i]) == key:
					index = i
			break   # the bag is the party's one backpack
	if index < 0:
		return {"state": State.FULL, "who": "", "member": "", "body": null, "place": -1, "bag_index": -1, "need": ""}
	var best_trend: int = -9
	var best: Player = null
	var need: String = ""
	var need_member: String = ""
	for body in party:
		var b := body as Player
		if b == null or not is_instance_valid(b) or b.stats == null:
			continue
		if not Items.hero_can_wear(item, b.member_id):
			var text: String = Items.requirement_card_text(item, b.member_id)
			if need == "" or text.length() < need.length():
				need = text
				need_member = b.member_id
			continue
		var t: int = LootAppraisal.trend(item, b.stats)
		var hc: int = b.stats._hand_conflict(item)
		if t > 0 and hc >= 0 and b.stats.equipment.has(hc):
			t = 0   # a two-handed weapon would take the shield off (or the reverse): not a plain upgrade (as the autoplay's MapAutoGear)
		if t > best_trend:
			best_trend = t
			best = b
	if best == null:
		return {"state": State.LOCKED, "who": need_member, "member": need_member, "body": null, "place": -1, "bag_index": index, "need": need.replace("Requires ", "Needs ")}
	var state: int = State.UPGRADE if best_trend > 0 else (State.SIDEGRADE if best_trend == 0 else State.DOWNGRADE)
	var place: int = _best_place(item, best)
	return {"state": state, "who": best.display_name, "member": best.member_id, "body": best, "place": place, "bag_index": index, "need": ""}

## The party member with this id (the first member when none matches, so a one-member party still works).
static func member_body(party: Array, member_id: String) -> Player:
	var first: Player = null
	for body in party:
		var b := body as Player
		if b == null or not is_instance_valid(b) or b.stats == null:
			continue
		if b.member_id == member_id:
			return b
		if first == null:
			first = b
	return first

## What `item` is for ONE member (the selector's choice), same fields as classify: worn by them (WORN) or by the other (WORN_OTHER), in the bag
## and unwearable by them (LOCKED, `need` says what is lacking; "Can't use" when nobody can), or wearable: UPGRADE / SIDEGRADE / DOWNGRADE by the
## shared comparison, CONFLICT when it would push the other hand's piece off. `place` is where Equip puts it on them.
static func classify_for(item: Dictionary, party: Array, member_id: String) -> Dictionary:
	var sel: Player = member_body(party, member_id)
	var key: String = MapAutoGear.key_of(item)
	for body in party:
		var b := body as Player
		if b == null or not is_instance_valid(b) or b.stats == null:
			continue
		for place in b.stats.equipment:
			if MapAutoGear.key_of(b.stats.equipment[place]) == key:
				return {"state": State.WORN if b == sel else State.WORN_OTHER, "who": b.display_name, "member": b.member_id, "body": b, "place": int(place), "bag_index": -1, "need": ""}
	var index: int = -1
	if sel != null:
		for i in sel.stats.bag.size():   # (the bag is the party's one backpack)
			if MapAutoGear.key_of(sel.stats.bag[i]) == key:
				index = i
	if index < 0 or sel == null:
		return {"state": State.FULL, "who": "", "member": "", "body": null, "place": -1, "bag_index": -1, "need": ""}
	if not Items.hero_can_wear(item, sel.member_id):
		var nobody: bool = true
		for body in party:
			var b := body as Player
			if b != null and is_instance_valid(b) and b != sel and Items.hero_can_wear(item, b.member_id):
				nobody = false
		var need: String = Items.requirement_card_text(item, sel.member_id).replace("Requires ", "Needs ")
		return {"state": State.LOCKED, "who": sel.display_name, "member": sel.member_id, "body": sel, "place": -1, "bag_index": index, "need": ("Can't use: " + need) if nobody else need}
	var place: int = _best_place(item, sel)
	var hc: int = sel.stats._hand_conflict(item)
	var state: int
	var slot_name: String = ""
	if hc >= 0 and sel.stats.equipment.has(hc):
		state = State.CONFLICT
		slot_name = String(Items.SLOT_NAMES[hc])
	else:
		var t: int = LootAppraisal.trend(item, sel.stats)
		state = State.UPGRADE if t > 0 else (State.SIDEGRADE if t == 0 else State.DOWNGRADE)
	return {"state": state, "who": sel.display_name, "member": sel.member_id, "body": sel, "place": place, "bag_index": index, "need": "", "displaces": slot_name}

## Whether Equip is offered for this verdict (any wearable item in the bag; the verdict is advice, the player decides).
static func can_equip(info: Dictionary) -> bool:
	return int(info["state"]) in [State.UPGRADE, State.SIDEGRADE, State.DOWNGRADE, State.CONFLICT]

## The member the clear is best for: the one who gains the most upgrades from the items (the shared trend), the warrior on a tie. Selecting it
## wears nothing.
static func default_member(items: Array, party: Array) -> String:
	var best_id: String = MEMBERS[0]
	var best_count: int = -1
	for id in MEMBERS:
		var b: Player = null
		for body in party:
			var c := body as Player
			if c != null and is_instance_valid(c) and c.stats != null and c.member_id == id:
				b = c
		if b == null:
			continue
		var count: int = 0
		for item in items:
			if Items.hero_can_wear(item, id) and LootAppraisal.trend(item, b.stats) > 0:
				count += 1
		if count > best_count:
			best_count = count
			best_id = id
	return best_id

## The place of the item's slot where it beats what is worn by most on the item card's own comparison (a free place first).
static func _best_place(item: Dictionary, body: Player) -> int:
	var best_place: int = Items.places(int(item["slot"]))[0]
	var best_balance: int = -9999
	for place in Items.places(int(item["slot"])):
		var balance: int = int(MapAutoGear.verdict(item, body, place)["balance"])
		if balance > best_balance:
			best_balance = balance
			best_place = place
	return best_place

## The tile's STATE badge: {text, color}; text is "" when there is none. The verdict (upgrade / sidegrade / downgrade / cannot use) is not a badge:
## it is the headline on each member's selector button and the two small marks on the tile.
static func badge_of(info: Dictionary) -> Dictionary:
	match int(info["state"]):
		State.UPGRADE, State.SIDEGRADE, State.DOWNGRADE, State.LOCKED: return {"text": "", "color": NEUTRAL}
		State.FULL: return {"text": "Inventory full", "color": AMBER}
		State.CONFLICT: return {"text": "Replaces %s" % String(info.get("displaces", "")), "color": AMBER}
	if bool(info.get("fresh", false)):
		return {"text": "Equipped on %s" % String(info["who"]), "color": GREEN}
	return {"text": "Worn by %s" % String(info["who"]), "color": NEUTRAL}

const SOFT_RED := Color(0.95, 0.5, 0.42)

## The cross for "this member cannot use it": a heavy X when the UI font has it, else a multiplication sign.
static func cross() -> String:
	var font: Font = UiTheme.get_theme().default_font
	return "\u2715" if font != null and font.has_char(0x2715) else "\u00d7"

## Which stat is an item's HEADLINE on a selector button. The rule, by slot:
##   weapon (it has a damage range)            -> "damage"
##   anything with armor (body, helm, gloves, boots, shield) -> "armor"
##   everything else (ring, amulet, ...)       -> its best modifier: the first modifier line of the card (Items.rows, section "mods"); "" if none.
static func headline_key(item: Dictionary) -> String:
	var stats: Dictionary = item["stats"]
	if stats.has("max"):
		return "damage"
	if stats.has("armor"):
		return "armor"
	for row in Items.rows(item):
		if String(row["section"]) == "mods" and String(row["key"]) != "":
			return String(row["key"])
	return ""

## What `item` would do for one member, as ONE headline: {sign, text, plain, usable, worn, need}. The number is the shared comparison's own line
## (Items.compare against what that member wears where it would go: the better ring place); with an empty slot it is the item's own card row.
## `text` is e.g. "▲ Damage +12.0", "▼ Armor -4", "= Damage"; `plain` adds the cross in front when the member cannot use it (the change is still worked
## out as if they could). A piece the member already wears reads "Worn".
static func headline(item: Dictionary, body: Player) -> Dictionary:
	var usable: bool = Items.hero_can_wear(item, body.member_id)
	var need: String = "" if usable else Items.requirement_card_text(item, body.member_id).replace("Requires ", "Needs ")
	var out := {"sign": 0, "text": "", "plain": "", "usable": usable, "worn": false, "need": need}
	var key: String = MapAutoGear.key_of(item)
	for place in body.stats.equipment:
		if MapAutoGear.key_of(body.stats.equipment[place]) == key:
			out["worn"] = true
			out["text"] = "Worn"
			out["plain"] = "Worn"
			return out
	var hk: String = headline_key(item)
	var current: Variant = body.stats.equipment.get(_best_place(item, body))
	var text: String = ""
	var sign: int = 0
	if current == null:
		sign = 1   # nothing worn there: it is all gain, shown as the item's own number
		for row in Items.rows(item, body.member_id):
			if String(row["key"]) != hk or hk == "":
				continue
			var line: String = String(row["text"])
			if hk == "damage":
				var avg := RegEx.create_from_string("avg ([0-9.]+)").search(line)
				text = "Damage +%s" % (avg.get_string(1) if avg != null else "")
			elif hk == "armor":
				text = "Armor +%s" % line.get_slice(" ", 1)
			else:
				text = line
			break
	else:
		for line in Items.compare(item, current, body.member_id):
			if String(line["key"]) != hk or hk == "":
				continue
			var stat_text: String = String(line["stat_text"]) if line.has("stat_text") else String(line["text"])
			var label: String = stat_text.substr(0, stat_text.rfind(" "))
			sign = int(line["sign"])
			text = "%s %s%s" % [label, "+" if sign > 0 else "-", String(line["delta"]).substr(2)]
			break
		if text == "":   # no difference in the headline stat
			text = {"damage": "Damage", "armor": "Armor"}.get(hk, "Same")
	var arrow: String = Items.UP if sign > 0 else (Items.DOWN if sign < 0 else "=")
	out["sign"] = sign
	out["text"] = "%s %s" % [arrow, text]
	out["plain"] = ("%s " % cross() if not usable else "") + String(out["text"])
	return out

static func headline_color(head: Dictionary) -> Color:
	if bool(head["worn"]):
		return DIM
	return GREEN if int(head["sign"]) > 0 else (SOFT_RED if int(head["sign"]) < 0 else DIM)

## The headline as BBCode for a label: a red cross (cannot use) and the change in its colour.
static func headline_bbcode(head: Dictionary) -> String:
	var out: String = ""
	if not bool(head["usable"]):
		out += "[color=#%s]%s[/color] " % [RED.to_html(false), cross()]
	return out + "[color=#%s]%s[/color]" % [headline_color(head).to_html(false), String(head["text"])]

## An item's one most important line: a legendary's effect, else its map-mode trait, else its best (first) modifier, else its base stat.
static func key_line(item: Dictionary, member_id: String) -> Dictionary:
	var id: String = MapModeLegendaries.id_of(item)
	if id != "":
		return {"text": "Legendary: %s" % String(MapModeLegendaries.DEFS[id]["text"]), "section": "legendary"}
	var rows: Array[Dictionary] = ItemTile.display_rows(item, [], member_id)   # the card's own lines (the one builder), not a second reading of the item
	for section in ["trait", "mods", "base"]:
		for row in rows:
			if String(row["section"]) == section:
				return {"text": String(row["text"]), "section": section}
	return {"text": "", "section": ""}

# ---- building -----------------------------------------------------------------------------------------------------------------------------------

## `party` are the bodies (warrior, Cutter); `tally` is the clear's {gold, health, mana, items}.
static func create(for_title: String, for_guard: String, tally: Dictionary, party: Array) -> MapRewardPanel:
	var panel := MapRewardPanel.new()
	panel.title = for_title
	panel.guard = for_guard
	panel.bodies = party
	panel.gold = int(tally.get("gold", 0))
	panel.potions = int(tally.get("health", 0)) + int(tally.get("mana", 0))
	panel.items = (tally.get("items", []) as Array).duplicate()
	var first: Player = member_body(party, default_member(panel.items, party))
	panel.selected = first.member_id if first != null else "hero"
	return panel

func _ready() -> void:
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	var plate := UiTheme.panel_box()
	plate.content_margin_left = 22
	plate.content_margin_right = 22
	plate.content_margin_top = 20
	plate.content_margin_bottom = 20
	add_theme_stylebox_override("panel", plate)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.add_child(_header())
	root.add_child(_currency())
	if bodies.size() > 1:
		root.add_child(_selector())
	root.add_child(_divider())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.custom_minimum_size.x = _inner_width() - 14.0
	_scroll.add_child(_list)
	root.add_child(_divider())
	root.add_child(_footer())
	_fill()
	modulate.a = 0.0
	await get_tree().process_frame   # (the layout of the tiles is only known after a frame)
	if _closing:
		return
	_fit()
	await get_tree().process_frame   # (measured again once laid out: the first pass over-counts wrapped text)
	if _closing:
		return
	_fit()
	_count_up()

func _inner_width() -> float:
	return WIDTH - 44.0

func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var glyph := Glyph.new("chest:" + guard, MapDrops.guard_color(guard))
	glyph.custom_minimum_size = Vector2(54, 46)
	row.add_child(glyph)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = title if title != "" else "Cleared"
	name_label.add_theme_font_override("font", UiTheme.heading_font())
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = _inner_width() - 66.0
	text.add_child(name_label)
	var kind := Label.new()
	var def: Dictionary = (MapDrops.T.guards as Dictionary).get(guard, {})
	kind.text = String(def.get("title", "Cleared")) if guard != "" else "Cleared"
	kind.add_theme_font_size_override("font_size", 15)
	kind.add_theme_color_override("font_color", MapDrops.guard_color(guard).lightened(0.25))
	text.add_child(kind)
	return row

func _currency() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	var gold_box := HBoxContainer.new()
	gold_box.add_theme_constant_override("separation", 7)
	var coin := Glyph.new("gold", Color(0.96, 0.78, 0.26))
	coin.custom_minimum_size = Vector2(26, 26)
	gold_box.add_child(coin)
	_gold_label = _count_label()
	gold_box.add_child(_gold_label)
	row.add_child(gold_box)
	if potions > 0:
		var potion_box := HBoxContainer.new()
		potion_box.add_theme_constant_override("separation", 7)
		var flask := Glyph.new("potion", Color(0.86, 0.22, 0.2))
		flask.custom_minimum_size = Vector2(26, 26)
		potion_box.add_child(flask)
		_potion_label = _count_label()
		potion_box.add_child(_potion_label)
		row.add_child(potion_box)
	return row

## "Equip on": one button per party member (portrait, name in the member's colour, and under it the HEADLINE of what the subject item would do
## for them), exactly one selected, and a line saying who the panel is for. Everything below it (cards, Equip) reads for the selected member.
func _selector() -> Control:
	var box := VBoxContainer.new()
	box.name = "Selector"
	box.add_theme_constant_override("separation", 4)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	box.add_child(head_row)
	var caption := Label.new()
	caption.text = "Equip on"
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", ItemTile.HINT_COLOR)
	head_row.add_child(caption)
	_selector_note = Label.new()
	_selector_note.name = "Note"
	_selector_note.add_theme_font_size_override("font_size", 14)
	_selector_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(_selector_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for id in MEMBERS:
		var body: Player = member_body(bodies, id)
		if body == null or body.member_id != id:
			continue
		var button := Button.new()
		button.name = "Member_" + id
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE   # LB / RB, Left / Right, Tab and 1 / 2 switch it
		button.clip_contents = true
		button.pressed.connect(select_member.bind(id))
		var inner := HBoxContainer.new()
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("separation", 8)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 8
		inner.offset_right = -6
		button.add_child(inner)
		var portrait := TextureRect.new()
		portrait.texture = Ds2PartyFrame.KNIGHT_PORTRAIT if id == "hero" else Ds2PartyFrame.ARCHER_PORTRAIT
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(40, 0)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(portrait)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(col)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = body.display_name
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(name_label)
		var summary := RichTextLabel.new()
		summary.name = "Summary"
		summary.bbcode_enabled = true
		summary.fit_content = false
		summary.scroll_active = false
		summary.autowrap_mode = TextServer.AUTOWRAP_OFF
		summary.clip_contents = true
		summary.custom_minimum_size = Vector2(10, 20)
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary.add_theme_font_size_override("normal_font_size", 15)
		col.add_child(summary)
		row.add_child(button)
		selector_buttons[id] = button
		selector_summaries[id] = summary
	_refresh_selector()
	return box

func _refresh_selector() -> void:
	for id in selector_buttons:
		var colour: Color = MEMBER_COLORS.get(id, NEUTRAL)
		var on: bool = id == selected
		var button: Button = selector_buttons[id]
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(colour.r * 0.34, colour.g * 0.34, colour.b * 0.34, 0.98) if on else Color(0.07, 0.06, 0.05, 0.96).lerp(Color(colour.r * 0.25, colour.g * 0.25, colour.b * 0.25, 0.96), 0.35 if state.begins_with("hover") else 0.0)
			style.border_color = colour if on else colour.darkened(0.55)
			style.set_border_width_all(4 if on else 1)
			style.set_corner_radius_all(5)
			button.add_theme_stylebox_override(state, style)
		(button.find_child("Name", true, false) as Label).add_theme_color_override("font_color", colour.lightened(0.45) if on else colour.darkened(0.2))
		button.modulate = Color.WHITE if on else Color(0.8, 0.8, 0.8)
	if _selector_note != null:
		var body: Player = member_body(bodies, selected)
		_selector_note.text = "for %s" % (body.display_name if body != null else selected)
		_selector_note.add_theme_color_override("font_color", (MEMBER_COLORS.get(selected, NEUTRAL) as Color).lightened(0.25))
	_refresh_summaries()

## The headline of the subject item on each member's button (and its tooltip: the full line, with the requirement when they cannot use it).
func _refresh_summaries() -> void:
	for id in selector_summaries:
		var summary: RichTextLabel = selector_summaries[id]
		var button: Button = selector_buttons[id]
		var body: Player = member_body(bodies, id)
		if subject.is_empty() or body == null:
			summary.text = ""
			button.tooltip_text = ""
			continue
		var head: Dictionary = headline(subject, body)
		summary.text = headline_bbcode(head)
		button.tooltip_text = "%s: %s%s" % [body.display_name, String(head["plain"]), ("\n%s" % String(head["need"])) if String(head["need"]) != "" else ""]

## The item the buttons summarise (hover and controller focus move it; it stays on the last one).
func set_subject(item: Dictionary) -> void:
	if not subject.is_empty() and MapAutoGear.key_of(subject) == MapAutoGear.key_of(item):
		return
	subject = item
	_refresh_summaries()

## Makes `member_id` the member the whole panel is for. It only changes what is shown and who Equip targets; nothing is worn or moved.
func select_member(member_id: String) -> void:
	if member_id == selected or member_body(bodies, member_id) == null or member_body(bodies, member_id).member_id != member_id:
		return
	selected = member_id
	_refresh_selector()
	_rebuild()
	member_selected.emit(member_id)

## The next (or previous) member in the party's order, wrapping.
func cycle_member(step: int) -> void:
	var ids: Array[String] = []
	for id in MEMBERS:
		var b: Player = member_body(bodies, id)
		if b != null and b.member_id == id:
			ids.append(id)
	if ids.size() < 2:
		return
	select_member(ids[posmod(ids.find(selected) + step, ids.size())])

func _count_label() -> Label:
	var label := Label.new()
	label.text = "0"
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.98, 0.9, 0.62))
	return label

func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "LB / RB member   Y items   A equip" if Gamepad.active else "Tab / 1 / 2 member   hover an item for its card"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 120.0
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", ItemTile.HINT_COLOR)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	continue_button = Button.new()
	continue_button.text = "Continue  (A)" if Gamepad.active else "Continue  (Space)"
	continue_button.custom_minimum_size = Vector2(150, 34)
	continue_button.focus_mode = Control.FOCUS_ALL
	continue_button.pressed.connect(close)
	row.add_child(continue_button)
	return row

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = ItemTile.DIVIDER_COLOR
	line.custom_minimum_size = Vector2(0, 1)
	return line

## (Re)builds every tile from what the party wears and carries now.
func _fill() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	tiles.clear()
	if items.is_empty():
		var none := Label.new()
		none.text = "No items this time"
		none.add_theme_font_size_override("font_size", 16)
		none.add_theme_color_override("font_color", NEUTRAL)
		_list.add_child(none)
		subject = {}
		_refresh_summaries()
		return
	if subject.is_empty() or not items.any(func(i: Dictionary) -> bool: return MapAutoGear.key_of(i) == MapAutoGear.key_of(subject)):
		subject = items[0]
	for item in items:
		var entry: Dictionary = _tile(item)
		tiles.append(entry)
		_list.add_child(entry["panel"])
	_refresh_summaries()

func _tile(item: Dictionary) -> Dictionary:
	var info: Dictionary = classify_for(item, bodies, selected)
	var done: Dictionary = equipped_log.get(MapAutoGear.key_of(item), {})
	if not done.is_empty() and int(info["state"]) == State.WORN and String(info["member"]) == String(done["member"]):
		info["fresh"] = true   # worn through Equip on this panel: "Equipped on X", and what it replaced
	var legendary: bool = MapModeLegendaries.id_of(item) != ""
	var rarity: int = int(item["rarity"])
	var colour: Color = LEGENDARY if legendary else Items.RARITY_COLORS[rarity]
	var strong: bool = legendary or rarity >= Items.Rarity.UNIQUE
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _tile_style(colour, rarity, legendary, false))
	var key: String = MapAutoGear.key_of(item)
	var is_open: bool = expanded_key == key
	var body: Player = info["body"] as Player
	var member: String = selected
	var worn: Variant = null
	if body != null and int(info["place"]) >= 0 and int(info["state"]) not in [State.WORN, State.WORN_OTHER]:
		worn = body.stats.equipment.get(int(info["place"]))
	var icon_px: float = ICON_LEGENDARY if legendary else ICON
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	panel.add_child(stack)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	stack.add_child(row)
	var icon := IconBox.new(item, worn, icon_px, colour, member, not is_open)   # (an opened tile shows its card in place, not as a popup)
	icon.focus_entered.connect(set_subject.bind(item))
	icon.mouse_entered.connect(set_subject.bind(item))
	panel.mouse_entered.connect(set_subject.bind(item))
	icon.gui_input.connect(_tile_clicked.bind(item))
	panel.gui_input.connect(_tile_clicked.bind(item))
	icon.focus_entered.connect(func() -> void: panel.add_theme_stylebox_override("panel", _tile_style(colour, rarity, legendary, true)))
	icon.focus_exited.connect(func() -> void: panel.add_theme_stylebox_override("panel", _tile_style(colour, rarity, legendary, false)))
	row.add_child(icon)
	var text_width: float = _inner_width() - 14.0 - icon_px - 10.0 - 24.0
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	col.add_child(_wrapped(String(item["name"]), 18 if legendary else 17, colour.lightened(0.18), text_width))
	# slot on the left, the verdict badge on the right of one row
	var kind_row := HBoxContainer.new()
	kind_row.add_theme_constant_override("separation", 8)
	col.add_child(kind_row)
	var slot_label := _wrapped("%s %s" % [Items.rarity_label(item), Items.SLOT_NAMES[int(item["slot"])]], 14, colour.lightened(0.3) if strong else NEUTRAL, 0.0)
	slot_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	slot_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind_row.add_child(slot_label)
	kind_row.add_child(_marks(item))
	var badge: Dictionary = badge_of(info)
	var badge_panel: Control = null
	if String(badge["text"]) != "":
		badge_panel = _badge(String(badge["text"]), badge["color"])
		badge_panel.name = "Badge"
		kind_row.add_child(badge_panel)
	# the item's one important line (a legendary's effect in full on its band), with Equip at the end of it for an upgrade
	var line: Dictionary = key_line(item, member)
	var equip: Button = null
	var other_wears: bool = int(info["state"]) == State.WORN_OTHER
	var cannot_use: bool = int(info["state"]) == State.LOCKED
	if can_equip(info) or other_wears or cannot_use:
		equip = Button.new()
		equip.name = "Equip"
		equip.text = "Equip on %s" % _display(selected)
		equip.custom_minimum_size = Vector2(EQUIP_WIDTH, 30)
		if other_wears:
			equip.disabled = true
			equip.tooltip_text = "Worn by %s. Take it off there first." % String(info["who"])
		elif cannot_use:
			equip.disabled = true
			equip.tooltip_text = "%s cannot use it: %s" % [String(info["who"]), String(info["need"])]
		equip.focus_mode = Control.FOCUS_ALL if (is_open and not equip.disabled) else Control.FOCUS_NONE   # the controller selects the tile; A opens it, then A on Equip wears it
		equip.pressed.connect(_equip.bind(item))
	var line_row := HBoxContainer.new()
	line_row.add_theme_constant_override("separation", 8)
	col.add_child(line_row)
	if bool(info.get("fresh", false)) and String(done.get("replaced", "")) != "":
		var was := _wrapped("Replaced %s (now in the bag)" % String(done["replaced"]), 15, DIM, 0.0)
		was.autowrap_mode = TextServer.AUTOWRAP_OFF
		was.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		was.custom_minimum_size.x = 60.0
		was.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_row.add_child(was)
	elif String(line["text"]) != "":
		if String(line["section"]) == "legendary":
			var band: Control = _effect_band(String(line["text"]), text_width - (EQUIP_WIDTH + 8.0 if equip != null else 0.0))
			band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line_row.add_child(band)
		else:
			var label := _wrapped(String(line["text"]), 15, ItemTile.MOD_COLOR if String(line["section"]) == "mods" else NEUTRAL, 0.0)
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.custom_minimum_size.x = 60.0
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line_row.add_child(label)
	else:
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line_row.add_child(pad)
	if equip != null:
		equip.size_flags_vertical = Control.SIZE_SHRINK_END
		line_row.add_child(equip)
	if is_open:   # the shared item card in place, its compare lines against what the SELECTED member wears there
		var card: Control = ItemTile.card(item, worn, true, false, "", Color(0, 0, 0, 0), member)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.name = "Details"
		stack.add_child(card)
	return {"item": item, "info": info, "panel": panel, "icon": icon, "equip": equip, "badge": badge_panel, "open": is_open}

## The two small marks on a tile, one per member in the member's colour: the headline's arrow (green up, red down, grey equal), a red cross when
## they cannot use it, a check when they already wear it. Hovering one gives the full headline.
func _marks(item: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.name = "Marks"
	box.add_theme_constant_override("separation", 8)
	for id in MEMBERS:
		var body: Player = member_body(bodies, id)
		if body == null or body.member_id != id:
			continue
		var head: Dictionary = headline(item, body)
		var chip := HBoxContainer.new()
		chip.name = "Mark_" + id
		chip.add_theme_constant_override("separation", 3)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = "%s: %s%s" % [body.display_name, String(head["plain"]), ("\n%s" % String(head["need"])) if String(head["need"]) != "" else ""]
		var dot := ColorRect.new()
		dot.color = MEMBER_COLORS.get(id, NEUTRAL)
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(dot)
		var glyph := Label.new()
		glyph.name = "Glyph"
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.add_theme_font_size_override("font_size", 14)
		if bool(head["worn"]):
			glyph.text = "\u2713"
			glyph.add_theme_color_override("font_color", DIM)
		elif not bool(head["usable"]):
			glyph.text = cross()
			glyph.add_theme_color_override("font_color", RED)
		else:
			glyph.text = String(head["text"]).substr(0, 1)
			glyph.add_theme_color_override("font_color", headline_color(head))
		chip.add_child(glyph)
		box.add_child(chip)
	return box

## Opens the tile in place to the full details, or closes it again (one open at a time).
func toggle_expand(item: Dictionary) -> void:
	var key: String = MapAutoGear.key_of(item)
	expanded_key = "" if expanded_key == key else key
	_rebuild()

func _tile_clicked(event: InputEvent, item: Dictionary) -> void:
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		toggle_expand(item)
		accept_event()

func _tile_style(colour: Color, rarity: int, legendary: bool, focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.036, 0.97).lerp(Color(colour.r * 0.2, colour.g * 0.16, colour.b * 0.1, 0.97), 0.55 if legendary else 0.0)
	style.border_color = colour.lightened(0.25 if focused else 0.0) if (rarity > 0 or legendary) else Color(0.5, 0.46, 0.4)
	style.set_border_width_all(4 if focused else (3 if legendary else 2))
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	if legendary or rarity >= Items.Rarity.RARE or focused:
		style.shadow_color = Color(colour.r, colour.g, colour.b, 0.6 if legendary else 0.32)
		style.shadow_size = 14 if legendary else 6
	return style

func _wrapped(text: String, size: int, colour: Color, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
	return label

## The legendary effect, in full, on the warm band the item card gives it.
func _effect_band(text: String, width: float) -> Control:
	var band := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(LEGENDARY.r, LEGENDARY.g, LEGENDARY.b, 0.18)
	style.border_color = LEGENDARY
	style.border_width_left = 3
	style.set_content_margin_all(6)
	style.content_margin_left = 9
	band.add_theme_stylebox_override("panel", style)
	band.add_child(_wrapped(text, 16, Color(1.0, 0.86, 0.6), width - 16.0))
	return band

func _badge(text: String, colour: Color) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colour.r * 0.2, colour.g * 0.2, colour.b * 0.2, 0.96)
	style.border_color = colour
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", colour.lightened(0.15))
	panel.add_child(label)
	return panel

# ---- layout: docked to a side, clear of the party, sized to the safe area -----------------------------------------------------------------------

## The screen area the panel may use: below the top margin, above the hotbar and both vessels.
static func safe_rect(hud: Hud, screen: Vector2) -> Rect2:
	var bottom: float = minf(screen.y - MARGIN, minf(Hud.orb_rect(screen, false).position.y, Hud.orb_rect(screen, true).position.y) - 8.0)
	bottom = minf(bottom, hud.hotbar_rect(screen).position.y - 8.0)
	return Rect2(Vector2(MARGIN, TOP), Vector2(screen.x - MARGIN * 2.0, maxf(bottom - TOP, 120.0)))

## Where a panel of `panel_size` goes: the right edge, else the left edge under the party cards, whichever keeps clear of every point in `avoid`
## (the party's screen positions, with `clear` pixels round each). Returns {rect, side}.
static func dock(panel_size: Vector2, safe: Rect2, avoid: Array[Vector2], left_top: float, clear: float = 70.0) -> Dictionary:
	var right := Rect2(Vector2(safe.end.x - panel_size.x, safe.position.y), panel_size)
	var left := Rect2(Vector2(safe.position.x, maxf(safe.position.y, left_top)), panel_size)
	for candidate in [[right, "right"], [left, "left"]]:
		var rect: Rect2 = (candidate[0] as Rect2)
		var clear_of_party: bool = true
		for point in avoid:
			if rect.grow(clear).has_point(point):
				clear_of_party = false
		if clear_of_party:
			return {"rect": rect, "side": candidate[1]}
	return {"rect": right, "side": "right"}

func _party_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return out
	for body in bodies:
		var b := body as Node3D
		if b == null or not is_instance_valid(b) or camera.is_position_behind(b.global_position):
			continue
		out.append(camera.unproject_position(b.global_position))
		out.append(camera.unproject_position(b.global_position + Vector3(0, 1.8, 0)))
	return out

## Sizes the panel to its tiles (a scroll when they exceed the height it may have) and docks it.
func _fit() -> void:
	var hud := get_parent() as Hud
	var screen: Vector2 = get_viewport_rect().size
	_last_screen = screen
	var safe: Rect2 = safe_rect(hud, screen) if hud != null else Rect2(Vector2(MARGIN, TOP), screen - Vector2(MARGIN * 2.0, 200.0))
	_scroll.custom_minimum_size.y = 0.0
	var chrome: float = get_combined_minimum_size().y
	var content: float = _list.get_combined_minimum_size().y
	custom_minimum_size.x = WIDTH
	var left_top: float = TOP
	if hud != null and is_instance_valid(hud.ds2_party_frame) and hud.ds2_party_frame.visible:
		left_top = hud.ds2_party_frame.get_global_rect().end.y + 10.0
	_avoid = _party_points()
	_set_height(minf(content, maxf(safe.size.y - chrome, 90.0)))
	var placed: Dictionary = dock(size, safe, _avoid, left_top)
	side = String(placed["side"])
	if side == "left":   # it starts lower, under the party cards: it gets what is left of the safe height
		_set_height(minf(content, maxf(safe.end.y - (placed["rect"] as Rect2).position.y - chrome, 90.0)))
	position = (placed["rect"] as Rect2).position
	_dock_x = position.x
	_reserve_map()

func _set_height(scroll_height: float) -> void:
	_scroll.custom_minimum_size.y = scroll_height
	size = Vector2(WIDTH, get_combined_minimum_size().y)

## The node map leaves the panel's strip free so every node stays visible and clickable.
func _reserve_map() -> void:
	var m: MapMode = MapMode.current
	if m == null or m.overlay == null:
		return
	m.overlay.reserve_right = (_last_screen.x - position.x + MARGIN * 0.5) if side == "right" else 0.0
	m.overlay.reserve_left = (position.x + size.x + MARGIN * 0.5) if side == "left" else 0.0
	m.overlay.yield_rect = Rect2(position, size)
	m.overlay.relayout()

func _release_map() -> void:
	var m: MapMode = MapMode.current
	if m != null and is_instance_valid(m) and m.overlay != null and is_instance_valid(m.overlay):
		m.overlay.reserve_right = 0.0
		m.overlay.reserve_left = 0.0
		m.overlay.yield_rect = Rect2()
		m.overlay.relayout()

## Where the panel rests (not mid-slide).
func rect() -> Rect2:
	return Rect2(Vector2(_dock_x, position.y), size)

var _dock_x: float = 0.0

# ---- count-up, fade, close -----------------------------------------------------------------------------------------------------------------------

func _count_up() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "_gold_shown", float(gold), COUNT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_potions_shown", float(potions), minf(COUNT_SECONDS, 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	modulate.a = 0.0
	var slide: float = 40.0 if side == "right" else -40.0
	var final_x: float = position.x
	_dock_x = final_x
	position.x += slide
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	tween.tween_property(self, "position:x", final_x, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	if _gold_label != null:
		_gold_label.text = str(int(round(_gold_shown)))
	if _potion_label != null:
		_potion_label.text = str(int(round(_potions_shown)))
	var screen: Vector2 = get_viewport_rect().size
	if screen != _last_screen and not _closing:
		_fit()

## What the count-up shows right now (tests).
func shown_counts() -> Vector2i:
	return Vector2i(int(round(_gold_shown)), int(round(_potions_shown)))

## Finishes the count-up at once (tests and screenshots).
func finish_count() -> void:
	_gold_shown = float(gold)
	_potions_shown = float(potions)
	modulate.a = 1.0
	_process(0.0)

func close() -> void:
	continued.emit()
	fade_out()

## Fades by itself (the next node was picked) or on Continue, then goes.
func fade_out() -> void:
	if _closing:
		return
	_closing = true
	_release_map()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(queue_free)

func _exit_tree() -> void:
	if not _closing:
		_release_map()

# ---- Equip --------------------------------------------------------------------------------------------------------------------------------------------

## Wears the item on the SELECTED member, through PlayerStats.equip_from_bag (the autoplay's own call); what it replaces goes to the bag. False
## when it cannot (not in the bag, not wearable by them, already worn, bag full).
func equip_item(item: Dictionary) -> bool:
	var info: Dictionary = classify_for(item, bodies, selected)
	if not can_equip(info):
		return false
	var body: Player = info["body"]
	var old: Variant = body.stats.equipment.get(int(info["place"]))
	if not body.stats.equip_from_bag(int(info["bag_index"]), int(info["place"])):
		return false
	equipped_log[MapAutoGear.key_of(item)] = {"member": body.member_id, "replaced": String(old["name"]) if old is Dictionary else ""}
	equipped.emit(item, body.member_id)
	return true

func _display(member_id: String) -> String:
	var b: Player = member_body(bodies, member_id)
	return b.display_name if b != null else member_id

func _equip(item: Dictionary) -> void:
	if equip_item(item):
		_rebuild()

## Builds the tiles again (another member was selected, or something was worn), keeping the scroll and the controller's tile.
func _rebuild() -> void:
	var keep: float = _scroll.scroll_vertical
	_fill()
	_scroll.scroll_vertical = int(keep)
	if _focus_index >= 0:
		_focus(_focus_index)
	if is_inside_tree() and not _closing:
		_fit.call_deferred()

# ---- input: LB / RB, Left / Right, Tab and 1 / 2 pick the member; Y enters the list, Up / Down pick a tile, A equips it or presses Continue; Space continues ---------------------------------

func _focus_targets() -> Array[Control]:
	var out: Array[Control] = []
	for entry in tiles:
		out.append(entry["icon"])
		var equip: Button = entry["equip"]
		if bool(entry["open"]) and equip != null and equip.focus_mode == Control.FOCUS_ALL:
			out.append(equip)
	out.append(continue_button)
	return out

func _focus(index: int) -> void:
	var targets: Array[Control] = _focus_targets()
	if targets.is_empty():
		return
	_focus_index = posmod(index, targets.size())
	targets[_focus_index].grab_focus()
	var entry: Control = targets[_focus_index]
	if entry.get_parent() != null:
		_scroll.ensure_control_visible(_tile_of(entry) if entry != continue_button else entry)

## The tile panel a focus target (its icon or its Equip button) belongs to.
func _tile_of(control: Control) -> Control:
	for entry in tiles:
		if entry["icon"] == control or entry["equip"] == control:
			return entry["panel"]
	return control

## After a tile opens, the controller focus moves to its Equip button when it has an enabled one.
func _focus_equip_of(item: Dictionary) -> void:
	var targets: Array[Control] = _focus_targets()
	for entry in tiles:
		if MapAutoGear.key_of(entry["item"]) == MapAutoGear.key_of(item) and entry["equip"] != null:
			var at: int = targets.find(entry["equip"])
			if at >= 0:
				_focus(at)

func _owns_focus() -> bool:
	var owner: Control = get_viewport().gui_get_focus_owner()
	return owner != null and is_ancestor_of(owner)

func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree():
		return
	if event is InputEventJoypadButton and event.pressed:
		var button: int = (event as InputEventJoypadButton).button_index
		if button == JOY_BUTTON_LEFT_SHOULDER or button == JOY_BUTTON_RIGHT_SHOULDER:
			cycle_member(-1 if button == JOY_BUTTON_LEFT_SHOULDER else 1)   # who the panel is for (nothing is worn)
			get_viewport().set_input_as_handled()
			return
		if button == JOY_BUTTON_Y and not _owns_focus():
			_focus(maxi(_focus_index, 0))   # into the item list; the map keeps the D-pad until then
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.is_echo():
		var code: int = (event as InputEventKey).keycode
		if code == KEY_SPACE:
			close()
			get_viewport().set_input_as_handled()
			return
		if code == KEY_TAB:
			cycle_member(-1 if (event as InputEventKey).shift_pressed else 1)
			get_viewport().set_input_as_handled()
			return
		if code in [KEY_1, KEY_KP_1, KEY_2, KEY_KP_2]:
			var number: int = 1 if code in [KEY_1, KEY_KP_1] else 2
			if number <= MEMBERS.size():
				select_member(MEMBERS[number - 1])
			get_viewport().set_input_as_handled()
			return
	if _owns_focus():
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
			cycle_member(-1 if event.is_action_pressed("ui_left") else 1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			_focus(_focus_index + (1 if event.is_action_pressed("ui_down") else -1))
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			var owner: Control = get_viewport().gui_get_focus_owner()
			if owner == continue_button:
				close()
			else:
				for entry in tiles:
					if entry["equip"] == owner and owner != null:
						_equip(entry["item"])   # A on an opened tile's Equip button wears it
					elif entry["icon"] == owner:
						toggle_expand(entry["item"])   # A on a tile opens it in place (or closes it)
						if expanded_key == MapAutoGear.key_of(entry["item"]):
							_focus_equip_of(entry["item"])
						break
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_cancel"):
			get_viewport().gui_release_focus()
			_focus_index = -1
			get_viewport().set_input_as_handled()

# ---- small drawn glyphs: a chest of the tier, a coin, a flask (no font needed) -----------------------------------------------------------

## The item's own high-resolution icon on the lighter rarity-tinted backing the item card uses (so a thin dark blade still reads), with a rarity
## frame and glow; focusable. Hovering it, or focusing it with a controller, shows the shared item card (ItemTile.focus_card).
class IconBox extends Control:
	var item: Dictionary
	var colour: Color
	var legendary: bool

	func _init(for_item: Dictionary, worn: Variant, px: float, for_colour: Color, for_member: String = "", with_card: bool = true) -> void:
		item = for_item
		colour = for_colour
		legendary = MapModeLegendaries.id_of(for_item) != ""
		name = "Icon"
		custom_minimum_size = Vector2(px, px)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if with_card:
			ItemTile.focus_card(self, for_item, worn, true, true, false, "", for_member)
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		if int(item["rarity"]) > 0 or legendary:
			draw_rect(box.grow(3.0), Color(colour.r, colour.g, colour.b, 0.22))   # the glow behind the frame
		draw_rect(box, Color(0.34, 0.31, 0.27).lerp(colour, 0.28))
		var icon: Texture2D = ItemIcons.icon_for(item)
		if icon != null:
			var fit: float = minf(size.x, size.y) - 10.0
			draw_texture_rect(icon, Rect2((size - Vector2(fit, fit)) * 0.5, Vector2(fit, fit)), false)
		draw_rect(box, colour, false, 3.0 if legendary else 2.0)
		if has_focus() or get_global_rect().has_point(get_global_mouse_position()):
			UiTheme.draw_hover(self, box, has_focus())

class Glyph extends Control:
	var kind: String
	var colour: Color

	func _init(for_kind: String, for_colour: Color) -> void:
		kind = for_kind
		colour = for_colour
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s: Vector2 = size
		if kind == "gold":
			var c: Vector2 = s * 0.5
			var r: float = minf(s.x, s.y) * 0.46
			draw_circle(c, r + 1.5, Color(0.12, 0.08, 0.02))
			draw_circle(c, r, colour.darkened(0.15))
			draw_circle(c, r * 0.72, colour.lightened(0.15))
			draw_arc(c, r * 0.5, 0.0, TAU, 20, colour.darkened(0.35), 2.0)
		elif kind == "potion":
			var c: Vector2 = s * 0.5
			draw_rect(Rect2(c.x - 3.0, 2.0, 6.0, 6.0), Color(0.7, 0.62, 0.5))
			draw_circle(c + Vector2(0, 5), s.x * 0.34, Color(0.1, 0.03, 0.03))
			draw_circle(c + Vector2(0, 5), s.x * 0.3, colour)
			draw_circle(c + Vector2(-3, 2), 2.5, colour.lightened(0.5))
		else:
			_draw_chest(kind.get_slice(":", 1))

	## A front view of the chest of this tier: wood, iron bands, gilded trim, a cursed glow, a hoard's heap of coin.
	func _draw_chest(tier: String) -> void:
		var s: Vector2 = size
		var wood := Color(0.42, 0.26, 0.12)
		var body := Rect2(Vector2(5, s.y * 0.42), Vector2(s.x - 10, s.y * 0.5))
		var lid := Rect2(Vector2(4, s.y * 0.14), Vector2(s.x - 8, s.y * 0.32))
		if tier == "cursed":
			draw_circle(s * 0.5, s.x * 0.52, Color(colour.r, colour.g, colour.b, 0.28))
			wood = Color(0.26, 0.16, 0.3)
		if tier == "hoard":
			for i in 4:
				draw_circle(Vector2(s.x * (0.22 + 0.19 * i), s.y * 0.1), 3.4, Color(1.0, 0.82, 0.3))
		draw_rect(body, wood)
		draw_rect(lid, wood.lightened(0.12))
		draw_rect(body, Color(0.05, 0.03, 0.02), false, 1.5)
		draw_rect(lid, Color(0.05, 0.03, 0.02), false, 1.5)
		var band: Color = Color(0.5, 0.54, 0.6)
		if tier == "gilded" or tier == "hoard":
			band = Color(1.0, 0.8, 0.28)
		elif tier == "cursed":
			band = colour.lightened(0.2)
		elif tier == "wooden":
			band = wood.darkened(0.35)
		for x in [s.x * 0.28, s.x * 0.72]:
			draw_rect(Rect2(Vector2(x - 2.5, lid.position.y), Vector2(5, body.end.y - lid.position.y)), band)
		if tier == "gilded" or tier == "hoard" or tier == "iron":
			draw_rect(Rect2(Vector2(lid.position.x, body.position.y - 2), Vector2(lid.size.x, 3)), band)
		draw_rect(Rect2(Vector2(s.x * 0.5 - 3.0, body.position.y - 3.0), Vector2(6, 8)), band.lightened(0.2))
