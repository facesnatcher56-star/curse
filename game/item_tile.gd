class_name ItemTile
extends Control
## An item as a picture in a menu. Hovering it shows the item's details and, when `compare_to` is set, how it compares with the piece
## worn in that slot. Used by the town's trader and stash.

const UNMET_COLOR := Color(0.93, 0.30, 0.24)   # the same red as an unmet requirement (see stat_line_color)

var item: Dictionary = {}
var compare_to: Variant = null    # the item worn in this item's slot (or null)
var show_compare: bool = true
var equip_hint: bool = false      # a bag item: its card ends with how to equip it ("R-click to equip")
var action_hint: String = ""      # optional action shown inside the item's details card
var tile_size: float = 52.0
var hovered: bool = false

static func create(for_item: Dictionary, worn: Variant, size: float = 52.0) -> ItemTile:
	var tile := ItemTile.new()
	tile.item = for_item
	tile.compare_to = worn
	tile.tile_size = size
	tile.custom_minimum_size = Vector2(size, size)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	return tile

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: hovered = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	focus_card(self, item, compare_to, show_compare, true, equip_hint, action_hint)

func _draw() -> void:
	draw_texture_rect(ItemIcons.badge(item), Rect2(Vector2.ZERO, size), false)
	if hovered or has_focus(): UiTheme.draw_hover(self, Rect2(Vector2.ZERO, size), has_focus())

## Card text colours: every one reads clearly on the card's near-black panel (none is dimmed by transparency).
const TEXT_COLOR := Color(0.95, 0.92, 0.84)
const MOD_COLOR := Color(0.66, 0.80, 1.0)
const SET_COLOR := Color(0.55, 0.92, 0.50)
const LEGENDARY_COLOR := Color(1.0, 0.64, 0.20)
const MET_NEUTRAL := Color(0.80, 0.76, 0.68)
const HINT_COLOR := Color(0.86, 0.82, 0.72)
const DIVIDER_COLOR := Color(0.62, 0.48, 0.28, 0.55)
const UP_COLOR := Color(0.45, 0.92, 0.45)
const ICON_SIZE := 96.0
const BAND_HEIGHT := 5.0
const PAD := 14.0
## Width of every item card (the trader, stash, inventory and hover cards, and the one on the ground). Wide so long lines wrap in few lines.
const CARD_WIDTH := 460.0
const DELTA_WIDTH := 110.0

## The details card for an item, built once for every place an item is shown: a header (icon, name in its rarity colour, rarity, slot and
## item level) under a rarity-coloured band, then the "vs <worn item>" line, then sections split by dividers (base stats, modifiers, trait,
## legendary effect, set bonuses, requirements), then one action hint. Each stat carries its change beside it as an up or down arrow.
## `with_action_hint` is a bag item's or a ground drop's line of what to do; it is coloured `hint_color` when that is opaque.
static func card(it: Dictionary, worn: Variant, with_compare: bool = true, with_equip_hint: bool = false, with_action_hint: String = "", hint_color: Color = Color(0, 0, 0, 0), for_member: String = "") -> Control:
	var member: String = for_member if for_member != "" else PartyManager.current().active_id   # (`for_member`: the reward panel compares for the member it has selected)
	var rarity: int = int(it["rarity"])
	var legendary: bool = MapModeLegendaries.id_of(it) != ""
	var accent: Color = LEGENDARY_COLOR if legendary else Items.RARITY_COLORS[rarity]
	var comparison: Array[Dictionary] = Items.compare(it, worn, member) if with_compare else Items.wear_warning(it, member)
	var rows: Array[Dictionary] = display_rows(it, comparison, member)
	var strong: bool = legendary or rarity >= Items.Rarity.UNIQUE
	var panel := PanelContainer.new()
	panel.theme = UiTheme.get_theme() # Native tooltip windows do not always inherit the opener's theme.
	panel.add_theme_stylebox_override("panel", UiTheme.card_box(accent, strong))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	root.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	panel.add_child(root)
	var band := ColorRect.new()   # the rarity band across the top
	band.color = accent
	band.custom_minimum_size = Vector2(0, BAND_HEIGHT)
	root.add_child(band)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(PAD))
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var inner: float = CARD_WIDTH - PAD * 2.0 - 6.0   # the panel's border takes 3 px a side
	box.add_child(_header(it, accent, inner))
	var section: String = ""
	for row in rows:
		if String(row["section"]) != section:
			section = String(row["section"])
			box.add_child(_divider())
		box.add_child(_row(row, inner))
	var hints: Array[String] = []
	if with_equip_hint:
		hints.append("Confirm to equip" if Gamepad.active else "R-click to equip")
	if not with_action_hint.is_empty():
		hints.append(_hint_text(with_action_hint))
	if not hints.is_empty():
		box.add_child(_divider())
		for hint in hints:
			box.add_child(_wrapping_label(hint, 15, hint_color if hint_color.a > 0.0 else HINT_COLOR, inner))
	return panel

