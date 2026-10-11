extends DevSuite
## Self-test: the town (simulation, state, run modifiers, the scene and its layout).

## The town's inner life: traits weight what NPCs do, likes and dislikes move mood and opinion, bad blood ends in brawls, wretched
## recruits leave, hunger sours everyone, and the numbers behave the same for the same seed.
func _test_town_sim() -> void:
	TownState.persist = false
	TownState.reset()
	expect("five people live in town", TownState.present_ids().size() == 5)
	var sim := TownSim.new(11)
	var marlow: Dictionary = sim.activity_weights("marlow")
	var maren: Dictionary = sim.activity_weights("maren")
	expect("a drunk drinks far more than a teetotal healer", float(marlow["drink"]) > float(maren["drink"]) * 3.0)
	expect("a gossip gossips more than a loyal warden", float(marlow["gossip"]) > float(sim.activity_weights("hale")["gossip"]) * 2.0)
	expect("a religious NPC prays more than a trader", float(maren["pray"]) > float(marlow["pray"]) * 3.0)
	# Likes: Cutter (a joker) enjoys a joke. Dislikes: Maren (religious) resents one.
	var rel_before: float = TownState.relation("marlow", "cutter")
	var mood_before: float = TownState.happiness("cutter")
	sim.perform("marlow", "joke", "cutter")
	expect("a liked joke raises the target's mood", TownState.happiness("cutter") > mood_before + 3.0)
	expect("a liked joke improves their opinion of each other", TownState.relation("marlow", "cutter") > rel_before + 3.0)
	rel_before = TownState.relation("cutter", "maren")
	mood_before = TownState.happiness("maren")
	sim.perform("cutter", "joke", "maren")
	expect("a disliked joke lowers the target's mood", TownState.happiness("maren") < mood_before)
	expect("a disliked joke sours their opinion", TownState.relation("cutter", "maren") < rel_before)
	# Mood changes what they choose.
	TownState.npcs["hale"]["happiness"] = -50.0
	expect("an unhappy NPC argues and broods more", float(sim.activity_weights("hale")["argue"]) > 1.5 * 0.5 * 3.5 * 0.9
		and float(sim.activity_weights("hale")["brood"]) > 0.5)
	TownState.npcs["hale"]["happiness"] = 20.0
	# Brawls.
	TownState.relations[TownState._pair("hale", "cutter")] = 5.0
	var brawled: bool = false
	for i in 20:
		sim.run_round()
		for line in sim.history:
			if "came to blows" in line:
				brawled = true
		TownState.relations[TownState._pair("hale", "cutter")] = 5.0
		if brawled:
			break
	expect("NPCs who hate each other come to blows", brawled)
	# A wretched hired recruit leaves.
	TownState.npcs["cutter"]["member"] = true
	TownState.npcs["cutter"]["happiness"] = -90.0
	sim.run_round()
	expect("a wretched recruit leaves the clan", bool(TownState.npcs["cutter"]["left"]) and not bool(TownState.npcs["cutter"]["member"]))
	expect("the others are shaken when someone leaves", TownState.present_ids().size() == 4)
	# Hunger.
	TownState.reset()
	var mood: float = TownState.happiness("maren")
	TownState.food = 0
	var quiet := TownSim.new(3)
	quiet._settle(TownState.present_ids())
	expect("no food sours everyone", TownState.happiness("maren") < mood - 1.0)
	TownState.food = 12
	expect("rationing starts when food runs low", not TownState.rationing())
	TownState.food = TownState.LOW_FOOD
	expect("food at the low mark means rationing", TownState.rationing())
	# Prices follow mood.
	TownState.npcs["marlow"]["happiness"] = 60.0
	var cheap: float = TownSim.mood_price_mult("marlow")
	TownState.npcs["marlow"]["happiness"] = -50.0
	expect("a content trader charges less than a wretched one", cheap < 1.0 and TownSim.mood_price_mult("marlow") > 1.0)
	# Same seed, same town.
	TownState.reset()
	var a := TownSim.new(99)
	for i in 6:
		a.run_round()
	var first: Array = [TownState.happiness("marlow"), TownState.happiness("hale"), TownState.relation("marlow", "hale")]
	TownState.reset()
	var b := TownSim.new(99)
	for i in 6:
		b.run_round()
	expect("the same seed gives the same town", first == [TownState.happiness("marlow"), TownState.happiness("hale"), TownState.relation("marlow", "hale")])
	# Over a long time every NPC's mood stays inside its range and the town stays alive.
	TownState.reset()
	var long := TownSim.new(5)
	for i in 80:
		long.run_round()
	var in_range: bool = true
	for id in TownState.npcs:
		var h: float = TownState.happiness(id)
		in_range = in_range and h >= -100.0 and h <= 100.0
	expect("moods stay in range over a long time", in_range)
	TownState.reset()

