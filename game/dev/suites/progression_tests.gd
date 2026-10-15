extends DevSuite
## Self-test: progression, XP, level rewards and the save policy.

func _test_class_notice() -> void:
	TownState.persist = false
	TownState.reset()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.queue_free()
	await get_tree().process_frame
	var seen: Array = []
	var on_increase: Callable = func(levels: Dictionary) -> void: seen.append(levels.duplicate())
	TownState.events.class_skills_leveled.connect(on_increase)
	TownState.add_hero_xp(300, false, {"melee": 1})
	expect("earned class level emits its final level once", seen == [{"melee": 1}])
	var label: Label3D
	for node in get_tree().current_scene.get_children():
		if node is Label3D and node.text == "Melee increased to 1": label = node
	expect("class increase appears above the hero", label != null and label.global_position.y > player.global_position.y + player.body_height)
	TownState.add_hero_xp(1, false, {"melee": 1})
	expect("XP within the same class level is silent", seen.size() == 1)
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var path: String = OS.get_environment("TEMP").path_join("curse_class_notice.png")
		get_viewport().get_texture().get_image().save_png(path)
		print("CLASS_NOTICE_CAPTURE ", path)
	await get_tree().create_timer(2.2).timeout
	expect("class notice remains readable beyond its former two-second lifetime", is_instance_valid(label) and label.modulate.a > 0.99)
	await get_tree().create_timer(1.0).timeout
	expect("class text fades", is_instance_valid(label) and label.modulate.a < 1.0)
	await get_tree().create_timer(2.0).timeout
	expect("class text cleans itself up", not is_instance_valid(label))
	TownState.reset()
	expect("reset does not celebrate a class increase", seen.size() == 1)
	var cutter := PartyManager.current().bodies.get("cutter") as Player
	if cutter != null:
		TownState.add_member_xp("cutter", 300, false, {"ranged": 1})
		var cutter_notices := 0
		for node in get_tree().current_scene.get_children():
			if node is Label3D and node.text == "Ranged increased to 1":
				cutter_notices += 1
				expect("inactive member's class notice appears above its earner", Vector2(node.global_position.x - cutter.global_position.x, node.global_position.z - cutter.global_position.z).length() < 0.01)
		expect("inactive member gets one notice without duplicating Hero's legacy event", cutter_notices == 1 and seen.size() == 1)
	TownState.class_xp = {"melee": 299, "ranged": 299, "combat": 299, "nature": 299}
	TownState.add_hero_xp(4, false, {"melee": 1, "ranged": 1, "combat": 1, "nature": 1})
	expect("simultaneous increases combine all four classes into one event", seen.size() == 2 and seen[-1] == {"melee": 1, "ranged": 1, "combat": 1, "nature": 1})
	var combined: bool = false
	for node in get_tree().current_scene.get_children():
		if node is Label3D and node.text.contains("Nature Magic increased to 1"):
			combined = node.text.split("\n").size() == 4
	expect("simultaneous classes share a readable multiline notice", combined)
	TownState.add_hero_xp(7600, false, {"ranged": 1})
	expect("a multi-level jump shows only the final class level", int(seen[-1]["ranged"]) == HeroAttributes.class_level(7900))
	TownState.events.class_skills_leveled.disconnect(on_increase)
	TownState.reset()