## The icon on the left (the item's own art on its rarity badge at its full 128 px, shown at 72 px), the name in its rarity colour, and under
## it the rarity, slot and item level.
static func _header(it: Dictionary, accent: Color, inner: float) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	# The item's own high-resolution icon on a lighter, rarity-tinted backing, so a thin dark blade still reads.
	var backing := PanelContainer.new()
	var back_style := StyleBoxFlat.new()
	back_style.bg_color = Color(0.34, 0.31, 0.27).lerp(accent, 0.28)
	back_style.border_color = accent
	back_style.set_border_width_all(2)
	back_style.set_corner_radius_all(3)
	back_style.set_content_margin_all(4)
	backing.add_theme_stylebox_override("panel", back_style)
	backing.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	backing.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var icon := TextureRect.new()
	icon.texture = ItemIcons.icon_for(it)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	backing.add_child(icon)
	head.add_child(backing)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(text)
	var text_width: float = inner - ICON_SIZE - 12.0
	var name_label := _wrapping_label(String(it["name"]), 22, accent.lightened(0.1), text_width)
	name_label.add_theme_font_override("font", UiTheme.heading_font())
	text.add_child(name_label)
	var kind := HBoxContainer.new()
	kind.add_theme_constant_override("separation", 8)
	kind.add_child(_label("%s %s" % [Items.rarity_label(it), Items.SLOT_NAMES[int(it["slot"])]], 16, accent.lightened(0.2)))
	kind.add_child(_label(Items.level_text(it), 16, TEXT_COLOR))
	text.add_child(kind)
	return head

static func _divider() -> Control:
	var line := ColorRect.new()
	line.color = DIVIDER_COLOR
	line.custom_minimum_size = Vector2(0, 1)
	return line

