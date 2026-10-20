extends DevSuite
## Champion affix chips (#85 addendum): every affix has its one-line effect in Champion.AFFIXES; the target banner shows exactly one chip per
## affix (two for a 2-affix champion); the Warded shield has its own segment; the map-mode node tooltip carries the effect line.

func _chip_texts(chips: AffixChips) -> PackedStringArray:
	var out: PackedStringArray = []
	for chip in chips.get_children():
		for child in chip.get_children():
			if child is Label:
				out.append((child as Label).text)
	return out

func _test_champion_affix_chips() -> void:
	for id in Champion.AFFIXES:
		expect("%s has an effect line" % id, String(Champion.AFFIXES[id].get("effect", "")).length() > 10)
	var swift_ok: bool = String(Champion.AFFIXES.fast.effect).contains("50%") and is_equal_approx(float(Champion.AFFIXES.fast.speed), 1.5)
	expect("Swift's text states the real speed multiplier", swift_ok)

	var banner := Ds2TargetBanner.new()
	game.hud.add_child(banner)
	await get_tree().process_frame
	for id in Champion.AFFIXES:
		var e: Enemy = game.director.spawn_enemy(player.global_position + Vector3(14, 0, 0), "zombie", WorldThreat.threat_for_level(4), "normal")
		e.alert_delay = 999.0
		Champion.attach(e, id)
		banner.update_target(e, 0.1)
		var chips: AffixChips = banner._chips
		expect("%s: the banner shows exactly one chip" % id, chips.chip_count() == 1 and Ds2TargetBanner.affixes_of(e) == [id])
		var texts := _chip_texts(chips)
		expect("%s: the chip carries the title and the effect line" % id, texts.has(String(Champion.AFFIXES[id].title).to_upper()) and texts.has(String(Champion.AFFIXES[id].effect)))
		expect("%s: the champion frame is the heavy one" % id, Ds2TargetBanner.strong_frame(e))
		var warded: bool = id == "shielded"
		expect("%s: the shield segment shows only for Warded" % id, banner._shield_track.visible == warded and banner._shield_fill.visible == warded)
		e.queue_free()

	var two: Enemy = game.director.spawn_enemy(player.global_position + Vector3(14, 0, 2), "zombie", WorldThreat.threat_for_level(4), "normal")
	two.alert_delay = 999.0
	var champ: Champion = Champion.attach(two, "shielded")
	champ.extra_ids = ["fast"]
	banner.update_target(two, 0.1)
	expect("a 2-affix champion shows two chips", banner._chips.chip_count() == 2)
	var rows_ok: bool = true
	var kids: Array = banner._chips.get_children()
	for i in kids.size():
		var chip: Control = kids[i]
		rows_ok = rows_ok and chip.position.x >= 0.0 and chip.position.x + chip.size.x <= AffixChips.CHIP_W + 0.01
		if i > 0:
			rows_ok = rows_ok and chip.position.y >= (kids[i - 1] as Control).position.y + (kids[i - 1] as Control).size.y
	expect("the chips are stacked inside the row without overlapping", rows_ok)
	champ.shield = champ.shield_max * 0.5
	banner.update_target(two, 0.1)
	expect("the shield segment follows the shield", is_equal_approx(banner._shield_fill.size.x, ChampionBarWidth.of(banner) * 0.5))
	champ.shield = 0.0
	banner.update_target(two, 0.1)
	expect("a broken shield leaves the empty track", banner._shield_track.visible and not banner._shield_fill.visible)
	banner.update_target(null, 0.1)
	expect("no target, no chips", banner._chips.chip_count() == 0)
	expect("plain enemies have no strong frame", not Ds2TargetBanner.strong_frame(player))
	two.queue_free()
	banner.queue_free()

	# The map-mode node tooltip: the champion's name, then its affix effect line.
	var m := MapMode.new()
	m.graph = MapGraph.from_layout()
	var found: bool = false
	for row in MapModeLayout.nodes():
		if String(row["champion"]) != "":
			var label: String = m.node_label(int(row["id"]))
			var affix: String = String((row["affixes"] as Array)[0])
			found = true
			expect("node %d tooltip carries the %s effect line" % [row["id"], affix], label.contains(String(Champion.AFFIXES[affix].effect)))
	expect("the layout has champion nodes", found)
	m.free()

class ChampionBarWidth:
	static func of(_banner: Ds2TargetBanner) -> float:
		return Ds2TargetBanner.BAR_WIDTH