## The hero's permanent level: the curve, awarding XP (several levels at once, the cap), saving, loading, repairing and migrating, and
## how the character screen and the HUD show it.
func _test_progression() -> void:
	TownState.persist = false
	TownState.reset()
	var l2: int = HeroProgression.xp_for_level(2)
	expect("a fresh hero is level 1 with 0 XP", TownState.hero_level == 1 and TownState.hero_xp == 0)
	expect("the curve starts at 0 and has a level for each of 1..100", HeroProgression.xp_for_level(1) == 0 and HeroProgression.table().size() == HeroProgression.MAX_LEVEL
		and HeroProgression.MAX_LEVEL == 100)
	var rising: bool = true
	for level in range(2, HeroProgression.MAX_LEVEL + 1):
		rising = rising and HeroProgression.xp_for_level(level) > HeroProgression.xp_for_level(level - 1)
	expect("every level needs more total XP than the one before", rising)
	var samples_ok: bool = true
	for level in HeroProgression.DS2_SAMPLES:
		samples_ok = samples_ok and HeroProgression.xp_for_level(int(level)) == int(HeroProgression.DS2_SAMPLES[level])
	expect("every documented DS2 experience-table point is exact (L2 300, L10 34,200, L30 663,000, L100 1.07 billion)", samples_ok
		and HeroProgression.xp_for_level(2) == 300 and HeroProgression.xp_for_level(30) == 663000 and HeroProgression.max_xp() == 1070000000)
	TownState.add_hero_xp(l2 - 1)
	expect("one XP short of level 2 is still level 1", TownState.hero_level == 1 and TownState.hero_xp == l2 - 1)
	var up: Dictionary = TownState.add_hero_xp(1)
	expect("exactly the level 2 threshold is level 2, and the result says so", TownState.hero_level == 2 and int(up["old_level"]) == 1
		and int(up["new_level"]) == 2 and int(up["levels_gained"]) == 1 and int(up["xp_gained"]) == 1)
	expect("a level is not paid for out of the XP: it is the total", TownState.hero_xp == l2)
	var before: int = TownState.hero_xp
	var none_zero: Dictionary = TownState.add_hero_xp(0)
	var none_neg: Dictionary = TownState.add_hero_xp(-50)
	expect("zero and negative awards change nothing", TownState.hero_xp == before and int(none_zero["xp_gained"]) == 0 and int(none_neg["levels_gained"]) == 0)
	var seen: Array = []
	var on_level: Callable = func(old_level: int, new_level: int, _xp: int) -> void: seen.append([old_level, new_level])
	TownState.events.hero_leveled.connect(on_level)
	var jump: Dictionary = TownState.add_hero_xp(HeroProgression.xp_for_level(5) - TownState.hero_xp)
	expect("one award can gain several levels (2 to 5)", TownState.hero_level == 5 and int(jump["levels_gained"]) == 3 and int(jump["old_level"]) == 2 and int(jump["new_level"]) == 5)
	expect("several levels is one event, old level to new level", seen == [[2, 5]])
	TownState.add_hero_xp(5)
	expect("an award inside a level fires no level event", seen.size() == 1)
	# Fractions, spans and the cap.
	var l3: int = HeroProgression.xp_for_level(3)
	var l4: int = HeroProgression.xp_for_level(4)
	expect("a level's progress is 0 at its start, half-way, and under 1 at its last point", is_equal_approx(HeroProgression.level_fraction(l3), 0.0)
		and is_equal_approx(HeroProgression.level_fraction(l3 + (l4 - l3) / 2), 0.5) and HeroProgression.level_fraction(l4 - 1) < 1.0 and HeroProgression.level_fraction(l4 - 1) > 0.95)
	expect("progress is read as 'into level / level span'", HeroProgression.xp_into_level(l3 + 20) == 20 and HeroProgression.xp_span_of_level(l3) == l4 - l3
		and HeroProgression.xp_to_next_level(l3 + 20) == l4 - l3 - 20 and HeroProgression.progress_text(l3 + 20) == "20 / %d XP" % (l4 - l3))
	TownState.add_hero_xp(HeroProgression.max_xp() * 2)
	expect("a huge award stops at the cap", TownState.hero_level == HeroProgression.MAX_LEVEL and TownState.hero_xp == HeroProgression.max_xp())
	var past: Dictionary = TownState.add_hero_xp(500)
	expect("XP past the cap is not kept and levels nothing", TownState.hero_level == HeroProgression.MAX_LEVEL and TownState.hero_xp == HeroProgression.max_xp()
		and int(past["xp_gained"]) == 0 and int(past["levels_gained"]) == 0 and seen.size() == 2)
	TownState.add_hero_xp(9223372036854775807)
	expect("an enormous award does not overflow", TownState.hero_xp == HeroProgression.max_xp())
	expect("at the cap the bar is full, nothing is left to earn and nothing divides by zero", is_equal_approx(HeroProgression.level_fraction(HeroProgression.max_xp()), 1.0)
		and HeroProgression.xp_to_next_level(HeroProgression.max_xp()) == 0 and HeroProgression.xp_span_of_level(HeroProgression.max_xp()) == 0
		and HeroProgression.progress_text(HeroProgression.max_xp()) == "MAX LEVEL")
	expect("XP is never negative and level never leaves 1..cap", HeroProgression.sanitize_xp(-5) == 0 and HeroProgression.level_for_xp(-5) == 1
		and HeroProgression.level_for_xp(HeroProgression.max_xp() + 1) == HeroProgression.MAX_LEVEL)
	TownState.events.hero_leveled.disconnect(on_level)
	# Developer commands.
	TownState.reset()
	TownState.apply_dev_progression(PackedStringArray(["--level=10"]))
	expect("--level=N sets the hero to the start of that level", TownState.hero_level == 10 and TownState.hero_xp == HeroProgression.xp_for_level(10))
	TownState.apply_dev_progression(PackedStringArray(["--xp=50", "--level=abc"]))
	expect("--xp=N grants XP; a bad value is ignored", TownState.hero_xp == HeroProgression.xp_for_level(10) + 50 and TownState.hero_level == 10)
	# Saving: the save carries the progression, loads it back, and the XP decides the level.
	TownState.reset()
	TownState.add_hero_xp(HeroProgression.xp_for_level(7) + 123)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	expect("the save holds the hero's level and XP", int(saved["hero_xp"]) == HeroProgression.xp_for_level(7) + 123 and int(saved["hero_level"]) == 7)
	TownState.reset()
	TownState.from_dict(TownState.migrate(saved))
	expect("save and load keep the XP and the level it makes", TownState.hero_xp == HeroProgression.xp_for_level(7) + 123 and TownState.hero_level == 7)
	var drifted: Dictionary = saved.duplicate(true)
	drifted["hero_level"] = 25
	TownState.from_dict(TownState.migrate(drifted))
	expect("a saved level that disagrees with the XP is repaired from the XP", TownState.hero_level == 7)
	for bad in [-40, 1e18, "lots", null, [], {}, 12.9, NAN]:
		var broken: Dictionary = saved.duplicate(true)
		broken["hero_xp"] = bad
		broken["hero_level"] = bad
		TownState.from_dict(TownState.migrate(broken))
		expect("a malformed hero_xp (%s) loads as a valid hero" % str(bad), TownState.hero_xp >= 0 and TownState.hero_xp <= HeroProgression.max_xp()
			and TownState.hero_level == HeroProgression.level_for_xp(TownState.hero_xp))
	var no_fields: Dictionary = saved.duplicate(true)
	no_fields.erase("hero_xp")
	no_fields.erase("hero_level")
	TownState.from_dict(TownState.migrate(no_fields))
	expect("a save missing the fields loads at level 1", TownState.hero_level == 1 and TownState.hero_xp == 0)
	# Migration: a version 2 save keeps everything and begins at level 1.
	var v2: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	v2["save_version"] = 2
	v2.erase("hero_xp")
	v2.erase("hero_level")
	v2["gold"] = 311
	v2["day"] = 9
	v2["jobs_done"] = 14   # not a measure of the hero's level
	var migrated: Dictionary = TownState.migrate(v2)
	expect("a version 2 save is migrated to the current version at level 1 with 0 XP", int(migrated["save_version"]) == TownState.SAVE_VERSION
		and int(migrated["hero_level"]) == 1 and int(migrated["hero_xp"]) == 0)
	TownState.reset()
	TownState.from_dict(migrated)
	expect("migrating keeps the gold, day, job count and level 1", TownState.gold == 311 and TownState.day == 9 and TownState.jobs_done == 14
		and TownState.hero_level == 1 and TownState.hero_xp == 0)
	# What it shows: the character screen and the HUD.
	TownState.reset()
	var town := TownScene.new()
	town.with_road = false
	game.add_child(town)
	await get_tree().process_frame
	town.combat_hud._open_character()
	var view: Control = town.combat_hud.character_panel
	expect("a fresh character screen reads Level 1 and 0 / 300 XP", view.level_label.text == "Level 1" and view.xp_label.text == "0 / 300 XP")
	TownState.add_hero_xp(HeroProgression.xp_for_level(2) + 30)
	expect("a level-up keeps the HUD free of a duplicate screen-space plate", town.combat_hud.level_toast_text.is_empty() and town.combat_hud.level_toast_time == 0.0)
	town.combat_hud._open_character()
	view = town.combat_hud.character_panel
	await get_tree().process_frame
	await get_tree().process_frame
	expect("the character screen shows the new level and the progress through it", view.level_label.text == "Level 2"
		and view.xp_label.text == "30 / %d XP" % (HeroProgression.xp_for_level(3) - HeroProgression.xp_for_level(2)))
	var close_button: Button = view.find_children("*", "Button", true, false).back()
	var overlap: bool = false
	for tile in view.find_children("*", "SubViewportContainer", true, false):
		overlap = overlap or (tile as Control).get_global_rect().intersects(view.level_label.get_global_rect()) \
			or (tile as Control).get_global_rect().intersects(view.xp_bar.get_global_rect())
	expect("the level and XP bar do not overlap the portrait", not overlap and view.xp_bar.get_global_rect().size.x > 100.0)
	expect("the character screen keeps its Close button focusable", close_button.focus_mode != Control.FOCUS_NONE and close_button.has_focus())
	expect("the level text sits inside the panel", view.get_global_rect().encloses(view.level_label.get_global_rect()) and view.get_global_rect().encloses(view.xp_bar.get_global_rect()))
	TownState.dev_set_hero_level(HeroProgression.MAX_LEVEL)
	town.combat_hud._open_character()
	view = town.combat_hud.character_panel
	await get_tree().process_frame
	expect("at the cap the screen reads Level 100 and MAX LEVEL", view.level_label.text == "Level %d" % HeroProgression.MAX_LEVEL and view.xp_label.text == "MAX LEVEL")
	town.queue_free()
	await get_tree().process_frame
	TownState.reset()