## One line of the card: its text (wrapping inside its own column), and its change, if any, right-aligned beside it.
static func _row(row: Dictionary, inner: float) -> Control:
	var section: String = String(row["section"])
	var delta: String = String(row.get("delta", ""))
	var size: int = 17 if section == "legendary" else 16
	var text_width: float = inner - (DELTA_WIDTH if delta != "" else 0.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var label := _wrapping_label(String(row["text"]), size, row["color"], text_width)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	if delta != "":
		var change := _label(delta, 16, row["delta_color"])
		change.custom_minimum_size.x = DELTA_WIDTH
		change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		change.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(change)
	if section != "legendary":
		return line
	var tint := PanelContainer.new()   # the legendary effect sits on a warm band: the most prominent line after the name
	var style := StyleBoxFlat.new()
	style.bg_color = Color(LEGENDARY_COLOR.r, LEGENDARY_COLOR.g, LEGENDARY_COLOR.b, 0.16)
	style.border_color = LEGENDARY_COLOR
	style.border_width_left = 3
	style.set_content_margin_all(6)
	style.content_margin_left = 10
	tint.add_theme_stylebox_override("panel", style)
	tint.add_child(line)
	return tint

## An action hint in the words of the input in use: "(R-click to take off)" reads "Confirm to take off" with a controller.
static func _hint_text(hint: String) -> String:
	var plain: String = hint.substr(1, hint.length() - 2) if hint.begins_with("(") and hint.ends_with(")") and hint.count("(") == 1 else hint
	return plain.replace("R-click", "Confirm") if Gamepad.active else plain

## The lines of an item card, in order, as {text, color, section, key, delta, delta_color}. Shared by every item card (hover, trader, stash,
## inventory and the ground). First the one "vs <worn item>" line; then the sections (Items.SECTIONS). Each stat carries its change beside it
## (`delta`, "▲ 1.5", coloured by `delta_color`); a change to a stat the item does not have still appears, as its own line in the modifiers.
## The requirement is one line, red (and saying the hero cannot wear it yet) only when unmet.
static func display_rows(it: Dictionary, comparison: Array[Dictionary], member_id: String) -> Array[Dictionary]:
	var vs: Array[Dictionary] = []
	var deltas: Dictionary = {}
	var unmet: bool = false
	for entry in comparison:
		var key: String = String(entry["key"])
		if key == Items.WARNING_KEY:
			unmet = true
		elif key == Items.VS_KEY or key == "":
			vs.append({"text": String(entry["text"]), "color": _delta_color(int(entry["sign"])) if int(entry["sign"]) != 0 else TEXT_COLOR,
				"section": "vs", "key": key, "delta": "", "delta_color": TEXT_COLOR})
		else:
			deltas[key] = entry
	var groups: Dictionary = {}
	for section in Items.SECTIONS:
		groups[section] = []
	var shown: Dictionary = {}
	for row in Items.rows(it, member_id):
		var key: String = String(row["key"])
		var section: String = String(row["section"])
		var out_row := {"text": String(row["text"]), "color": row.get("color", _section_color(section)), "section": section, "key": key,
			"delta": "", "delta_color": TEXT_COLOR}
		if key == Items.REQ_KEY:
			var met: bool = Items.hero_can_wear(it, member_id)
			out_row["color"] = MET_NEUTRAL if met else UNMET_COLOR   # a met requirement is quiet; only what is lacking is red
			if not met:
				out_row["text"] = "%s - you cannot wear this yet" % String(row["text"])
			unmet = false
		elif deltas.has(key):
			shown[key] = true
			out_row["delta"] = String(deltas[key]["delta"])
			out_row["delta_color"] = _delta_color(int(deltas[key]["sign"]))
		groups[section].append(out_row)
	for key in deltas:
		if not shown.has(key):
			var entry: Dictionary = deltas[key]
			groups["mods"].append({"text": String(entry.get("stat_text", entry["text"])), "color": MOD_COLOR, "section": "mods", "key": String(key),
				"delta": String(entry["delta"]), "delta_color": _delta_color(int(entry["sign"]))})
	if unmet:   # the one line that says the hero cannot wear it yet (after its requirement, when it has one)
		groups["req"].append({"text": "You cannot wear this yet", "color": UNMET_COLOR, "section": "req", "key": Items.WARNING_KEY, "delta": "", "delta_color": TEXT_COLOR})
	var out: Array[Dictionary] = vs
	for section in Items.SECTIONS:
		out.append_array(groups[section])
	return out

static func _section_color(section: String) -> Color:
	match section:
		"mods": return MOD_COLOR
		"legendary": return LEGENDARY_COLOR
		"set": return SET_COLOR
	return TEXT_COLOR

## The colour of a comparison: green for a beneficial change, red for a detrimental one, cream when neutral.
static func _delta_color(sign_value: int) -> Color:
	if sign_value > 0:
		return UP_COLOR
	if sign_value < 0:
		return UNMET_COLOR
	return TEXT_COLOR

static func _wrapping_label(text: String, size: int, color: Color, width: float = CARD_WIDTH) -> Label:
	var label := _label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A wrapping label measures its height at the width it has. Before the container lays it out that width is 0, which wraps every word
	# onto its own line and made the card taller than the screen. Give it its column's width up front so its height is its text.
	label.custom_minimum_size.x = width
	label.size.x = width
	return label

## How far a hover card's edge overlaps the item it describes (see focus_card): the pointer crosses from item to card without a gap.
const HOVER_OVERLAP := 6.0

## Shared by inventory/shop cards and ground-loot cards.
static func stat_line_color(it: Dictionary, line: String) -> Color:
	return Color(0.93, 0.30, 0.24) if line.contains("Requires ") and not Items.hero_can_wear(it, PartyManager.current().active_id) else Color(0.9, 0.88, 0.82)

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func name_label(it: Dictionary, worn: Variant, compare: bool = true, with_equip_hint: bool = false) -> Label:
	var label: Label = preload("res://game/item_name.gd").new()
	label.item = it
	label.worn = worn
	label.show_compare = compare
	label.equip_hint = with_equip_hint
	label.text = String(it["name"])
	label.tooltip_text = label.text
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 84
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Items.RARITY_COLORS[int(it["rarity"])])
	return label

