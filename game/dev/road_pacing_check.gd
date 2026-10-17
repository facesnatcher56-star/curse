extends SceneTree
var failures := 0
var town: TownScene

func _init() -> void: call_deferred("run")

func check(label: String, ok: bool) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	TownState.persist = false
	TownState.reset()
	seed(12102026)
	town = TownScene.new()
	root.add_child(town)
	current_scene = town
	for frame in 300:
		await physics_frame
		if town.director != null and not get_nodes_in_group("enemies").is_empty() and Nav.ready(town.player): break
	town.set_process(false)
	town.set_physics_process(false)
	var hero := PartyManager.current().bodies.hero as Player
	var cutter := PartyManager.current().bodies.cutter as Player
	var continuous := OS.get_cmdline_user_args().has("--continuous")
	var switching := OS.get_cmdline_user_args().has("--switching")
	var switches := 0
	var visible := OS.get_cmdline_user_args().has("--visible")
	if visible:
		var dimensions := Vector2i(2560, 1440) if OS.get_cmdline_user_args().has("--1440") else Vector2i(1920, 1080)
		root.mode = Window.MODE_WINDOWED
		root.borderless = true
		var screen := 1 if dimensions.y == 1080 and DisplayServer.get_screen_count() > 1 else 0
		root.current_screen = screen
		root.size = dimensions
		root.position = DisplayServer.screen_get_position(screen)
		GameSettings.ui_size = 1.0
		GameSettings.apply_ui_scale()
	hero.set_physics_process(false)
	cutter.set_physics_process(false)
	var groups := {}
	for enemy: Enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(continuous)
		if not groups.has(enemy.group_id): groups[enemy.group_id] = []
		groups[enemy.group_id].append(enemy)
		check("no legacy hazard enemies %d" % enemy.group_id, enemy.variant in ["zombie", "rock_thrower"])
	check("at least 14 deliberately separated packs", groups.size() >= 14)
	for id in groups:
		check("group %d is a 4-8 body pack" % id, groups[id].size() >= RoadEncounterRoster.PACK_MIN and groups[id].size() <= RoadEncounterRoster.PACK_MAX)
		for enemy: Enemy in groups[id]:
			if id <= 3: check("opening HP < 8, damage max <= 6.5", enemy.max_health < 8 and enemy.damage_max <= 6.5)
	# Real attack controllers and enemy physics: no direct receive(), stat buffs or purchased powers.
	var fight_ids: Array = [1, 2, 3, 4, 5]
	if OS.get_cmdline_user_args().has("--full-road"): fight_ids = [1, 2, 3, 4, 5, 6, 8, 9, 11, 12, 13, 14, 15, 27]
	if OS.get_cmdline_user_args().has("--loot-only"): fight_ids = []
	for id in fight_ids:
		var pack: Array = groups[id]
		var centre: Vector3 = pack[0].global_position
		if not continuous:
			hero.global_position = Nav.snap(hero, centre + Vector3(0, 0, 5))
			cutter.global_position = Nav.snap(cutter, centre + Vector3(2, 0, 7))
		for enemy: Enemy in pack:
			enemy.process_mode = Node.PROCESS_MODE_INHERIT
			enemy.set_physics_process(true)
			if not continuous: enemy.wake()
		var elapsed := 0
		for frame in 3600:
			await physics_frame
			elapsed = frame
			var live: Array = pack.filter(func(e): return is_instance_valid(e) and not e.dead)
			if live.is_empty() or hero.dead: break
			if switching and frame % 180 == 0:
				Input.action_release("click")
				PartyManager.current().cycle()
				switches += 1
				PartyManager.current().active_body()._physics_process(1.0 / 60.0) # Release held input before new orders.
			var active := PartyManager.current().active_body()
			var other := cutter if active == hero else hero
			active.cursor_override = live[0].global_position
			active.attack_target = live[0]
			Input.action_press("click")
			active._physics_process(1.0 / 60.0)
			if active.health < active.max_health * 0.4: active.skills.drink_potion()
			other._physics_process(1.0 / 60.0)
		check("starter party clears group %d without death within 60s" % id, not hero.dead and not cutter.dead and pack.all(func(e): return not is_instance_valid(e) or e.dead))
		print("FIGHT group=", id, " seconds=", elapsed / 60.0, " HP=", hero.health, " XP=", hero.character.xp, " level=", hero.character.level)
		if visible:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("curse_pace_traversal_%d_group%d.png" % [root.size.y, id]))
		Input.action_release("click")
		if hero.dead: break
		# Only ordinary 1% regeneration during a short recovery pause.
		for frame in 300:
			await physics_frame
			hero.stats.regen(1.0 / 60.0)
			cutter.stats.regen(1.0 / 60.0)
	if not fight_ids.is_empty(): check("opening earns level two", hero.character.level >= 2)
	if switching:
		check("switching occurs during real combat", switches >= fight_ids.size())
		await integrated_checks(hero, cutter)
	TownState.mana_potions = 2
	hero.stats.mana = 0
	check("mana potion restores resource and consumes one shared potion", hero.stats.use_mana_potion() and hero.stats.mana > 0 and TownState.mana_potions == 1)
	check("mana count serialized", int(TownState.to_dict().mana_potions) == 1)
	var mana_pickup := HealthOrb.new()
	mana_pickup.is_mana = true
	town.add_child(mana_pickup)
	mana_pickup.global_position = hero.global_position
	hero.stats.collect_orbs()
	check("mana pickup adds one to party inventory", TownState.mana_potions == 2)
	cutter.global_position = hero.global_position
	cutter.stats.collect_orbs()
	check("two members cannot collect one potion in the same frame", TownState.mana_potions == 2)
	await process_frame
	var gold_before := TownState.gold
	var gold_pickup := HealthOrb.new()
	gold_pickup.gold_amount = 5
	town.add_child(gold_pickup)
	gold_pickup.global_position = hero.global_position
	hero.stats.collect_orbs()
	cutter.stats.collect_orbs()
	check("two members cannot duplicate a gold pickup", TownState.gold == gold_before + 5)
	await process_frame
	var gear_pickup := LootDrop.new()
	gear_pickup.item = Items.starting_gear()[0].duplicate(true)
	town.add_child(gear_pickup)
	var bag_before := hero.stats.bag.size()
	gear_pickup.pick_up(hero)
	gear_pickup.pick_up(cutter)
	check("two members cannot duplicate equipment", hero.stats.bag.size() == bag_before + 1)
	await process_frame
	PartyManager.current().select("cutter")
	cutter.stats.mana = 0
	check("switching spends shared supply on the selected character", cutter.stats.use_mana_potion() and TownState.mana_potions == 1 and cutter.stats.mana > 0)
	var saved := TownState.to_dict()
	var hero_xp := hero.character.xp
	var cutter_xp := cutter.character.xp
	TownState.mana_potions = 99
	TownState.from_dict(saved)
	check("reload preserves mana inventory and both members' XP", TownState.mana_potions == 1 and PartyManager.current().member("hero").xp == hero_xp and PartyManager.current().member("cutter").xp == cutter_xp)
	var counts := {"gold": 0, "health": 0, "mana": 0, "item": 0}
	for i in 20000:
		var loot := MonsterLoot.roll(2, "weak")
		for kind in counts:
			if (not loot.item.is_empty()) if kind == "item" else int(loot[kind]) > 0: counts[kind] += 1
	print("LOOT weak 20000 rolls ", counts)
	check("weak gold approximately 14%", counts.gold > 2500 and counts.gold < 3100)
	check("weak health approximately 4%", counts.health > 650 and counts.health < 950)
	check("weak mana approximately 2.4%", counts.mana > 350 and counts.mana < 620)
	check("weak equipment approximately 5.75%", counts.item > 950 and counts.item < 1350)
	print("ROAD PACING failures=", failures)
	quit(1 if failures else 0)