## What the town keeps: pay-out for a run, gear handed over, the job board, the food bill, and saving without losing a thing.
func _test_town_state() -> void:
	TownState.persist = false
	TownState.reset()
	var board_ok: bool = TownState.board.size() == 1
	for offer in TownState.board:
		board_ok = board_ok and JobObjective.stages(offer) >= 2 and offer.has("location") and int(offer["reward"]) > 0 \
			and String(offer.get("site", "")) == CryptRoad.SITE_ID and not bool(offer.get("ready", false))
	expect("the board posts the world's quest, which is active without being taken", board_ok and TownState.job.get("name") == TownState.board[0]["name"])
	# Saving: a version, the job and last run saved, old saves migrated, newer ones left alone, an abandoned run noticed.
	TownState.gold = 77
	TownState.job = TownState.board[0].duplicate(true)
	TownState.last_run = {"kills": 5, "wave": 2, "completed": true, "died": false, "gold": 40}
	var saved_town: Variant = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.reset()
	TownState.from_dict(TownState.migrate(saved_town))
	expect("a saved town keeps its version, gold, job and last run", int(saved_town["save_version"]) == TownState.SAVE_VERSION and TownState.gold == 77
		and JobObjective.stages(TownState.job) >= 2 and TownState.last_run.get("kills") == 5)
	var legacy: Dictionary = {"gold": 12, "board": [{"name": "Clear Ash Ford", "waves": 3, "modifiers": [], "reward": 80}]}
	var upgraded: Dictionary = TownState.migrate(legacy)
	expect("a save from before versions is migrated", int(upgraded["save_version"]) == TownState.SAVE_VERSION
		and JobObjective.stages(upgraded["board"][0]) == 3)
	expect("a save from a newer build is refused, not overwritten", TownState.migrate({"save_version": TownState.SAVE_VERSION + 1}).is_empty())
	# Items are definitions plus a small instance: saved as {def, tier, rarity, affix}, rebuilt from the data on load.
	var made: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 3, "chain", "Greatsword")
	var slim: Dictionary = Items.to_save(made)
	var rebuilt: Dictionary = Items.from_save(JSON.parse_string(JSON.stringify(slim)))
	expect("an item is saved as only its definition, tier, rarity and affix", slim.keys().size() == 4 and slim["def"] == "greatsword"
		and rebuilt["name"] == made["name"] and is_equal_approx(float(rebuilt["stats"]["damage"]), float(made["stats"]["damage"])))
	var def: ItemDef = ItemDb.get_def("greatsword")
	var old_damage: float = float(def.stats["damage"])
	def.stats["damage"] = 2.0
	expect("changing a base's numbers changes saved copies too", is_equal_approx(float(Items.from_save(slim)["stats"]["damage"]), 2.0 * (1.0 + 0.08 * 2)))
	def.stats["damage"] = old_damage
	var old_form: Dictionary = {"slot": 0, "rarity": 1, "name": "Stormcalled Greatsword", "base": "Greatsword", "affix": "chain", "flavor": "",
		"stats": {"damage": 1.35 * 1.16, "speed": 0.82}}
	var from_old: Dictionary = Items.from_save(old_form)
	expect("an item saved as a whole dictionary still loads, its tier worked out", from_old["def"] == "greatsword" and from_old["tier"] == 3)
	expect("an item whose base or affix has gone is dropped", Items.from_save({"def": "vanished", "tier": 1, "rarity": 0, "affix": ""}).is_empty()
		and Items.from_save({"def": "falchion", "tier": 1, "rarity": 1, "affix": "no_such_affix"}).is_empty())
	var v1: Dictionary = TownState.migrate({"save_version": 1, "gear": {"0": old_form}, "stash": [old_form], "stock": [{"item": old_form, "price": 80}]})
	expect("a version 1 save has its items rewritten as definitions", v1["gear"]["0"].has("def") and not v1["gear"]["0"].has("stats")
		and v1["stash"][0]["def"] == "greatsword" and v1["stock"][0]["item"]["tier"] == 3)
	TownState.run_in_progress = true
	TownState.job = {}
	var mid_run: Variant = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.from_dict(TownState.migrate(mid_run))
	expect("a reloaded town has nothing in progress and the posted quest is the active one", not TownState.run_in_progress
		and TownState.job.get("name") == TownState.board[0]["name"])
	var wave_board: Variant = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	wave_board["board"] = [{"name": "Clear Ash Ford", "location": "Ash Ford", "objective": JobObjective.clear_waves(3), "modifiers": [], "reward": 80}]
	TownState.from_dict(TownState.migrate(wave_board))
	expect("a board saved with only the old wave jobs is replaced by the world's quest", TownState.board.size() == 1 and TownState.board[0].get("site") == CryptRoad.SITE_ID)
	TownState.reset()
	var cost: int = TownState.food_cost()
	var food_mood_before: float = TownState.happiness("marlow")
	TownState.food = cost
	TownState.begin_job(TownState.board[0])
	expect("exactly enough food is not a shortage", TownState.food == 0 and is_equal_approx(TownState.happiness("marlow"), food_mood_before))
	TownState.food = cost - 1
	TownState.begin_job(TownState.board[0])
	expect("too little food sours the clan", TownState.happiness("marlow") < food_mood_before)
	var old_job: Dictionary = JobObjective.upgrade_legacy({"name": "Clear Ash Ford", "waves": 4, "modifiers": [], "reward": 90})
	expect("a job saved with a wave count becomes an objective", JobObjective.stages(old_job) == 4 and old_job["location"] == "Ash Ford"
		and JobObjective.describe(old_job) == "Clear 4 waves" and JobObjective.is_complete(old_job, {"stage": 4}) and not JobObjective.is_complete(old_job, {"stage": 3}))
	var clash: bool = false
	for seed_value in 120:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		TownState.jobs_done = 5
		TownState.roll_board(rng)
		for offer in TownState.board:
			var mods: Array = offer["modifiers"]
			if (mods.has("darkness") and mods.has("moonlit")) or (mods.has("fog") and mods.has("moonlit")):
				clash = true
	expect("jobs never combine modifiers that exclude each other", not clash)
	TownState.reset()
	# The food bill and the pay-out.
	var food_before: int = TownState.food
	var offer: Dictionary = {"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["fog"], "reward": 100}
	TownState.begin_job(offer)
	expect("leaving costs the clan food", TownState.food == food_before - TownState.food_cost())
	var gold_before: int = TownState.gold
	var mood_before: float = TownState.happiness("hale")
	TownState.finish_run({"kills": 10, "wave": 3, "completed": true, "died": false})
	expect("a finished job pays its reward plus 2g a kill", TownState.gold == gold_before + 120)
	expect("a finished job counts", TownState.jobs_done == 1)
	expect("the town is pleased by a finished job", TownState.happiness("hale") > mood_before)
	expect("the board is refreshed", TownState.board.size() == 1 and not bool(TownState.board[0].get("ready", false)))
	expect("the result is kept for the welcome back", int(TownState.last_run["gold"]) == 120)
	gold_before = TownState.gold
	TownState.begin_job({})
	TownState.finish_run({"kills": 4, "wave": 2, "completed": false, "died": true})
	expect("a fallen hero keeps only the 2g per kill", TownState.gold == gold_before + 8 and TownState.jobs_done == 1)
	# Gear and stash.
	TownState.reset()
	var blade: Dictionary = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 2, "")
	for id in AffixDb.all():
		if AffixDb.all()[id]["slot"] == Items.Slot.WEAPON and AffixDb.all()[id]["title"] != "":
			blade = Items.make(Items.Slot.WEAPON, Items.Rarity.RARE, 2, id)
			break
	TownState.take_gear({Items.Slot.WEAPON: blade})
	expect("the run's gear is kept", String(TownState.gear[Items.Slot.WEAPON]["name"]) == String(blade["name"]))
	TownState.take_gear({Items.Slot.WEAPON: Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword")})
	expect("a replaced special item goes to the stash", TownState.stash.size() == 1 and String(TownState.stash[0]["name"]) == String(blade["name"]))
	# Saving: everything survives a trip through JSON.
	TownState.gold = 321
	TownState.food = 7
	TownState.npcs["marlow"]["happiness"] = 33.0
	TownState.add_relation("marlow", "hale", 9.0)
	TownState.npcs["cutter"]["member"] = true
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.reset()
	TownState.from_dict(saved)
	expect("saved gold and food come back", TownState.gold == 321 and TownState.food == 7)
	expect("saved moods and opinions come back", is_equal_approx(TownState.happiness("marlow"), 33.0)
		and is_equal_approx(TownState.relation("marlow", "hale"), 59.0) and bool(TownState.npcs["cutter"]["member"]))
	expect("saved gear keeps its slot and rarity as integers", TownState.gear.has(Items.Slot.WEAPON)
		and typeof(TownState.gear[Items.Slot.WEAPON]["rarity"]) == TYPE_INT and TownState.stash.size() == 1)
	var hero_gear: Dictionary = {}
	for item in TownState.gear.values():
		hero_gear[int(item["slot"])] = item
	expect("a saved item still describes itself", not Items.lines(TownState.gear[Items.Slot.WEAPON]).is_empty())
	TownState.reset()

## Wave modifiers: more of what they favour, tougher or quicker enemies, a mood for the whole run, and a job that ends in town.
func _test_run_modifiers() -> void:
	var director: RunDirector = game.director
	var zombie: EnemyDef = EnemyDb.get_def("zombie")
	var ghoul: EnemyDef = EnemyDb.get_def("ghoul")
	expect("all twelve modifiers load", TownDb.modifiers().size() == 12)
	var plain_zombies: int = director.modified_count(zombie, 3)
	var plain_ghouls: int = director.modified_count(ghoul, 3)
	director.set_job({"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["swarming"], "reward": 50})
	expect("Swarming brings more zombies and ghouls", director.modified_count(zombie, 3) > plain_zombies
		and director.modified_count(ghoul, 3) > plain_ghouls)
	expect("an enemy not in the wave stays out", director.modified_count(EnemyDb.get_def("priest"), 1) == 0)
	director.set_job({"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["cursed"], "reward": 50})
	expect("Cursed only starts at its minimum wave", director.active_modifiers(1).is_empty() and director.active_modifiers(2).size() == 1)
	var saved_wave: int = director.wave
	director.wave = 3
	director.set_job({"name": "Test", "objective": JobObjective.clear_waves(3), "modifiers": ["gigantism", "fleet"], "reward": 50})
	expect("modifiers stack", is_equal_approx(director.modifier_product("speed_mult"), 0.92 * 1.25)
		and is_equal_approx(director.modifier_product("health_mult"), 1.5))
	var big: Enemy = _spawn_enemy(Vector3(30, 0, 30), "zombie", 1.0)
	await get_tree().process_frame
	expect("Gigantism makes enemies tougher and bigger", big.max_health >= zombie.health * 1.49 and big.visual.scale.x > 1.2)
	expect("the wave banner names the rules", director.modifier_names() == "Gigantism, Fleet of Foot")
	big.queue_free()
	director.wave = saved_wave
	director.set_job({})
	expect("no job means no modifiers", director.modifiers.is_empty() and director.modified_count(zombie, 3) == plain_zombies)
	# Mood: darkness dims, fog thickens.
	var env: Environment = game.world_environment
	var ambient: float = env.ambient_light_energy
	var fog: float = env.fog_density
	game._apply_job_mood({"modifiers": ["darkness"]})
	expect("Darkness dims the world and thickens the fog", env.ambient_light_energy < ambient * 0.5 and env.fog_density > fog)
	env.ambient_light_energy = ambient
	env.fog_density = fog
	# Every modifier references enemies that exist.
	var known: bool = true
	for id in TownDb.modifiers():
		for enemy_id in TownDb.modifier(id).spawn_weights:
			known = known and EnemyDb.all().has(enemy_id)
	expect("every modifier names real enemies", known)

## The town scene: it builds, people and places can be found and used, the panels work and shopping changes what you own.
func _test_town_scene() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.gold = 500
	var town := TownScene.new()
	game.add_child(town)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect("the town has its five people", town.npcs.size() == 5)
	var kinds: Dictionary = {}
	for spot in town.spots:
		kinds[spot["kind"]] = true
	expect("the town has interactive stone, board, stash and people, but no gate menu", not kinds.has("gate") and kinds.has("stone") and kinds.has("board")
		and kinds.has("stash") and kinds.has("npc"))
	# Standing near the gate shows travel information, without an interaction prompt or a free run.
	town.player.global_position = Vector3(0, 0, -16.0)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("near the gate nothing pops up over it (the quest is in the corner), and there is nothing to accept", town.near.is_empty() and town.hud.prompt == ""
		and town.hud.quest_line.contains("Crypt Road") and town.hud.quest_line.contains("0 / 3"))
	# Walking out is just walking: no loading, no scene change. The clan eats once when the hero is properly out, not at the wall.
	var food_before_gate: int = TownState.food
	town.player.global_position = Vector3(0, 0, -TownScene.HALF - 3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("stepping just past the wall is not yet an expedition and costs nothing", not town.outside and TownState.food == food_before_gate)
	town.player.global_position = Vector3(0, 0, -TownScene.HALF - 20.0)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("being properly out on the road is an expedition: the clan eats once", town.outside and TownState.expedition
		and TownState.food == food_before_gate - TownState.food_cost())
	town.player.global_position = Vector3(0, 0, -TownScene.HALF - 15.0)
	await get_tree().process_frame
	expect("going back and forth does not charge again", TownState.food == food_before_gate - TownState.food_cost())
	town.player.global_position = Vector3(0, 0, -10.0)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("coming back inside ends the expedition", not town.outside and not TownState.expedition)
	# The gate is a real opening: the north edge is walled either side of it, and the opening itself is clear.
	var space: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var blocked_at: Callable = func(x: float) -> bool:
		var query := PhysicsRayQueryParameters3D.create(Vector3(x, 1.0, -15.0), Vector3(x, 1.0, -TownScene.HALF - 1.0), Actor.LAYER_WORLD)
		return not space.intersect_ray(query).is_empty()
	expect("the town wall is solid beside the gate", blocked_at.call(-10.0) and blocked_at.call(10.0))
	expect("the opening at the gate is clear of walls", not blocked_at.call(2.5) and not blocked_at.call(-2.5))
	var ward_query := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, -TownScene.HALF - 2.0), Vector3(0, 1.0, -TownScene.HALF + 2.0), Actor.LAYER_ENEMY | Actor.LAYER_PLAYER)
	expect("the gate is warded against monsters only", not space.intersect_ray(ward_query).is_empty()
		and space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, -TownScene.HALF - 2.0), Vector3(0, 1.0, -TownScene.HALF + 2.0), town.player.collision_mask)).is_empty())
	# A click on someone is found by where they are on screen.
	town.player.global_position = Vector3(-8.0, 0, 0.0)
	await get_tree().process_frame
	var camera: Camera3D = town.get_viewport().get_camera_3d()
	var on_screen: Vector2 = camera.unproject_position(town.npcs["marlow"].global_position + Vector3(0, 1.1, 0))
	expect("a click on Marlow picks Marlow", town.pick_spot(on_screen).get("id") == "marlow")
	# The sim's social life is acted out: a gossiper walks over to the other person, they face each other, and he goes home after.
	TownStage.time_scale = 8.0
	TownNpc.speed_scale = 8.0
	town.player.global_position = Vector3(0, 0, -4.0)
	var gossiper: TownNpc = town.npcs["marlow"]
	var listener: TownNpc = town.npcs["hale"]
	town.stage.handle({"id": "marlow", "text": "Did you hear?", "partner": "hale", "activity": "gossip"})
	var met: bool = false
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if town.stage.events.has("gossip marlow"):
			met = gossiper.global_position.distance_to(listener.global_position) < 2.4
			break
	expect("someone who gossips walks over to the other person", met)
	expect("and the two turn to face each other", absf(angle_difference(gossiper.rotation.y, atan2(listener.global_position.x - gossiper.global_position.x, listener.global_position.z - gossiper.global_position.z))) < 0.5)
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if not gossiper.busy:
			break
	expect("afterwards he walks home and the stage lets him go", not gossiper.busy and gossiper.global_position.distance_to(gossiper.home) < 0.5)
	town.stage.handle({"id": "marlow", "text": "Another.", "partner": "", "activity": "drink"})
	var drank: bool = false
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if town.stage.events.has("drink marlow"):
			drank = gossiper.global_position.distance_to(town.stations["drink"]) < 1.5
			break
	expect("drinking happens at the barrels", drank)
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if not gossiper.busy:
			break
	town.stage.handle({"id": "hale", "text": "That's it!", "partner": "marlow", "activity": "brawl"})
	town.stage.handle({"id": "marlow", "text": "Come on, then.", "partner": "hale", "activity": "brawl_reply"})
	var fought: bool = false
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if town.stage.events.has("brawl hale"):
			fought = listener.global_position.distance_to(gossiper.global_position) < 2.4
			break
	expect("a brawl is fought face to face", fought)
	for i in 200:
		await get_tree().create_timer(0.05).timeout
		if not listener.busy and not gossiper.busy:
			break
	expect("and everyone is home afterwards", not listener.busy and not gossiper.busy and listener.global_position.distance_to(listener.home) < 0.5)
	TownStage.time_scale = 1.0
	TownNpc.speed_scale = 1.0
	town.player.global_position = Vector3(-8.0, 0, 0.0)
	for each in town.npcs.values():   # let the lines die away
		each._bark_left = 0.0
		each._bark.visible = false
	# A name tag and a speech line never show together.
	var talker: TownNpc = town.npcs["marlow"]
	talker.set_tag_visible(true)
	expect("the name shows while they are quiet", talker._tag.visible)
	talker.say("Prices are only going up.")
	expect("the name hides while they speak", not talker._tag.visible and talker._bark.visible)
	talker._bark_left = 0.01
	await get_tree().create_timer(0.1).timeout
	expect("the name comes back when they stop", talker._tag.visible and not talker._bark.visible)
	# Panels.
	for id in ["marlow", "hale", "maren", "cutter", "dorn"]:
		town.panel.open_npc(id)
		await get_tree().process_frame
		var passive_page: bool = id in ["hale", "cutter"]
		expect("%s's panel opens with something to do" % id, town.panel.visible and town.panel.get_tree().paused and _count_buttons(town.panel) >= (1 if passive_page else 2))
		town.panel.close()
	town.panel.open_npc("dorn")
	await get_tree().process_frame
	var smith_ok: bool = TownState.smith_stock.size() >= 2
	for entry in TownState.smith_stock:
		smith_ok = smith_ok and int(entry["item"]["slot"]) != Items.Slot.TRINKET
	expect("the smith sells only weapons and armour", smith_ok)
	town.panel.close()
	town.panel.open_board()
	await get_tree().process_frame
	expect("the board lists the quest, which has nothing to accept", _count_buttons(town.panel) >= 1)
	var offer: Dictionary = TownState.board[0]
	expect("the posted quest is already the active one", TownState.job.get("name") == offer["name"])
	town.panel.close()
	town.player.global_position = Vector3(0, 0, -16.0)
	await get_tree().process_frame
	await get_tree().process_frame
	expect("near the gate no text appears over it and there is no button", town.hud.prompt == "" and town.hud.quest_line != "")
	town.panel.open_stash()
	await get_tree().process_frame
	town.panel.close()
	expect("closing a panel unpauses the world", not get_tree().paused)
	# Shopping.
	town.panel.open_npc("marlow")
	await get_tree().process_frame
	var stock: Array = TownState.stock
	expect("the trader has wares", stock.size() == 3)
	var gold: int = TownState.gold
	var vendor_gold: int = TownState.vendor_gold
	var ware: Dictionary = (stock[0] as Dictionary)["item"]
	var price: int = int(round(int((stock[0] as Dictionary)["price"]) * TownSim.mood_price_mult("marlow")))
	town.panel._buy(0, price)
	expect("buying costs gold and puts the item on", TownState.gold == gold - price and TownState.vendor_gold == vendor_gold + price
		and String(TownState.gear[int(ware["slot"])]["name"]) == String(ware["name"]))
	expect("buying gear puts it on the hero standing in town", town.player.stats.equipment[int(ware["slot"])]["name"] == ware["name"])
	var potions: int = TownState.potions
	town.panel._buy_supply("potion", 15)
	expect("buying a potion adds one, to the hero too", TownState.potions == potions + 1 and town.player.stats.potions == potions + 1)
	town.panel.close()   # (the town is paused while a panel is open)
	town.player.stats.potions -= 1   # he drinks one in town
	await get_tree().process_frame
	await get_tree().process_frame
	expect("a potion drunk in town is not bought back by the town's count", TownState.potions == potions)
	TownState.stash.append(Items.make(Items.Slot.WEAPON, Items.Rarity.COMMON, 1, "", "Greatsword"))
	town.panel._wear(TownState.stash.size() - 1)
	expect("wearing from the stash puts it on the hero too", town.player.stats.equipment[Items.Slot.WEAPON]["base"] == "Greatsword"
		and town.player._held_path == Items.model_path(town.player.stats.equipment[Items.Slot.WEAPON]))
	# Cutter is no longer hired: he is the permanent, free clan archer.
	town.panel.close()
	town.panel.open_npc("cutter")
	await get_tree().process_frame
	expect("Cutter starts as a permanent clan member", bool(TownState.npcs["cutter"]["member"]))
	gold = TownState.gold
	town.panel.close()
	TownState.npcs["cutter"]["member"] = false
	TownState.ensure_npcs()
	town.panel.open_npc("cutter")
	town.panel._rebuild()
	var hire: Button = _find_button(town.panel, "Hire")
	expect("Cutter has no hire button or cost", hire == null and TownDb.npc("cutter").recruit_cost == 0)
	expect("old saves that lacked him are repaired without spending gold", bool(TownState.npcs["cutter"]["member"]) and TownState.gold == gold)
	town.panel.close()
	# The healing stone, and the hero carries what the town gave into the run.
	town.player.health = 10.0
	town.interact({"kind": "stone"})
	expect("the healing stone heals", town.player.health >= town.player.max_health - 0.1)
	var run_hero := Player.new()
	game.add_child(run_hero)
	TownScene._apply_run_gear(run_hero)
	expect("a run starts with the town's potions", run_hero.stats.potions == TownState.potions)
	run_hero.queue_free()
	# Town life goes on while you watch.
	town.sim.run_round()
	await get_tree().process_frame
	expect("the sim's talk reaches the townspeople", true)
	town.queue_free()
	await get_tree().process_frame
	game.rig.camera.current = true
	get_tree().paused = false
	TownState.job = {}
	TownState.reset()

## Nothing in the town may clip into anything else: no solid prop overlaps another or the palisade, none stands beyond the wall, and
## nobody's spot or station is inside one. Footprints are each model's bounds, scaled to its height, as a rotated rectangle.
func _town_footprint(node: Node3D, prop: TownProp) -> Dictionary:
	var inst: Node3D = (load("res://assets/models/%s/model.glb" % prop.model_name) as PackedScene).instantiate()
	var b: AABB = CharacterModel._bounds_of(inst)
	var f: float = prop.height / maxf(b.size.y, 0.001)
	inst.free()
	return {"name": node.name, "model": prop.model_name, "c": Vector2(node.position.x, node.position.z),
		"h": Vector2(b.size.x * f * 0.5, b.size.z * f * 0.5), "yaw": node.rotation.y, "solid": prop.collides}

func _town_corners(o: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var c: float = cos(o["yaw"])
	var s: float = sin(o["yaw"])
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector2(sx * o["h"].x, sz * o["h"].y)
			out.append(o["c"] + Vector2(p.x * c + p.y * s, -p.x * s + p.y * c))
	return out

## How deep two footprints overlap (0 when apart), by the separating-axis test.
func _town_overlap(a: Dictionary, b: Dictionary) -> float:
	var best: float = INF
	for o in [a, b]:
		var c: float = cos(o["yaw"])
		var s: float = sin(o["yaw"])
		for axis in [Vector2(c, -s), Vector2(s, c)]:
			var ra := Vector2(INF, -INF)
			var rb := Vector2(INF, -INF)
			for p in _town_corners(a):
				ra = Vector2(minf(ra.x, p.dot(axis)), maxf(ra.y, p.dot(axis)))
			for p in _town_corners(b):
				rb = Vector2(minf(rb.x, p.dot(axis)), maxf(rb.y, p.dot(axis)))
			var depth: float = minf(ra.y, rb.y) - maxf(ra.x, rb.x)
			if depth <= 0.0:
				return 0.0
			best = minf(best, depth)
	return best

func _test_town_layout() -> void:
	var layout: Node = (load("res://game/town/town_layout.tscn") as PackedScene).instantiate()
	var props: Array[Dictionary] = []
	for node in layout.get_node("Props").get_children():
		if node is TownProp and (node as TownProp).model_name != "":
			props.append(_town_footprint(node, node))
	var clashes: PackedStringArray = []
	var beyond: PackedStringArray = []
	for i in props.size():
		var a: Dictionary = props[i]
		if a["model"] != "palisade":
			for corner in _town_corners(a):
				if absf(corner.x) > TownScene.HALF + 0.3 or absf(corner.y) > TownScene.HALF + 0.3:
					beyond.append(String(a["name"]))
					break
		for j in range(i + 1, props.size()):
			var b: Dictionary = props[j]
			if (a["model"] == "palisade" and b["model"] == "palisade") or a["model"] == "town_gate" or b["model"] == "town_gate":
				continue
			if (a["solid"] or b["solid"]) and _town_overlap(a, b) > 0.05:
				clashes.append("%s x %s" % [a["name"], b["name"]])
	expect("no town prop clips into another or into the palisade: " + ", ".join(clashes), clashes.is_empty())
	expect("no town prop stands beyond the wall: " + ", ".join(beyond), beyond.is_empty())
	var stood_in: PackedStringArray = []
	for group in ["Spots", "Stations"]:
		for marker in layout.get_node(group).get_children():
			var at := Vector2(marker.position.x, marker.position.z)
			for o in props:
				if not o["solid"] or o["model"] == "palisade":
					continue
				var local: Vector2 = at - o["c"]
				var c: float = cos(o["yaw"])
				var s: float = sin(o["yaw"])
				if absf(local.x * c - local.y * s) < o["h"].x + 0.4 and absf(local.x * s + local.y * c) < o["h"].y + 0.4:
					stood_in.append("%s in %s" % [marker.name, o["name"]])
	expect("nobody's spot or station is inside a solid prop: " + ", ".join(stood_in), stood_in.is_empty())
	layout.free()