## The details card shown beside `control`: with a controller while it has focus, and with `on_hover` the moment the mouse is over it (an
## item's picture shows its card at once, like the item on the ground does; its buttons do not).
static func focus_card(control: Control, it: Dictionary, worn: Variant, compare: bool = true, on_hover: bool = false, with_equip_hint: bool = false, with_action_hint: String = "", for_member: String = "") -> void:
	var holder := Control.new()
	holder.name = "ItemDetails"
	holder.add_user_signal("hover_resolved")   # emitted each time a hover close is decided (see _close_when_unhovered)
	holder.top_level = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = 100
	holder.visible = false
	control.add_child(holder)
	var reposition: Callable = func() -> void:
		if not is_instance_valid(holder) or not holder.visible or holder.get_child_count() == 0:
			return
		var scroll := holder.get_child(0) as ScrollContainer
		var detail := scroll.get_child(0) as Control
		var screen: Vector2 = control.get_viewport_rect().size
		var safe_rect := Rect2(Vector2(8, 8), Vector2(maxf(1, screen.x - 16), maxf(1, screen.y - 118)))
		# Full size always: the card grows with its text, and only a card taller than the safe area scrolls (never scaled down).
		var extent: Vector2 = detail.get_combined_minimum_size()
		var shown := Vector2(minf(extent.x, safe_rect.size.x), minf(extent.y, safe_rect.size.y))
		scroll.size = shown
		# Try the sides of the item in turn (right, left, below, above) and take the first that covers no buttons. Buttons are the
		# merchant's Buy/Sell controls and neighbouring rows; with none clear, the side that covers the least wins.
		var item_rect := Rect2(control.global_position, control.size)
		# A tile inside the character window: the card goes beside the window (right, then left), so the grid being browsed stays visible.
		var window: Control = control
		while window != null and not window.has_method("gear_text"):
			window = window.get_parent() as Control
		if window != null:
			var win_rect := window.get_global_rect()
			for beside in [win_rect.end.x + 8.0, win_rect.position.x - 8.0 - shown.x]:
				if beside >= safe_rect.position.x and beside + shown.x <= safe_rect.end.x:
					holder.global_position = Vector2(beside, clampf(item_rect.position.y, safe_rect.position.y, maxf(safe_rect.position.y, safe_rect.end.y - shown.y)))
					return
		var blockers: Array[Rect2] = []
		for button in control.get_viewport().find_children("*", "BaseButton", true, false):
			var other := button as Control
			if other == null or other == control or holder.is_ancestor_of(other) or not other.is_visible_in_tree():
				continue
			blockers.append(other.get_global_rect())
		# Each side overlaps the item's edge by HOVER_OVERLAP, so the pointer crosses straight from the item into the card: there is no gap
		# where neither is hovered.
		var sides: Array[Vector2] = [
			Vector2(item_rect.end.x - HOVER_OVERLAP, item_rect.position.y),
			Vector2(item_rect.position.x + HOVER_OVERLAP - shown.x, item_rect.position.y),
			Vector2(item_rect.position.x, item_rect.end.y - HOVER_OVERLAP),
			Vector2(item_rect.position.x, item_rect.position.y + HOVER_OVERLAP - shown.y),
		]
		var position := Vector2.ZERO
		var least := INF
		var found := false
		var first := Vector2.ZERO
		for index in sides.size():
			var side: Vector2 = sides[index]
			var candidate := Vector2(clampf(side.x, safe_rect.position.x, maxf(safe_rect.position.x, safe_rect.end.x - shown.x)),
				clampf(side.y, safe_rect.position.y, maxf(safe_rect.position.y, safe_rect.end.y - shown.y)))
			if index == 0:
				first = candidate
			# A side is usable only if the clamped card still overlaps the item's edge, so the pointer cannot cross a gap.
			if not _keeps_hover_edge(Rect2(candidate, shown), item_rect):
				continue
			found = true
			var covered := 0.0
			for blocker in blockers:
				covered += Rect2(candidate, shown).intersection(blocker).get_area()
			if covered < least:
				least = covered
				position = candidate
			if covered <= 0.0:
				break
		holder.global_position = position if found else first
	var open: Callable = func() -> void:
		for child in holder.get_children():
			child.free()
		var detail := card(it, worn, compare, with_equip_hint, with_action_hint, Color(0, 0, 0, 0), for_member)
		var scroll := ScrollContainer.new()   # a card taller than the screen scrolls instead of clipping or shrinking
		scroll.name = "DetailScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.mouse_filter = Control.MOUSE_FILTER_PASS # the wheel reaches a tall card; PASS keeps clicks from landing on a merchant button under it
		scroll.add_child(detail)
		holder.add_child(scroll)
		scroll.mouse_entered.connect(func() -> void: holder.set_meta("card_hover", true))
		scroll.mouse_exited.connect(func() -> void:
			holder.set_meta("card_hover", false)
			_close_when_unhovered.bind(holder).call_deferred())
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for child in detail.find_children("*", "Control", true, false):
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE # tooltip contents must not intercept a drag destination
		holder.visible = true
		reposition.call()
	holder.tree_entered.connect(func() -> void:
		var viewport: Viewport = control.get_viewport()
		if viewport != null and not viewport.size_changed.is_connected(reposition):
			viewport.size_changed.connect(reposition))
	control.tree_exiting.connect(func() -> void:
		var viewport: Viewport = control.get_viewport()
		if viewport != null and viewport.size_changed.is_connected(reposition):
			viewport.size_changed.disconnect(reposition))
	control.resized.connect(reposition)
	control.item_rect_changed.connect(reposition)
	control.focus_entered.connect(func() -> void:
		if Gamepad.active:
			open.call())
	control.focus_exited.connect(func() -> void: holder.visible = false)
	if on_hover:
		control.mouse_entered.connect(func() -> void:
			holder.set_meta("item_hover", true)
			open.call())
		control.mouse_exited.connect(func() -> void:
			holder.set_meta("item_hover", false)
			_close_when_unhovered.bind(holder).call_deferred())   # deferred: the pointer may enter the card in this same event