## Hero Level, world threat, item tier and rarity are four different things, and only the last three are connected: a stronger hero (or one
## who has done more jobs) never makes the world harder; a place or a monster is as dangerous as it is; a drop's tier comes from its source.
func _test_world_progression() -> void:
	TownState.persist = false
	TownState.reset()
	Monsters.in_tests = true
	Monsters.rng.seed = 5
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	# Zone threat and the tier it makes.
	var road_in: float = WorldThreat.for_distance(10.0)
	var deep: float = WorldThreat.for_distance(300.0)
	expect("each stretch has its own threat, rising with distance", is_equal_approx(road_in, TownDb.zone_at(10.0).base_threat) and road_in < WorldThreat.for_distance(100.0)
		and WorldThreat.for_distance(100.0) < WorldThreat.for_distance(170.0) and WorldThreat.for_distance(170.0) < deep)
	# The arena director still runs on its waves.
	var arena_director := RunDirector.new()
	add_child(arena_director)
	arena_director.wave = 6
	expect("the arena scales by its wave and drops by its wave", is_equal_approx(RunDirector.arena_level(1), 1.0) and is_equal_approx(RunDirector.arena_level(6), 1.6)
		and not arena_director.connected() and arena_director.drop_level(9.0) == WorldThreat.monster_level(RunDirector.arena_level(6))
		and arena_director.drop_level_at(Vector3.ZERO) == WorldThreat.monster_level(RunDirector.arena_level(6)))
	arena_director.queue_free()
	# The connected world.
	var town := TownScene.new()
	game.add_child(town)
	var waited: int = 0
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 40) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var crypt: CryptRoad = town.crypt
	var director: RunDirector = town.director
	expect("the world does not borrow an arena wave", director.connected() and director.wave == 0)
	var placed_right: bool = true
	var checked: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and e.group_id >= 1 and e.group_id < 100 and not e.has_meta("monster_uid") and not e.has_meta("quest_uid") and not e.has_meta("exact_level"):
			checked += 1
			placed_right = placed_right and absf(e.level_scale - crypt.threat_at(e.home)) < 0.001
	expect("every ordinary monster on the road has its stretch's threat (%d checked)" % checked, checked > 20 and placed_right)
	var spawn_at: Callable = func(group: int, z: float) -> Enemy:
		crypt._group(group, "", [["zombie", 0.0, z]], Vector2(0.0, z))
		for node in get_tree().get_nodes_in_group("enemies"):
			if (node as Enemy).group_id == group:
				return node as Enemy
		return null
	var near_before: Enemy = spawn_at.call(950, 160.0)
	var far_before: Enemy = spawn_at.call(951, -40.0)
	var first_level: int = director.drop_level_at(crypt.at(0.0, 160.0))
	TownState.dev_set_hero_level(20)
	TownState.jobs_done += 6
	var near_after: Enemy = spawn_at.call(952, 160.0)
	var far_after: Enemy = spawn_at.call(953, -40.0)
	expect("a level 20 hero faces the same Road In zombie as a level 1 hero (%.2f, %.2f)" % [near_before.level_scale, near_after.level_scale],
		is_equal_approx(near_before.level_scale, road_in) and is_equal_approx(near_after.level_scale, near_before.level_scale)
		and is_equal_approx(near_after.max_health, near_before.max_health) and is_equal_approx(near_after.damage_max, near_before.damage_max))
	expect("six more jobs done do not make the road harder either", is_equal_approx(far_after.level_scale, far_before.level_scale) and TownState.jobs_done == 6)
	expect("deeper authored ground is still tougher", far_before.level_scale > near_before.level_scale and far_before.max_health > near_before.max_health)
	expect("the same place drops at the same level whatever the hero is", director.drop_level_at(crypt.at(0.0, 160.0)) == first_level
		and director.drop_level(road_in) == WorldThreat.monster_level(road_in) and director.drop_level(road_in + 1.0) > director.drop_level(road_in))
	for e in [near_before, far_before, near_after, far_after]:
		e.queue_free()
	# A named monster is its own measure, wherever it lives.
	var mon: Dictionary = Monsters.rise()
	mon["kind"] = "zombie"
	mon["dist"] = 20.0
	mon["level"] = 5.0
	town.populate_monsters()
	var body: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("monster_uid"):
			body = node
	var plain: Enemy = spawn_at.call(954, 160.0)
	expect("a level 5 named monster in the Road In is far stronger than the ordinary zombies there", body != null and body.max_health > plain.max_health * 2.0
		and body.damage_max > plain.damage_max * 1.3)
	var named_strength: float = body.max_health
	TownState.dev_set_hero_level(1)
	town.populate_monsters()
	expect("its strength follows its own level, not the hero's", is_equal_approx(body.max_health, named_strength))
	# Its strength is its own threat, set where it is spawned: the marker is only a picture.
	var bare: Enemy = director.spawn_enemy(body.global_position + Vector3(3, 0, 0), "zombie", 5.0)   # the same monster with no marker at all
	var stats_before: Array = [body.level_scale, body.max_health, body.damage_min, body.damage_max, body.armor, body.move_speed]
	MonsterMark.apply_look(body, mon)
	MonsterMark.attach(body, mon)
	var stats_after: Array = [body.level_scale, body.max_health, body.damage_min, body.damage_max, body.armor, body.move_speed]
	expect("a named monster's level_scale is its own level", is_equal_approx(body.level_scale, 5.0) and is_equal_approx(bare.level_scale, 5.0))
	expect("the marker changes no combat statistic", stats_before == stats_after)
	expect("a named monster with no marker has exactly the same strength", is_equal_approx(bare.max_health, body.max_health)
		and is_equal_approx(bare.damage_min, body.damage_min) and is_equal_approx(bare.damage_max, body.damage_max) and is_equal_approx(bare.armor, body.armor))
	bare.set_threat(2.0)
	expect("a body can be given a new threat in place: health and damage follow, the share of health stays", is_equal_approx(bare.max_health, MonsterScaling.life(WorldThreat.monster_level(2.0), "normal"))
		and bare.level == WorldThreat.monster_level(2.0)
		and is_equal_approx(bare.health, bare.max_health) and is_equal_approx(bare.level_scale, 2.0))
	bare.queue_free()
	var loot_before: int = get_tree().get_nodes_in_group("loot").size()
	director._report_to_quests(body)
	var levels: Array[int] = []
	for node in get_tree().get_nodes_in_group("loot"):
		levels.append(int((node as LootDrop).item["level"]))
	var named_level: int = WorldThreat.monster_level(5.0)
	expect("its drops are rare or better at its own level (%s, its level %d), not the road's" % [str(levels), named_level],
		get_tree().get_nodes_in_group("loot").size() > loot_before and levels.all(func(l: int) -> bool: return l <= named_level + 3)
		and levels.max() > WorldThreat.monster_level(road_in) + 5)
	# A quest's unique monster has an absolute threat on the same scale.
	var uniques: Array = TownDb.quests().values().filter(func(q: QuestDef) -> bool: return q.kind == "slay_unique")
	expect("a unique quest monster has its own absolute threat, on the zones' scale", not uniques.is_empty()
		and uniques.all(func(q: QuestDef) -> bool: return q.unique_level >= 1.0 and q.unique_level <= 3.0))
	plain.queue_free()
	# Rarity is not level: a guaranteed reward is rare or better, but from the same window around its source's level.
	var reward_ok: bool = true
	for i in 120:
		var reward: Dictionary = Items.roll_reward(3)
		reward_ok = reward_ok and int(reward["rarity"]) >= Items.Rarity.RARE and int(reward["level"]) <= 3 + 3
	expect("a reward is rare or better and no higher in level for it", reward_ok)
	# The shops and quest rewards do not read jobs done.
	var shop_level: int = WorldThreat.monster_level(WorldThreat.MERCHANT_THREAT)
	var in_window: Callable = func(i: Dictionary) -> bool: return int(i["level"]) >= shop_level - 4 and int(i["level"]) <= shop_level + 1
	TownState.jobs_done = 0
	var shop_a: Array[Dictionary] = Items.roll_choices(shop_level)
	TownState.jobs_done = 40
	var shop_b: Array[Dictionary] = Items.roll_choices(shop_level)
	expect("merchant stock is around a fixed explicit level (%d), whatever has been done" % shop_level, shop_a.all(in_window) and shop_b.all(in_window))
	TownState.stash = []
	Quests.apply_bundle({"item": 1})
	Quests.apply_bundle({"item": 1, "threat": 4.0})
	expect("a quest reward item's level comes from its own named source threat, not jobs done",
		int(TownState.stash[0]["level"]) <= WorldThreat.monster_level(WorldThreat.QUEST_REWARD_THREAT) + 3
		and int(TownState.stash[1]["level"]) <= WorldThreat.monster_level(4.0) + 3 and int(TownState.stash[1]["rarity"]) >= Items.Rarity.RARE)
	town.queue_free()
	await get_tree().process_frame
	TownState.reset()
	Monsters.in_tests = false

