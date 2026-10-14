extends DevSuite
## Loot you can read at a glance (LootAppraisal): the verdict for every drop (wearable and better, equal or worse, or not wearable yet),
## its name-plate mark and item-card line on a real HUD, the callout when an upgrade goes to the bag, and the pickup rules around it:
## a full bag leaves the item on the ground, nothing is picked up twice, and drops keep their level window and survive a save.

func _gear(stats: PlayerStats) -> void:
	stats.equipment.clear()
	stats.bag.clear()
	for item in Items.starting_gear():
		stats.equip(item, false)
	stats.refresh()

## A drop that was collected is queued for deletion, then freed.
func _gone(drop: Variant) -> bool:
	return not is_instance_valid(drop) or drop.is_queued_for_deletion()

func _clear_world() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("loot"):
		node.queue_free()

func _test_loot_appraisal() -> void:
	_clear_world()
	await get_tree().process_frame
	TownState.dev_set_hero_level(20)
	TownState.passive_ranks["overbear"] = 1
	var stats: PlayerStats = player.stats
	_gear(stats)
	var V = LootAppraisal.Verdict
	# --- The verdict ----------------------------------------------------------------------------------------------------------------------
	var worn_sword: Dictionary = stats.equipment[Items.Slot.WEAPON]
	var better: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 12, "Longsword")
	var worse: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Falchion")
	var locked: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 70, "Longsword")
	expect("an item level 70 sword is not wearable at hero level 20", not Items.hero_can_wear(locked))
	expect("an unwearable drop is LOCKED, however good", LootAppraisal.of(locked, stats) == V.LOCKED)
	expect("a rare of a higher level than the worn sword is an UPGRADE (%s)" % [Items.compare(better, worn_sword)], LootAppraisal.of(better, stats) == V.UPGRADE)
	expect("the worn item itself is EVEN, not an upgrade", LootAppraisal.of(worn_sword.duplicate(true), stats) == V.EVEN)
	expect("a weaker sword is EVEN", LootAppraisal.of(worse, stats) == V.EVEN)
	var helm: Dictionary = Items.make(Items.Slot.HELM, Items.Rarity.NORMAL, 4)
	for attempt in 40:   # (a helm is for one armour class: take one this hero can wear)
		if Items.hero_can_wear(helm):
			break
		helm = Items.make(Items.Slot.HELM, Items.Rarity.NORMAL, 4)
	expect("a wearable piece for an empty slot is an UPGRADE: walking over it wears it", Items.hero_can_wear(helm) and LootAppraisal.of(helm, stats) == V.UPGRADE)
	expect("the card line names the case", LootAppraisal.note(V.LOCKED, locked, stats) != "" and LootAppraisal.note(V.UPGRADE, better, stats) == "Better than what you wear"
		and LootAppraisal.note(V.UPGRADE, helm, stats) == "Nothing worn in this slot" and LootAppraisal.note(V.EVEN, worse, stats) == "")
	# Rings: with both places full a better ring is an upgrade for whichever it beats.
	var worn_ring: Dictionary = Items.make(Items.Slot.RING, Items.Rarity.NORMAL, 1)
	stats.equip(worn_ring.duplicate(true), false)
	stats.equip(worn_ring.duplicate(true), false)
	var ring: Dictionary = Items.make(Items.Slot.RING, Items.Rarity.RARE, 15)
	for attempt in 40:   # (a ring this hero can wear, carrying at least one modifier)
		if Items.hero_can_wear(ring) and not (ring["mods"] as Array).is_empty():
			break
		ring = Items.make(Items.Slot.RING, Items.Rarity.RARE, 15)
	var plain_ring: Dictionary = stats.equipment[Items.places(Items.Slot.RING)[0]].duplicate(true)   # the very ring that is worn
	expect("with both ring places full, a better ring is an UPGRADE (%s %s)" % [ring["name"], Items.compare(ring, stats.equipment[Items.places(Items.Slot.RING)[0]])], LootAppraisal.of(ring, stats) == V.UPGRADE)
	expect("with both ring places full, the worn ring itself is EVEN (%s)" % [Items.compare(plain_ring, stats.equipment[Items.places(Items.Slot.RING)[0]])], LootAppraisal.of(plain_ring, stats) == V.EVEN)
	# A shield beside a worn two-handed weapon cannot be worn: not an upgrade, even though its slot is empty.
	_gear(stats)
	stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Greatsword"), false)
	var shield: Dictionary = Items.make(Items.Slot.SHIELD, Items.Rarity.NORMAL, 1)
	expect("an empty shield slot under a two-handed weapon is not an UPGRADE", not stats.takes_empty_slot(shield) and LootAppraisal.of(shield, stats) != V.UPGRADE)
	_gear(stats)

	# --- The real HUD: plate marks and the card line --------------------------------------------------------------------------------------
	player.global_position = Vector3(0, 0, 0)
	player.reset_physics_interpolation()
	var d_up: LootDrop = game.director.drop_item(Vector3(-2.2, 0, -2.2), better.duplicate(true))
	var d_even: LootDrop = game.director.drop_item(Vector3(0, 0, -2.2), worse.duplicate(true))
	var d_lock: LootDrop = game.director.drop_item(Vector3(2.2, 0, -2.2), locked.duplicate(true))
	d_up._end = Vector3(-2.2, 0, -2.2)   # (fixed landing spots, so no plate can fall under the minimap or the hotbar by chance)
	d_even._end = Vector3(0, 0, -2.2)
	d_lock._end = Vector3(2.2, 0, -2.2)
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.6).timeout
	hud.show_gear = false
	await get_tree().process_frame
	await get_tree().process_frame
	var shot_dir: String = OS.get_environment("LOOT_SHOT_DIR")   # (windowed runs only: a picture of the real HUD for a person to look at)
	if shot_dir != "" and DisplayServer.get_name() != "headless":
		hud.set_process(true)
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png(shot_dir.path_join("loot_plates.png"))
	var verdicts: Dictionary = {}
	var widths: Dictionary = {}
	for entry in hud.loot_cards.names:
		verdicts[entry["drop"]] = int(entry["verdict"])
		widths[entry["drop"]] = (entry["rect"] as Rect2).size.x
	expect("every landed drop has a name plate carrying its verdict", verdicts.size() == 3)
	expect("the plates show UPGRADE, EVEN and LOCKED for the three drops", verdicts.get(d_up, -1) == V.UPGRADE and verdicts.get(d_even, -1) == V.EVEN and verdicts.get(d_lock, -1) == V.LOCKED)
	var font: Font = ThemeDB.fallback_font
	var even_width: float = font.get_string_size(String(d_even.item["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, HudLootCards.NAME_FONT).x + 14.0
	var up_width: float = font.get_string_size(String(d_up.item["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, HudLootCards.NAME_FONT).x + 14.0 + HudLootCards.MARK_WIDTH
	expect("the unmarked plate is exactly its name plus padding", absf(float(widths.get(d_even, 0.0)) - even_width) < 0.5)
	expect("the marked plate has room for the arrow", absf(float(widths.get(d_up, 0.0)) - up_width) < 0.5)
	var walk_up: Dictionary = hud.loot_cards._walk_over(d_up.item)
	var walk_lock: Dictionary = hud.loot_cards._walk_over(d_lock.item)
	var walk_even: Dictionary = hud.loot_cards._walk_over(d_even.item)
	expect("the card says an upgrade is waiting in the bag", String(walk_up.text).contains("better than what you wear"))
	expect("a locked piece's walk-over line does not repeat the cannot-wear warning", String(walk_lock.text) == "Walk over it: it goes in the bag")
	expect("the locked piece's card shows the cannot-wear warning once",
		ItemTile.display_rows(d_lock.item, Items.compare(d_lock.item, null, PartyManager.current().active_id), PartyManager.current().active_id).filter(
			func(r: Dictionary) -> bool: return String(r["text"]).contains("cannot wear")).size() == 1)
	expect("an even piece keeps the plain bag line", String(walk_even.text) == "Walk over it: it goes in the bag")
	var rects: Array = hud.loot_cards.names.map(func(e): return e["rect"])
	var clashes: int = 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			clashes += 1 if (rects[i] as Rect2).intersects(rects[j]) else 0
	expect("marked plates do not overlap each other", clashes == 0)
	var toast_rect: Rect2 = hud.progression_hud.toast_rect(hud.get_viewport_rect().size)
	var toast_clashes: int = 0
	for rect_value in rects:
		toast_clashes += 1 if (rect_value as Rect2).grow(2.0).intersects(toast_rect) else 0
	expect("loot name plates stay clear of the visible level-up toast", toast_clashes == 0)
	var hud_clashes: int = 0
	for rect_value in rects:
		hud_clashes += 1 if hud.loot_cards._plate_blocked(rect_value, Rect2(), []) else 0
	expect("loot name plates stay clear of the party frames and other HUD controls", hud_clashes == 0)

	# --- The pickup path: upgrade, locked, full bag, no double pickup -------------------------------------------------------------------------
	d_up.pick_up(player)
	await get_tree().process_frame
	var in_bag: bool = stats.bag.any(func(i): return i["name"] == better["name"] and i["level"] == better["level"])
	expect("an upgrade pick-up goes to the bag and the drop is gone (never worn unasked)", in_bag and _gone(d_up) and stats.equipment[Items.Slot.WEAPON]["name"] == worn_sword["name"])
	var bag_size: int = stats.bag.size()
	if is_instance_valid(d_up):
		d_up.pick_up(player)
	await get_tree().process_frame
	expect("the same drop cannot be collected twice", stats.bag.size() == bag_size)
	d_lock.pick_up(player)
	await get_tree().process_frame
	expect("a locked piece can still be carried (it goes to the bag)", stats.bag.any(func(i): return int(i["level"]) == 70))
	while stats.add_to_bag(Items.make(Items.Slot.RING, Items.Rarity.NORMAL, 1)):
		pass
	var held: int = stats.bag.size()
	d_even.pick_up(player)
	await get_tree().process_frame
	expect("a full bag leaves the drop on the ground and loses nothing", is_instance_valid(d_even) and not d_even.is_queued_for_deletion() and stats.bag.size() == held)
	for i in 30:   # (a sword is bigger than a ring: free a good block of cells)
		stats.bag.pop_back()
	held = stats.bag.size()
	d_even.pick_up(player)
	await get_tree().process_frame
	expect("with room again the same drop is taken", _gone(d_even) and stats.bag.size() == held + 1)
	_gear(stats)
	_clear_world()
	await get_tree().process_frame

## The real kill path: a monster dies, the reward is generated once, lands near the body, and is appraised on the HUD; drops stay inside the
## item-level window of the monster, and what is picked up survives a save.
func _test_loot_rewards() -> void:
	_clear_world()
	await get_tree().process_frame
	TownState.dev_set_hero_level(20)
	var stats: PlayerStats = player.stats
	_gear(stats)
	hud.show_gear = false
	var def: EnemyDef = EnemyDb.get_def("zombie")
	var old_tier: String = def.tier
	player.global_position = Vector3(30, 0, 30)
	player.reset_physics_interpolation()
	var zombie: Enemy = _spawn_enemy(Vector3(24, 0, 24))
	zombie.aggro_range = 0.0
	zombie.level = 18
	await get_tree().process_frame
	def.tier = "miniboss"   # a miniboss always drops
	zombie.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": player, "skill_id": "basic", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, player.global_position)
	await get_tree().create_timer(LootDrop.LAND_TIME + 0.6).timeout
	def.tier = old_tier
	var drops: Array = get_tree().get_nodes_in_group("loot")
	expect("one kill leaves exactly one reward (no duplicates)", drops.size() == 1)
	if drops.size() == 1:
		var drop: LootDrop = drops[0]
		var level: int = int(drop.item["level"])
		# A miniboss reward is unique or set ~8% of the time; those come from their own wide windows (Items.UNIQUE_WINDOW /
		# SET_WINDOW), exactly as the distribution check below exempts them. Plain, magic and rare stay in the tight window.
		var reward_rarity: int = int(drop.item["rarity"])
		var window := Vector2i(-6, 3)
		if reward_rarity == Items.Rarity.UNIQUE:
			window = Items.UNIQUE_WINDOW
		elif reward_rarity == Items.Rarity.SET:
			window = Items.SET_WINDOW
		expect("the reward's item level (%d, rarity %d) sits in its window around the monster's level 18" % [level, reward_rarity],
			level >= 18 + window.x and level <= 18 + window.y)
		expect("the reward has a model on the ground and a plate with a verdict", drop.get_node_or_null("Model") != null and hud.loot_cards.names.any(func(e): return e["drop"] == drop))
		var plates: Array = hud.loot_cards.names.filter(func(e): return e["drop"] == drop)
		if not plates.is_empty():
			expect("the plate's verdict is the appraisal's", int(plates[0]["verdict"]) == LootAppraisal.of(drop.item, stats))
		var item: Dictionary = drop.item.duplicate(true)
		drop.pick_up(player)
		await get_tree().process_frame
		var restored: Dictionary = Items.from_save(Items.to_save(item))
		expect("the reward survives a save: same name, level, rarity and mods", restored["name"] == item["name"] and restored["level"] == item["level"]
			and restored["rarity"] == item["rarity"] and restored["mods"] == item["mods"])
		var carried: bool = stats.bag.any(func(i): return i["name"] == item["name"]) or stats.equipment.values().any(func(i): return i["name"] == item["name"])
		expect("the reward is carried: in the bag or worn", carried)
	zombie.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": player, "skill_id": "basic", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, player.global_position)
	await get_tree().create_timer(0.4).timeout
	expect("a second blow on the corpse drops nothing more", get_tree().get_nodes_in_group("loot").size() == 0)
	# Distribution, deterministic: how often a kill drops gear, its rarity mix and its level window.
	seed(20261013)
	var out_of_window: int = 0
	var rarity := {Items.Rarity.NORMAL: 0, Items.Rarity.MAGIC: 0, Items.Rarity.RARE: 0, Items.Rarity.UNIQUE: 0, Items.Rarity.SET: 0}
	var drops_made: int = 0
	for i in 20000:
		var loot: Dictionary = MonsterLoot.roll(18, "normal", 0.0)
		if loot.item.is_empty():
			continue
		drops_made += 1
		rarity[int(loot.item["rarity"])] += 1
		var lvl: int = int(loot.item["level"])
		if int(loot.item["rarity"]) < Items.Rarity.UNIQUE and (lvl < 18 - 12 or lvl > 18 + 7):
			out_of_window += 1
	print("  loot distribution at monster level 18: ", drops_made, " item drops of 20000 kills, rarity ", rarity)
	expect("an ordinary kill drops gear in roughly a tenth of kills (%d of 20000)" % drops_made, drops_made > 1000 and drops_made < 3000)
	expect("plain and magic gear is most of what drops, rares are rarer (%s)" % [rarity], rarity[Items.Rarity.NORMAL] + rarity[Items.Rarity.MAGIC] > rarity[Items.Rarity.RARE] * 5 and rarity[Items.Rarity.RARE] > 0)
	expect("drops of plain, magic and rare rarity stay near the monster's level (%d outside)" % out_of_window, out_of_window == 0)
	var boss_rare: int = 0
	for i in 400:
		var reward: Dictionary = Items.roll_reward(18, Items.MINIBOSS)
		boss_rare += 1 if int(reward["rarity"]) >= Items.Rarity.RARE else 0
	print("  miniboss rewards rare-or-better: ", boss_rare, " of 400")
	expect("a miniboss reward is a rare or better a fifth of the time (%d of 400)" % boss_rare, boss_rare > 40 and boss_rare < 130)
	_gear(stats)
	_clear_world()
	await get_tree().process_frame
