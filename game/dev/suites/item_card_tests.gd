extends DevSuite
## The item card (issue #85): one shared builder (ItemTile.card / display_rows over Items.rows / Items.compare) for every card. Each line shows
## once, a compare is in the same terms as the stat line, the lines the owner removed do not come back, text is solid and readable, sections
## keep their order, and every kind of card (hover, trader, stash, ground, summary) is built by that one builder.

const REMOVED_FRAGMENTS: Array[String] = ["Speed x", "Compared with", "(R-click", "(Confirm", "Normal Weapon", "(+", "(-", "you cannot wear it yet)"]

func _labels(card: Control) -> Array[String]:
	var out: Array[String] = []
	for label in card.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out

func _count(texts: Array[String], fragment: String) -> int:
	var n := 0
	for text in texts:
		if text.contains(fragment):
			n += 1
	return n

func _luminance(c: Color) -> float:
	var f := func(v: float) -> float: return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

func _test_item_cards() -> void:
	TownState.dev_set_hero_level(20)
	var member: String = PartyManager.current().active_id
	var greatsword: Dictionary = Items.build(ItemDb.get_def("greatsword"), 40, Items.Rarity.RARE, Items.roll_mods(ItemDb.get_def("greatsword"), 40, Items.Rarity.RARE))
	var longsword: Dictionary = Items.build(ItemDb.get_def("longsword"), 3, Items.Rarity.NORMAL)
	var better: Dictionary = Items.build(ItemDb.get_def("longsword"), 12, Items.Rarity.RARE, Items.roll_mods(ItemDb.get_def("longsword"), 12, Items.Rarity.RARE))
	var plate: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Plate Cuirass")
	var leather: Dictionary = Items.make(Items.Slot.ARMOR, Items.Rarity.NORMAL, 1, "Leather Jerkin")

	# --- Each line once -------------------------------------------------------------------------------------------------------------------
	expect("the greatsword is out of reach at hero level 20 (the unmet case)", not Items.hero_can_wear(greatsword, member))
	var unmet := ItemTile.card(greatsword, longsword, true)
	var texts := _labels(unmet)
	expect("the requirement is shown once on an unmet card: %s" % [texts], _count(texts, "Requires ") == 1)
	expect("the cannot-wear message is not a second line", _count(texts, "cannot wear") == 1)
	expect("the item level is one header line, not a row", _count(texts, "Item level") == 1)
	expect("one 'vs <worn item>' line names what is worn", _count(texts, "vs %s" % String(longsword["name"])) == 1)
	var unmet_color_ok := false
	for label in unmet.find_children("*", "Label", true, false):
		if (label as Label).text.contains("Requires "):
			unmet_color_ok = (label as Label).get_theme_color("font_color").is_equal_approx(ItemTile.UNMET_COLOR)
	expect("the unmet requirement is red", unmet_color_ok)
	for fragment in REMOVED_FRAGMENTS:
		expect("a removed line does not come back: '%s'" % fragment, _count(texts, fragment) == 0)
	expect("no stat text carries a doubled sign or a bracketed change: %s" % [texts],
		not texts.any(func(t: String) -> bool: return t.begins_with("+ ") or t.begins_with("- ") or t.contains(" (+") or t.contains(" (-")))
	unmet.free()
	var wearable: Dictionary = Items.build(ItemDb.get_def("longsword"), 3, Items.Rarity.MAGIC, Items.roll_mods(ItemDb.get_def("longsword"), 3, Items.Rarity.MAGIC))
	var met_rows := ItemTile.display_rows(wearable, [], member)
	var req_rows := met_rows.filter(func(r: Dictionary) -> bool: return String(r["section"]) == "req")
	expect("a requirement the hero meets is one line and not red", req_rows.size() <= 1 and (req_rows.is_empty() or not (req_rows[0]["color"] as Color).is_equal_approx(ItemTile.UNMET_COLOR)))
	expect("an item with no requirement problem has no cannot-wear line", not met_rows.any(func(r: Dictionary) -> bool: return String(r["text"]).contains("cannot wear")))

	# --- The compare is in the stat line's own terms --------------------------------------------------------------------------------------
	var rows := ItemTile.display_rows(better, Items.compare(better, longsword, member), member)
	var damage: Dictionary = {}
	var speed: Dictionary = {}
	for row in rows:
		match String(row["key"]):
			"damage": damage = row
			"speed": speed = row
	var a: Dictionary = better["stats"]
	var b: Dictionary = longsword["stats"]
	var avg_a: float = (float(a["min"]) + float(a["max"])) * 0.5
	var avg_b: float = (float(b["min"]) + float(b["max"])) * 0.5
	expect("the damage line shows its range and the average the compare uses: %s" % damage.get("text", ""),
		String(damage.get("text", "")) == "Damage %d-%d (avg %.1f)" % [int(a["min"]), int(a["max"]), avg_a])
	expect("the damage change is that average's change: %s" % damage.get("delta", ""),
		is_equal_approx(avg_a, avg_b) or String(damage.get("delta", "")) == "%s %.1f" % [Items.UP if avg_a > avg_b else Items.DOWN, absf(avg_a - avg_b)])
	var armor_rows := ItemTile.display_rows(plate, Items.compare(plate, leather, member), member).filter(func(r: Dictionary) -> bool: return String(r["key"]) == "armor")
	expect("the armour change is the difference of the two armour numbers",
		armor_rows.size() == 1 and String(armor_rows[0]["delta"]) == "%s %d" % [Items.UP, int(plate["stats"]["armor"]) - int(leather["stats"]["armor"])])
	expect("a better stat is green, a worse one red", (armor_rows[0]["delta_color"] as Color).is_equal_approx(ItemTile.UP_COLOR)
		and (ItemTile.display_rows(leather, Items.compare(leather, plate, member), member).filter(func(r: Dictionary) -> bool: return String(r["key"]) == "armor")[0]["delta_color"] as Color).is_equal_approx(ItemTile.UNMET_COLOR))
	expect("speed reads as a word, not a multiplier: %s" % speed.get("text", ""), String(speed.get("text", "")).begins_with("Speed: ") and not String(speed.get("text", "")).contains("x0"))
	expect("the speed words", Items.speed_word(0.82) == "Slow" and Items.speed_word(1.0) == "Normal" and Items.speed_word(1.18) == "Fast" and Items.speed_word(1.5) == "Very fast")
	var vs_rows := rows.filter(func(r: Dictionary) -> bool: return String(r["section"]) == "vs")
	expect("exactly one 'vs' line leads the compare", vs_rows.size() >= 1 and String(vs_rows[0]["text"]) == "vs %s (equipped)" % String(longsword["name"]) and rows[0] == vs_rows[0])
	var empty_rows := ItemTile.display_rows(better, Items.compare(better, null, member), member)
	expect("an empty slot is one green line", empty_rows[0]["text"] == "Nothing worn in this slot" and (empty_rows[0]["color"] as Color).is_equal_approx(ItemTile.UP_COLOR))

	# --- Sections keep their order --------------------------------------------------------------------------------------------------------
	MapMode.current = MapMode.new()   # the map-mode trait and legendary lines show only while map mode runs
	var legend: Dictionary = MapModeLegendaries.item("gravecaller_maul")
	var samples: Array[Dictionary] = [greatsword, better, legend, Items.make(Items.Slot.ARMOR, Items.Rarity.SET, 10), Items.make(Items.Slot.AMULET, Items.Rarity.UNIQUE, 10)]
	for sample in samples:
		if sample.is_empty():
			continue
		var order: Array[int] = []
		for row in ItemTile.display_rows(sample, Items.compare(sample, longsword, member), member):
			order.append(-1 if String(row["section"]) == "vs" else Items.SECTIONS.find(String(row["section"])))
		var sorted_order := order.duplicate()
		sorted_order.sort()
		expect("%s: lines keep the order vs, base, modifiers, trait, legendary, set, requirements" % String(sample["name"]), order == sorted_order and not order.has(-2))
	if not legend.is_empty():
		var legend_rows := ItemTile.display_rows(legend, [], member).filter(func(r: Dictionary) -> bool: return String(r["section"]) == "legendary")
		expect("a map-mode legendary has its effect line in legendary orange", legend_rows.size() == 1 and (legend_rows[0]["color"] as Color).is_equal_approx(ItemTile.LEGENDARY_COLOR))
	var trait_item: Dictionary = Items.build(ItemDb.get_def("falchion"), 5, Items.Rarity.NORMAL)
	var trait_rows := ItemTile.display_rows(trait_item, [], member).filter(func(r: Dictionary) -> bool: return String(r["section"]) == "trait")
	expect("the map-mode trait is its own section and colour", trait_rows.size() == 1 and (trait_rows[0]["color"] as Color).is_equal_approx(MapModeTraits.LINE_COLOR))
	var with_legend: Control = ItemTile.card(legend if not legend.is_empty() else better, null, false)
	expect("a legendary card has the strong frame", (with_legend.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size > 0)
	with_legend.free()
	var plain_card := ItemTile.card(longsword, null, false)
	expect("a normal card has no glow", (plain_card.get_theme_stylebox("panel") as StyleBoxFlat).shadow_size == 0)
	plain_card.free()
	MapMode.current.free()
	MapMode.current = null

	# --- Readability ------------------------------------------------------------------------------------------------------------------------
	var panel_bg: Color = UiTheme.card_box().bg_color
	expect("the panel is near-opaque", panel_bg.a >= 0.98)
	var worst := 99.0
	var translucent := 0
	for sample in [greatsword, better, plate, wearable]:
		var card := ItemTile.card(sample, longsword, true, true, "Walk over it: it goes in the bag", Color(0.5, 0.9, 0.5))
		for label in card.find_children("*", "Label", true, false):
			var color: Color = (label as Label).get_theme_color("font_color")
			if color.a < 1.0:
				translucent += 1
			worst = minf(worst, _contrast(color, panel_bg))
		card.free()
	expect("no card text is translucent", translucent == 0)
	expect("every card text has at least 4.5:1 contrast on the panel (worst %.1f)" % worst, worst >= 4.5)

	# --- The wrapping fixes ---------------------------------------------------------------------------------------------------------------
	expect("the class skills break between skills, never inside one", not preload("res://game/character_view.gd").classes_text(member).contains("Nature\nMagic") and preload("res://game/character_view.gd").classes_text(member).split("\n").size() == 2
		and preload("res://game/character_view.gd").classes_text(member).split("\n")[1].begins_with("Combat Magic"))

	# --- Every card kind uses the one builder -----------------------------------------------------------------------------------------------
	var loot_source: String = FileAccess.get_file_as_string("res://game/ui/hud_loot_cards.gd")
	expect("the ground card is built by ItemTile.card, with no drawn copy", loot_source.contains("ItemTile.card(") and not loot_source.contains("_draw_card_body") and not loot_source.contains("display_rows"))
	expect("hover and focus cards (inventory, trader, stash) are built by ItemTile.card", FileAccess.get_file_as_string("res://game/item_tile.gd").contains("var detail := card("))
	expect("the item name label's tooltip is built by ItemTile.card", FileAccess.get_file_as_string("res://game/item_name.gd").contains("ItemTile.card("))
	expect("no other file makes its own card from Items.rows", _files_using("Items.rows(").size() == 1)
	var ground := hud.loot_cards
	var drop: Dictionary = better
	ground._draw_card(drop, longsword, Vector2(600, 300), Vector2(1920, 1080), ThemeDB.fallback_font, true, true)
	var built: Control = ground._ground_card
	var ground_texts := _labels(built)
	var shared_texts := _labels(ItemTile.card(drop, longsword, true, false, String(ground._walk_over(drop).text), ground._walk_over(drop).color))
	expect("the ground card shows the very lines the shared card shows", ground_texts == shared_texts and ground_texts.size() > 5)
	expect("the ground card stays on screen", Rect2(Vector2.ZERO, Vector2(1920, 1080)).encloses(ground.ground_card_rect))
	ground._draw_card(drop, longsword, Vector2(1900, 1070), Vector2(1920, 1080), ThemeDB.fallback_font, true, true)
	expect("a ground card asked for the screen corner is moved fully on screen", Rect2(Vector2.ZERO, Vector2(1920, 1080)).encloses(ground.ground_card_rect))
	ground._hide_ground_card(true)

func _files_using(fragment: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://game"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(dir):
			if sub != "dev":
				stack.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd") and FileAccess.get_file_as_string(dir.path_join(file)).contains(fragment):
				out.append(dir.path_join(file))
	return out