## The gameplay XP economy: what pays, what does not (no renewable summons, no kills the hero had no hand in), that rewards are paid once, and
## that the hero's level never changes what a source is worth.
func _test_xp() -> void:
	TownState.persist = false
	TownState.reset()
	Monsters.in_tests = true
	Monsters.rng.seed = 5
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	var town := TownScene.new()
	game.add_child(town)
	var waited: int = 0
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 40) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var director: RunDirector = town.director
	var crypt: CryptRoad = town.crypt
	var hero: Player = town.player
	var spot: Vector3 = crypt.at(0.0, 150.0)
	# DS2's values: a monster's XP by its level and tier, the level gap, the party.
	expect("DS2 monster XP: 48 + 12L under level 12 (level 1 normal 60, level 3 normal 84), the steeper curve above",
		HeroProgression.monster_xp(1) == 60 and HeroProgression.monster_xp(3) == 84 and HeroProgression.monster_xp(11) == 180
		and HeroProgression.monster_xp(20) == int(round(6480.0 * pow(1.11, 20) / (5.4 * 30))))
	expect("tiers: trivial < weak < normal < strong < miniboss", HeroProgression.monster_xp(5, "trivial") < HeroProgression.monster_xp(5, "weak")
		and HeroProgression.monster_xp(5, "weak") < HeroProgression.monster_xp(5) and HeroProgression.monster_xp(5) < HeroProgression.monster_xp(5, "strong")
		and HeroProgression.monster_xp(5, "strong") < HeroProgression.monster_xp(5, "miniboss"))
	expect("the level gap: full within 4 levels, -20% a level beyond, either way, never under 5%", HeroProgression.level_gap_mult(10, 6) == 1.0
		and HeroProgression.level_gap_mult(10, 14) == 1.0 and is_equal_approx(HeroProgression.level_gap_mult(10, 5), 0.8)
		and is_equal_approx(HeroProgression.level_gap_mult(2, 10), 0.2) and is_equal_approx(HeroProgression.level_gap_mult(40, 1), 0.05))
	expect("a party of two gets 180% shared: 90% each", HeroProgression.party_share(100, 2) == 90 and HeroProgression.party_share(100, 1) == 100
		and HeroProgression.party_share(100, 4) == 73)
	var members: int = 2 if not town.companion.dead else 1   # Cutter is a party member: he takes his share
	var expected: Callable = func(kind: String, threat: float) -> int:
		var level: int = WorldThreat.monster_level(threat)
		var gap: float = HeroProgression.level_gap_mult(TownState.hero_level, level)
		return HeroProgression.party_share(int(round(HeroProgression.monster_xp(level, EnemyDb.get_def(kind).tier) * gap)), members)
	# A kill the hero is credited with pays; the same kill in a stronger place pays more.
	var kill: Callable = func(kind: String, threat: float, credited: bool) -> int:
		var before: int = TownState.hero_xp
		var e: Enemy = director.spawn_enemy(spot, kind, threat)
		await get_tree().process_frame
		if credited:
			e.credit_hero()
		e._apply_damage(e.max_health + 10.0)
		await get_tree().process_frame
		return TownState.hero_xp - before
	var zombie_xp: int = await kill.call("zombie", 1.25, true)
	expect("a level 1 zombie pays DS2's 60, shared with Cutter (%d)" % zombie_xp, zombie_xp == expected.call("zombie", 1.25) and zombie_xp == 54)
	var cutter_before: int = TownState.cutter_xp
	var brute_near: int = await kill.call("brute", 1.25, true)
	expect("Cutter takes his own share of a kill", TownState.cutter_xp - cutter_before == brute_near)
	expect("a Brute pays more than a zombie (%d)" % brute_near, brute_near == expected.call("brute", 1.25) and brute_near > zombie_xp)
	TownState.dev_set_hero_level(20)
	var brute_high: int = await kill.call("brute", 1.25, true)
	expect("a level 20 hero gets little for a level 1 Brute: DS2's level gap (%d)" % brute_high, brute_high == expected.call("brute", 1.25) and brute_high < brute_near / 5)
	TownState.dev_set_hero_level(1)
	# Credit: burn, collision, and monsters hurting each other.
	var uncredited: int = await kill.call("zombie", 1.25, false)
	expect("a death the hero had no hand in pays nothing", uncredited == 0)
	var burner: Enemy = director.spawn_enemy(spot, "brute", 1.25)
	await get_tree().process_frame
	var xp_before: int = TownState.hero_xp
	burner.apply_burn(5000.0, 2.0, true)
	burner._tick_burn(0.1)
	await get_tree().process_frame
	expect("a kill by fire the hero lit is theirs", burner.dead and TownState.hero_xp - xp_before == brute_near)
	var other_fire: Enemy = director.spawn_enemy(spot, "brute", 1.25)
	await get_tree().process_frame
	xp_before = TownState.hero_xp
	other_fire.apply_burn(5000.0, 2.0)   # a monster's fire, not the hero's
	other_fire._tick_burn(0.1)
	await get_tree().process_frame
	expect("a kill by fire the hero did not light is not", other_fire.dead and TownState.hero_xp == xp_before)
	var thrown: Enemy = director.spawn_enemy(spot, "zombie", 1.25)
	var struck: Enemy = director.spawn_enemy(spot + Vector3(2, 0, 0), "brute", 1.25)
	await get_tree().process_frame
	xp_before = TownState.hero_xp
	thrown.credit_hero()
	thrown.ragdoll_launch(Vector3(12, 0, 0), 2.0, Vector3(0, 0, 4))
	await get_tree().create_timer(0.5).timeout
	expect("a credited flying body cannot damage a bystander or award collision XP", not struck.dead and struck.health == struck.max_health
		and TownState.hero_xp == xp_before)
	var biter: Enemy = director.spawn_enemy(spot, "brute", 1.25)
	var bitten: Enemy = director.spawn_enemy(spot + Vector3(2, 0, 0), "brute", 1.25)
	await get_tree().process_frame
	xp_before = TownState.hero_xp
	var tries: int = 0
	while not bitten.dead and tries < 30:
		tries += 1
		bitten.receive(Combat.resolve(biter, bitten, 5000.0, Combat.DamageType.PHYSICAL, false, 1.0), biter.global_position)
	await get_tree().process_frame
	expect("monsters killing each other earns nothing", bitten.dead and TownState.hero_xp == xp_before)
	# Renewable summons pay nothing; finite spawns do.
	var priest: Enemy = director.spawn_enemy(spot, "priest", 1.25)
	await get_tree().process_frame
	var support: SupportBehavior = priest.behavior as SupportBehavior
	var before_summons: int = get_tree().get_nodes_in_group("enemies").size()
	support._summon()
	var summoned: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var s := node as Enemy
		if s != null and not s.xp_eligible:
			summoned.append(s)
	expect("a priest's summons are marked as paying nothing", summoned.size() >= 2 and get_tree().get_nodes_in_group("enemies").size() > before_summons)
	xp_before = TownState.hero_xp
	for s in summoned:
		s.credit_hero()
		s._apply_damage(s.max_health + 10.0)
	await get_tree().process_frame
	expect("killing summons, credited or not, earns no XP", TownState.hero_xp == xp_before)
	var horde_mon: Dictionary = Monsters.rise()
	horde_mon["dist"] = 20.0
	horde_mon["level"] = 2.0
	var group_before: Dictionary = {}
	crypt.spawn_horde(horde_mon, 3)
	var horde: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var h := node as Enemy
		if h != null and h.group_id == 600 + int(horde_mon["uid"]):
			horde.append(h)
	expect("an uprising's horde and the road's own groups are worth XP", horde.size() == 3 and horde.all(func(h: Enemy) -> bool: return h.xp_eligible)
		and get_tree().get_nodes_in_group("enemies").filter(func(n: Node) -> bool: return (n as Enemy).group_id in range(1, 6) and (n as Enemy).xp_eligible).size() > 0)
	for h in horde:
		h.queue_free()
	Monsters.killed(int(horde_mon["uid"]))
	# Named monsters: their own level, their history, their plot; once.
	var mon: Dictionary = Monsters.rise()
	mon["kind"] = "zombie"
	mon["dist"] = 20.0
	mon["level"] = 2.0
	mon["kills"] = 0
	mon["plot"] = {}
	town.populate_monsters()
	var body: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("monster_uid") and int(node.get_meta("monster_uid")) == int(mon["uid"]):
			body = node
	var named_level: int = WorldThreat.monster_level(2.0)
	var bounty: int = HeroProgression.named_xp(named_level, 0, false)
	expect("a named monster's bounty is a miniboss of its level", bounty == HeroProgression.monster_xp(named_level, "miniboss"))
	expect("a monster that has killed the hero is worth more, and so is one with a plot", HeroProgression.named_xp(named_level, 2, false) == bounty + 2 * HeroProgression.NEMESIS_PER_KILL
		and HeroProgression.named_xp(named_level, 0, true) == bounty + HeroProgression.PLOT_BONUS_XP)
	xp_before = TownState.hero_xp
	body.credit_hero()
	body._apply_damage(body.max_health + 10.0)
	await get_tree().process_frame
	var paid: int = TownState.hero_xp - xp_before
	var named_total: int = HeroProgression.monster_xp(named_level, "normal") + bounty
	expect("killing a named monster pays its kill value and its bounty, gap and party applied (%d)" % paid,
		paid == HeroProgression.party_share(int(round(named_total * HeroProgression.level_gap_mult(TownState.hero_level, named_level))), members))
	var again: int = director._report_to_quests(body)
	expect("the bounty is paid once", again == 0 and TownState.hero_xp - xp_before == paid)
	var strong: Dictionary = Monsters.rise()
	strong["kind"] = "zombie"
	strong["dist"] = 20.0
	strong["level"] = 5.0
	strong["kills"] = 2
	strong["plot"] = {"type": "raid", "days_left": 2, "total": 3}
	town.populate_monsters()
	var strong_body: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("monster_uid") and int(node.get_meta("monster_uid")) == int(strong["uid"]):
			strong_body = node
	xp_before = TownState.hero_xp
	strong_body.credit_hero()
	strong_body._apply_damage(strong_body.max_health + 10.0)
	await get_tree().process_frame
	var strong_paid: int = TownState.hero_xp - xp_before
	expect("a stronger nemesis that beat the hero twice, with a plot, pays much more (%d)" % strong_paid, strong_paid > paid * 2)
	# Nests: once each, when they break.
	var nest_xp: int = HeroProgression.nest_xp(WorldThreat.monster_level(crypt.threat_at(crypt.nests[0].global_position)))
	xp_before = TownState.hero_xp
	crypt.nests[0].hit(9999.0, Vector3.FORWARD)
	await get_tree().process_frame
	var after_nest: int = TownState.hero_xp
	crypt.nests[0].hit(9999.0, Vector3.FORWARD)
	await get_tree().process_frame
	expect("a nest pays its miniboss XP with party share, once", after_nest - xp_before == HeroProgression.party_share(nest_xp, PartyManager.current().living().size()) and TownState.hero_xp == after_nest)
	# The standing quest: on hand-in, once.
	TownState.board[0]["ready"] = true
	xp_before = TownState.hero_xp
	var claimed: Dictionary = TownState.claim_ready()
	var after_claim: int = TownState.hero_xp
	var claimed_again: Dictionary = TownState.claim_ready()
	expect("handing in the standing quest pays shared XP once", after_claim - xp_before == HeroProgression.party_share(HeroProgression.STANDING_QUEST_XP, PartyManager.current().living().size()) and int(claimed["xp"]) == HeroProgression.STANDING_QUEST_XP
		and int(claimed_again["count"]) == 0 and TownState.hero_xp == after_claim)
	expect("the new standing quest carries its XP", int(TownState.board[0].get("xp", 0)) == HeroProgression.STANDING_QUEST_XP)
	# Dynamic quests: the quest's own XP, once; matters pay none.
	var inst: Dictionary = Quests.post("ghoul_cull")
	inst["state"] = "ready"
	xp_before = TownState.hero_xp
	var first: Dictionary = Quests.claim(int(inst["uid"]))
	var after_first: int = TownState.hero_xp
	var second: Dictionary = Quests.claim(int(inst["uid"]))
	expect("a quest pays its written XP with party share once (%d)" % (after_first - xp_before), bool(first["ok"]) and after_first - xp_before == HeroProgression.party_share(int(TownDb.quest("ghoul_cull").reward["xp"]), PartyManager.current().living().size())
		and not bool(second["ok"]) and TownState.hero_xp == after_first)
	var matter: QuestDef = TownDb.quest("fever")
	expect("a matter in town pays no XP", not matter.reward.has("xp"))
	# Saving: XP is in memory at once, written lazily for kills, kept across a reload, and never lost on death.
	TownState.flush_progression(true)
	expect("nothing waits for the disk after a flush", not TownState.has_unsaved_xp())
	TownState.add_hero_xp(1, false)
	expect("an ordinary kill's XP waits to be saved, and is in the save data already", TownState.has_unsaved_xp() and int(TownState.to_dict()["hero_xp"]) == TownState.hero_xp)
	TownState.flush_progression(true)
	var saved: Variant = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	var kept: int = TownState.hero_xp
	var kept_level: int = TownState.hero_level
	TownState.from_dict(TownState.migrate(saved))
	expect("save and load keep XP earned in play", TownState.hero_xp == kept and TownState.hero_level == kept_level)
	hero._apply_damage(hero.max_health + 100.0)
	await get_tree().create_timer(3.6).timeout
	expect("dying costs no XP and control passes to the survivor", TownState.hero_xp == kept and hero.dead and PartyManager.current().active_body() == town.companion)
	# Continue the Hero-specific UI checks after explicitly reviving and selecting him.
	hero.revive_at(hero.global_position)
	PartyManager.current().select("hero")
	# Levels from one reward: one event, one plate; the cap; the open character screen.
	TownState.dev_set_hero_level(1)
	var events: Array = []
	var on_level: Callable = func(old_level: int, new_level: int, _xp: int) -> void: events.append([old_level, new_level])
	TownState.events.hero_leveled.connect(on_level)
	town.combat_hud._open_character()
	var view: Control = town.combat_hud.character_panel
	TownState.add_hero_xp(HeroProgression.xp_for_level(4) + 10)
	expect("one large reward emits one level-up event without a duplicate HUD plate", events == [[1, 4]] and town.combat_hud.level_toast_text.is_empty())
	expect("an open character screen follows the XP without being reopened", view.level_label.text == "Level 4" and view.xp_label.text == HeroProgression.progress_text(TownState.hero_xp)
		and town.combat_hud.character_panel == view)
	TownState.add_hero_xp(HeroProgression.max_xp() * 2)
	expect("and it follows to MAX LEVEL", view.level_label.text == "Level %d" % HeroProgression.MAX_LEVEL and view.xp_label.text == "MAX LEVEL")
	var capped_events: int = events.size()
	var at_cap: int = await kill.call("brute", 3.0, true)
	expect("at the cap XP stops and nothing levels", at_cap == 0 and TownState.hero_level == HeroProgression.MAX_LEVEL and TownState.hero_xp == HeroProgression.max_xp() and events.size() == capped_events)
	TownState.events.hero_leveled.disconnect(on_level)
	# Diagnostics change nothing.
	TownState.dev_set_hero_level(1)
	var enemies_before: int = get_tree().get_nodes_in_group("enemies").size()
	var xp_now: int = TownState.hero_xp
	var report_a: Dictionary = director.xp_report()
	var report_b: Dictionary = director.xp_report()
	expect("the XP report reads the road and changes nothing", report_a == report_b and int(report_a["total"]) > 0 and TownState.hero_xp == xp_now
		and get_tree().get_nodes_in_group("enemies").size() == enemies_before)
	# The marker is only a picture: its size, never the body's collision.
	var marked: Enemy = director.spawn_enemy(spot, "zombie", 2.0)
	await get_tree().process_frame
	var shape: CollisionShape3D = marked.find_children("*", "CollisionShape3D", false, false)[0]
	var radius_before: float = (shape.shape as CapsuleShape3D).radius if shape.shape is CapsuleShape3D else 0.0
	var gameplay_before: Array = [marked.body_radius, marked.level_scale, marked.max_health, marked.damage_max, marked.armor, shape.scale, shape.transform.origin]
	MonsterMark.apply_look(marked, {"level": 9.0})
	var gameplay_after: Array = [marked.body_radius, marked.level_scale, marked.max_health, marked.damage_max, marked.armor, shape.scale, shape.transform.origin]
	var radius_after: float = (shape.shape as CapsuleShape3D).radius if shape.shape is CapsuleShape3D else 0.0
	expect("the marker changes no collision or combat value", gameplay_before == gameplay_after and is_equal_approx(radius_before, radius_after))
	town.queue_free()
	await get_tree().process_frame
	TownState.reset()
	Monsters.in_tests = false