## Whether a card rect overlaps its item's rect by at least HOVER_OVERLAP across the edge the card sits on (a horizontal side needs that
## much width, a vertical side that much height), so the pointer crosses from item to card without a gap.
static func _keeps_hover_edge(card: Rect2, item: Rect2) -> bool:
	var overlap := card.intersection(item)
	return (overlap.size.x >= HOVER_OVERLAP and overlap.size.y > 0.0) or (overlap.size.y >= HOVER_OVERLAP and overlap.size.x > 0.0)

## Closes a hover card once neither its item nor the card is hovered. Hover is tracked from the enter and exit signals, so the decision
## follows what the pointer did, not a polled position. The check runs at the end of the frame, after a pointer that moved from the item onto
## the card has entered the card.
## `holder` is deliberately untyped: this runs as a deferred call, which is handed the bound node even if it was freed in the meantime, and a
## typed parameter would fail to convert that freed object. It is validated before any use.
static func _close_when_unhovered(holder) -> void:
	if not is_instance_valid(holder) or not (holder is Control):
		return
	if not (bool(holder.get_meta("item_hover", false)) or bool(holder.get_meta("card_hover", false))):
		holder.visible = false
	holder.emit_signal("hover_resolved")   # after the decision, so a test can await the close itself rather than a frame count

static func decorate_button(button: Button, it: Dictionary, worn: Variant) -> void:
	button.set_script(preload("res://game/item_button.gd"))
	button.item = it
	button.worn = worn
	focus_card(button, it, worn)
