extends DevSuite
## The map-mode autoplay's gear logic (game/map_mode/map_auto_gear.gd): it wears a clear upgrade for either member, refuses what nobody can wear,
## keeps the replaced piece in the bag, logs the equip with the comparison that decided it, and the decision is the shared one (Items.compare,
## LootAppraisal.trend, Items.hero_can_wear), not a copy.

func _weapon(damage_scale: float, level: int = 1) -> Dictionary:
	var it: Dictionary = Items.build(ItemDb.get_def("club"), level, Items.Rarity.NORMAL)
	it["stats"] = (it["stats"] as Dictionary).duplicate(true)
	if it["stats"].has("max"):
		it["stats"]["min"] = float(it["stats"]["min"]) * damage_scale
		it["stats"]["max"] = float(it["stats"]["max"]) * damage_scale
	it["name"] = "Test blade x%.1f" % damage_scale
	return it

func _balance(item: Dictionary, current: Variant, member_id: String) -> int:
	var b: int = 0
	for line in Items.compare(item, current, member_id):
		if String(line.get("key", "")) != Items.WARNING_KEY:
			b += int(line["sign"])
	return b

func _test_map_equip() -> void:
	TownState.persist = false
	TownState.reset()
	var hero: Player = player
	var cutter: Player = game.companion
	hero.set_physics_process(false)
	var cutter_disabled: bool = cutter.testing_disabled
	cutter.testing_disabled = true
	cutter.set_physics_process(false)
	var saved_hero: Dictionary = hero.stats.equipment.duplicate(true)
	var saved_cutter: Dictionary = cutter.stats.equipment.duplicate(true)
	var saved_bag: Array = hero.stats.bag.duplicate(true)
	hero.stats.bag.clear()
	var top: Dictionary = _weapon(100.0)   # the Cutter wears something nothing here beats: only the warrior's slots are in play
	top["name"] = "Unbeatable blade"
	cutter.stats.equipment[Items.Slot.WEAPON] = top
	cutter.stats.refresh()
	var m := MapMode.new()
	m.hero = hero
	m.companion = cutter
	game.add_child(m)
	MapAutoGear.reset()

	# A clear upgrade: the better blade goes on, the old one goes to the bag, the equip is logged with its numbers.
	var weak: Dictionary = _weapon(1.0)
	hero.stats.equipment.clear()
	hero.stats.equipment[Items.Slot.WEAPON] = weak
	hero.stats.refresh()
	var strong: Dictionary = _weapon(3.0)
	expect("setup: the strong blade is wearable and the shared comparison calls it better", Items.hero_can_wear(strong, "hero") and _balance(strong, weak, "hero") > 0 and LootAppraisal.trend(strong, hero.stats) > 0)
	expect("the bag takes the strong blade", hero.stats.add_to_bag(strong))
	var made: Array[Dictionary] = MapAutoGear.process(m, MapAutoGear.snapshot([hero, cutter]), [])
	expect("the upgrade is worn", String(hero.stats.equipment[Items.Slot.WEAPON]["name"]) == String(strong["name"]))
	var bag_names: Array = hero.stats.bag.map(func(i: Dictionary) -> String: return String(i["name"]))
	expect("the replaced blade stays in the bag", bag_names.has(String(weak["name"])) and not bag_names.has(String(strong["name"])))
	var rec: Dictionary = made[0] if not made.is_empty() else {}
	expect("one equip is made and logged with item, rarity, slot, who, why", made.size() == 1 and m.log.equips.size() == 1 and String(rec.get("name", "")) == String(strong["name"])
		and String(rec.get("slot", "")) == "Weapon" and String(rec.get("rarity", "")) == "Normal" and String(rec.get("who", "")) == hero.display_name and not (rec.get("lines", []) as Array).is_empty()
		and int(rec.get("balance", 0)) == _balance(strong, weak, "hero") and String(rec.get("replaces", "")) == String(weak["name"]))
	expect("the equip line names the item and the verdict", MapAutoGear.line_of(rec).begins_with("[mapmode] EQUIP Test blade x3.0") and MapAutoGear.line_of(rec).contains("why:"))
	expect("the fight log summary carries the equips", "\n".join(m.log.equip_lines()).contains("equips: 1"))

	# A worse piece is left alone, and the same comparison says so.
	var worse: Dictionary = _weapon(0.5)
	hero.stats.add_to_bag(worse)
	var before_name: String = String(hero.stats.equipment[Items.Slot.WEAPON]["name"])
	var none: Array[Dictionary] = MapAutoGear.process(m, MapAutoGear.snapshot([hero, cutter]), [])
	expect("a worse blade is not worn (shared comparison: balance %d, trend %d)" % [_balance(worse, hero.stats.equipment[Items.Slot.WEAPON], "hero"), LootAppraisal.trend(worse, hero.stats)],
		none.is_empty() and String(hero.stats.equipment[Items.Slot.WEAPON]["name"]) == before_name and _balance(worse, hero.stats.equipment[Items.Slot.WEAPON], "hero") < 0 and LootAppraisal.trend(worse, hero.stats) < 0)
	expect("and it is reported as never worn, with the reason", String(MapAutoGear.seen[MapAutoGear.key_of(worse)]["reason"]).contains("not better"))

	# An unwearable piece is refused however strong it is.
	var locked: Dictionary = _weapon(10.0, 40)
	hero.stats.add_to_bag(locked)
	expect("setup: nobody can wear the level 40 blade yet", not Items.hero_can_wear(locked, "hero") and not Items.hero_can_wear(locked, "cutter"))
	var refused: Array[Dictionary] = MapAutoGear.process(m, MapAutoGear.snapshot([hero, cutter]), [])
	expect("the unwearable blade is refused and stays in the bag", refused.is_empty() and String(hero.stats.equipment[Items.Slot.WEAPON]["name"]) == before_name
		and hero.stats.bag.any(func(i: Dictionary) -> bool: return String(i["name"]) == String(locked["name"])))
	expect("its reason names the requirement", String(MapAutoGear.seen[MapAutoGear.key_of(locked)]["reason"]).contains("cannot wear"))

	# The Cutter gets a piece the warrior cannot use better: an empty slot on her is an upgrade for her.
	var helm: Dictionary = Items.build(ItemDb.get_def("leather_cap"), 1, Items.Rarity.NORMAL)
	cutter.stats.equipment.erase(Items.Slot.HELM)
	hero.stats.equipment[Items.Slot.HELM] = Items.build(ItemDb.get_def("iron_helm"), 1, Items.Rarity.NORMAL)
	hero.stats.equipment[Items.Slot.HELM]["stats"] = {"armor": 9999}
	hero.stats.equipment[Items.Slot.HELM]["name"] = "Unbeatable helm"
	hero.stats.refresh()
	hero.stats.add_to_bag(helm)
	var cutter_made: Array[Dictionary] = MapAutoGear.process(m, MapAutoGear.snapshot([hero, cutter]), [])
	expect("an upgrade only one member can use goes to that member (the shared trend picks her: the warrior's helm is better)",
		cutter_made.size() == 1 and String(cutter_made[0]["member"]) == "cutter" and cutter.stats.equipment.has(Items.Slot.HELM) and LootAppraisal.trend(helm, hero.stats) < 0)

	# Clean up.
	m.free()
	hero.stats.equipment.clear()
	for place in saved_hero:
		hero.stats.equipment[place] = saved_hero[place]
	cutter.stats.equipment.clear()
	for place in saved_cutter:
		cutter.stats.equipment[place] = saved_cutter[place]
	hero.stats.bag.assign(saved_bag)
	hero.stats.refresh()
	cutter.stats.refresh()
	cutter.testing_disabled = cutter_disabled
	cutter.set_physics_process(true)
	hero.set_physics_process(true)
	MapAutoGear.reset()