## Where a session may save: a developer session (any user argument) never uses the production save unless it says so, loudly.
func _test_save_policy() -> void:
	var production: String = SavePolicy.PRODUCTION_PATH
	var normal: PackedStringArray = PackedStringArray([])
	expect("a normal launch uses the production save path and saves only when saving is enabled", SavePolicy.path_for(normal) == production and SavePolicy.persists_by_default(normal) == SavePolicy.SAVING_ENABLED
		and not SavePolicy.is_dev_session(normal))
	var sessions: Dictionary = {"self-test": ["--selftest", "--only=xp"], "screenshot": ["--townshot", "--zoom=4"], "xp demo": ["--townshot", "--xpdemo", "--xplog"],
		"xp report": ["--townshot", "--xpreport"], "threats": ["--townshot", "--threats", "--road=40"], "item sheet": ["--itemsheet", "--gear"],
		"developer level": ["--level=10"], "an unknown future flag": ["--some-new-debug-mode"], "pose": ["--poses"]}
	var all_isolated: bool = true
	for label in sessions:
		var args := PackedStringArray(sessions[label])
		var isolated: bool = SavePolicy.is_dev_session(args) and SavePolicy.path_for(args) != production and not SavePolicy.persists_by_default(args) \
			and not SavePolicy.may_modify(production, args) and SavePolicy.may_modify(SavePolicy.DEV_PATH, args)
		if not isolated:
			print("  not isolated: ", label)
		all_isolated = all_isolated and isolated
	expect("every developer mode (self-test, screenshots, XP diagnostics, item sheets, dev commands, flags not yet written) is kept off the production save", all_isolated)
	var opted_in := PackedStringArray(["--townshot", SavePolicy.REAL_SAVE_FLAG])
	expect("only the explicit flag lets a developer session use the production save", SavePolicy.path_for(opted_in) == production and SavePolicy.persists_by_default(opted_in) == SavePolicy.SAVING_ENABLED
		and SavePolicy.may_modify(production, opted_in) and not SavePolicy.allows_production(PackedStringArray(["--xp=5", "--allow-real-save"])))
	expect("the override flag is not something an ordinary argument could be", SavePolicy.REAL_SAVE_FLAG == "--write-production-save")
	var selftest := PackedStringArray(["--selftest"])
	expect("cleanup in a developer session cannot delete the production save, and backups and copies of it are refused too",
		not SavePolicy.may_modify(production, selftest) and not SavePolicy.may_modify(production + ".tmp", selftest) and not SavePolicy.may_modify(production + ".newer.bak", selftest)
		and SavePolicy.may_modify(production, normal))
	# This very session.
	var args: PackedStringArray = OS.get_cmdline_user_args()
	expect("this self-test session is a developer session with its own save file", SavePolicy.is_dev_session(args) and TownState.save_path() == SavePolicy.DEV_PATH
		and TownState.save_path() != production)
	# What saving does here: writes the developer file, leaves the production file exactly as it was.
	var production_before: int = FileAccess.get_modified_time(production) if FileAccess.file_exists(production) else -1
	var production_size: int = FileAccess.open(production, FileAccess.READ).get_length() if FileAccess.file_exists(production) else -1
	var was_persisting: bool = TownState.persist
	TownState.reset()
	TownState.persist = true
	TownState.gold = 12345
	TownState.save()
	var dev_written: bool = FileAccess.file_exists(SavePolicy.DEV_PATH)
	var production_after: int = FileAccess.get_modified_time(production) if FileAccess.file_exists(production) else -1
	var production_size_after: int = FileAccess.open(production, FileAccess.READ).get_length() if FileAccess.file_exists(production) else -1
	expect("even with saving switched on a self-test writes only its own file and leaves the production save untouched", dev_written and production_after == production_before
		and production_size_after == production_size)
	var reloaded_ok: bool = false
	TownState.gold = 1
	TownState.load_or_start()
	reloaded_ok = TownState.gold == 12345
	expect("and reads it back from there", reloaded_ok)
	expect("the session's own cleanup removes the developer file and nothing else", SavePolicy.delete_session_save(args) and not FileAccess.file_exists(SavePolicy.DEV_PATH)
		and (FileAccess.get_modified_time(production) if FileAccess.file_exists(production) else -1) == production_before)
	TownState.persist = was_persisting
	TownState.persist = false
	TownState.reset()