func integrated_checks(hero: Player, cutter: Player) -> void:
	# Controlled fixture placement below is explicit: this checks the connected
	# systems after real fights, not a claim of uninterrupted full-road playthrough.
	for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	Input.action_release("click")
	for body in [hero, cutter]:
		body.skills.cancel_action()
		body.attack_target = null
	var pickups := {"gold": 0, "health": 0, "mana": 0, "gear": 0}
	for orb: HealthOrb in get_nodes_in_group("orbs"):
		var kind := "gold" if orb.gold_amount > 0 else ("mana" if orb.is_mana else "health")
		pickups[kind] += 1
		hero.global_position = Vector3(orb.global_position.x, 0, orb.global_position.z)
		hero.stats.collect_orbs()
		await process_frame
	for drop: LootDrop in get_nodes_in_group("loot"):
		var before := hero.stats.bag.size()
		drop.pick_up(hero)
		check("real kill equipment enters shared backpack", hero.stats.bag.size() == before + 1)
		pickups.gear += 1
	print("ACTUAL KILL PICKUPS ", pickups)
	check("real kills generate collectible loot", pickups.values().reduce(func(a, b): return a + b, 0) > 0)
	for nest: Destructible in town.crypt.nests:
		var before_hero := hero.character.xp
		var before_cutter := cutter.character.xp
		var reward := HeroProgression.nest_xp(WorldThreat.monster_level(town.crypt.threat_at(nest.global_position)))
		var share := HeroProgression.party_share(reward, 2)
		nest.hit(999.0, Vector3.FORWARD)
		check("nest pays both living members their party share", hero.character.xp == before_hero + share and cutter.character.xp == before_cutter + share)
		nest.hit(999.0, Vector3.FORWARD)
		check("broken nest never pays twice", hero.character.xp == before_hero + share and cutter.character.xp == before_cutter + share)
		for enemy in get_nodes_in_group("enemies"): enemy.set_physics_process(false)
	check("three nests mark standing quest ready", town.crypt.nests_destroyed == 3 and TownState.has_reward())
	var before_hero := hero.character.xp
	var before_cutter := cutter.character.xp
	var paid := TownState.claim_ready()
	var quest_share := HeroProgression.party_share(int(paid.xp), 2)
	check("quest hand-in pays both members shared XP once", int(paid.count) == 1 and hero.character.xp == before_hero + quest_share and cutter.character.xp == before_cutter + quest_share and int(TownState.claim_ready().count) == 0)
	var path := SavePolicy.DEV_PATH.get_base_dir().path_join("road_integration_fixture.json")
	var isolated := SavePolicy.may_modify(path, OS.get_cmdline_user_args()) and path != SavePolicy.PRODUCTION_PATH
	check("road integration disk save is isolated", isolated)
	if not isolated: return # A failed safety assertion must prevent the write itself.
	SavePolicy.ensure_folder(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(TownState.to_dict()))
	file.close()
	TownState.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	check("road XP survives disk reload independently", hero.character.xp == before_hero + quest_share and cutter.character.xp == before_cutter + quest_share)
	var death_xp := [hero.character.xp, cutter.character.xp]
	PartyManager.current().select("hero")
	hero.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": null, "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, hero.global_position)
	await create_timer(0.2).timeout
	check("single death switches to living companion without party defeat", hero.dead and not cutter.dead and PartyManager.current().active_body() == cutter)
	cutter.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": null, "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, cutter.global_position)
	await create_timer(4.0).timeout
	check("party defeat revives both without progression loss", not hero.dead and not cutter.dead and hero.character.xp == death_xp[0] and cutter.character.xp == death_xp[1])
	for body in [hero, cutter]: body.set_physics_process(false)