## A kill in an authored location (the dungeon, `--dungeon`) pays the hero's XP and the class skill of the weapon that did the damage,
## the same as a kill on the road. The director runs with `location` set and `world_mode` off, as the dungeon's does.
func _test_dungeon_kill_xp() -> void:
	TownState.persist = false
	TownState.reset()
	var place := CryptRoad.new()
	place.arena = game.arena   # only the location's distance from the gate is read (threat_at), not its built props
	var dungeon := RunDirector.new()
	dungeon.player = player
	dungeon.location = place
	game.add_child(dungeon)
	expect("the dungeon is a connected location without world mode", dungeon.connected() and not dungeon.world_mode)
	var enemy: Enemy = dungeon.spawn_enemy(player.global_position + Vector3(2.0, 0.0, 0.0), "zombie", 1.0)
	enemy.aggro_range = 0.0
	enemy.member_damage = {"hero": {"melee": 60.0}}
	var xp_before: int = TownState.hero_xp
	var melee_before: int = int(TownState.class_xp.get("melee", 0))
	enemy.credit_hero()
	enemy._apply_damage(enemy.max_health + 10.0)
	for i in 3:
		await get_tree().process_frame
	expect("a kill in the dungeon raises the hero's XP (%d -> %d)" % [xp_before, TownState.hero_xp], TownState.hero_xp > xp_before)
	expect("a kill in the dungeon raises the melee class XP (%d -> %d)" % [melee_before, int(TownState.class_xp.get("melee", 0))],
		int(TownState.class_xp.get("melee", 0)) > melee_before)
	dungeon.queue_free()
	await get_tree().process_frame
	place.free()   # never added to the tree
	TownState.reset()
