extends DevSuite
## Self-test: quests (logic and in the world).

## The quest and event rules (no scene needed): the data hangs together, things turn up by weight and clock, are measured, paid, chained,
## expire, are decided in town, run a world event, and survive saving.
func _test_quest_logic() -> void:
	TownState.persist = false
	TownState.reset()
	Quests.rng.seed = 7
	Quests.clocks_in_tests = true
	Quests.news.clear()
	# The data.
	var defs: Dictionary = TownDb.quests()
	expect("twenty quests and events are defined (the blood moon is removed)", defs.size() == 20)
	var sound: bool = true
	for id in defs:
		var def: QuestDef = defs[id]
		sound = sound and def.title != "" and def.text != "" or def.kind == "world"
		sound = sound and (def.giver == "" or TownDb.npc(def.giver) != null)
		for when in def.links:
			for link in def.links[when]:
				sound = sound and TownDb.quest(String(link["quest"])) != null
		match def.kind:
			"kill_group":
				sound = sound and def.count > 0 and EnemyDb.all().has(def.target)
			"slay_unique":
				sound = sound and def.unique_name != "" and EnemyDb.all().has(def.target)
			"fetch":
				sound = sound and def.item_name != "" and EnemyDb.all().has(def.target) and def.count > 0
			"matter":
				sound = sound and def.choices.size() >= 2
			"world":
				sound = sound and not def.world_mod.is_empty()
	expect("every quest names real people, monsters and links", sound)
	# Eligibility.
	expect("a quest that needs more jobs done does not turn up yet", not Quests.eligible(TownDb.quest("spitter_cull")))
	expect("one that is only ever started by another quest never rolls", not Quests.eligible(TownDb.quest("grey_alpha")))
	expect("but a link may start it", Quests.eligible(TownDb.quest("grey_alpha"), true))
	# Kill a group: progress, ready, hand in, mood, chain.
	TownDb.quest("ghoul_cull").links["complete"][0]["chance"] = 1.0
	var gold: int = TownState.gold
	var hale_mood: float = TownState.happiness("hale")
	var cull: Dictionary = Quests.post("ghoul_cull")
	expect("a posted quest is active with its deadline", cull["state"] == "active" and int(cull["days_left"]) == 5)
	expect("posting it is news", Quests.news.size() == 1 and Quests.news[0].begins_with("New:"))
	Quests.report_kill("zombie")
	expect("the wrong monster does not count", int(cull["progress"]) == 0)
	for i in 7:
		Quests.report_kill("ghoul")
	expect("seven of eight is not enough", cull["state"] == "active" and int(cull["progress"]) == 7)
	Quests.report_kill("ghoul")
	expect("the eighth makes it ready", cull["state"] == "ready" and Quests.ready_for("hale").size() == 1)
	var paid: Dictionary = Quests.claim(int(cull["uid"]))
	expect("handing it in pays gold and lifts the keeper's mood", paid["ok"] and TownState.gold == gold + 70 and TownState.happiness("hale") > hale_mood)
	expect("it is gone from the board and remembered", not Quests.has_live("ghoul_cull") and TownState.quest_history.size() == 1)
	expect("finishing it started the next link (the alpha)", Quests.has_live("grey_alpha"))
	TownDb.quest("ghoul_cull").links["complete"][0]["chance"] = 0.3
	# A named monster.
	var alpha: Dictionary = Quests.find(int(Quests.live()[0]["uid"]))
	expect("it is a named monster to find", Quests.progress_text(alpha).contains("Greywhisker"))
	expect("killing it makes it ready", Quests.report_unique_killed(int(alpha["uid"])) and alpha["state"] == "ready")
	gold = TownState.gold
	Quests.claim(int(alpha["uid"]))
	expect("and pays", TownState.gold == gold + 90)
	# Fetching: the item drops from a kill, is found, and is handed in to Maren.
	var satchel: Dictionary = Quests.post("lost_satchel")
	var dropped: bool = false
	for i in 10:
		var result: Dictionary = Quests.report_kill("zombie")
		dropped = dropped or not (result["drops"] as Array).is_empty()
	expect("the item turns up within ten kills (it is guaranteed by then)", dropped and bool(satchel["data"]["dropped"]))
	expect("a quest item is not dropped twice", (Quests.report_kill("zombie")["drops"] as Array).is_empty())
	Quests.report_fetch_lost(int(satchel["uid"]))
	expect("one left behind can drop again", not bool(satchel["data"]["dropped"]))
	Quests.report_fetch_found(int(satchel["uid"]))
	var potions: int = TownState.potions
	expect("found and handed in to the healer", satchel["state"] == "ready" and Quests.ready_for("maren").size() == 1 and Quests.claim(int(satchel["uid"]))["ok"])
	expect("it pays potions", TownState.potions == potions + 3)
	# Deadlines: a quest nobody did runs out and costs.
	TownState.jobs_done = 1
	var spit: Dictionary = Quests.post("spitter_cull")
	var food: int = TownState.food
	for i in 5:
		Quests.on_day()
	expect("an unfinished quest fails when its days run out", spit["state"] == "failed" and TownState.quest_history[-1]["id"] == "spitter_cull"
		and TownState.quest_history[-1]["state"] == "failed")
	expect("and its failure costs what it said", TownState.food == food - 2)
	expect("a day is counted each time", TownState.day == 6)
	# A matter: choose, pay, results.
	TownState.gold = 100
	TownState.quests = []
	var fever: Dictionary = Quests.post("fever")
	expect("a matter names someone", String(fever["data"]["victim"]) != "" and Quests.text_of(fever).find("{victim}") < 0)
	TownState.gold = 10
	var broke: Dictionary = Quests.resolve_choice(int(fever["uid"]), 0)
	expect("a choice you cannot afford changes nothing", not broke["ok"] and Quests.has_live("fever") and TownState.gold == 10)
	TownState.gold = 100
	var mood_all: float = TownState.happiness("marlow")
	var fixed: Dictionary = Quests.resolve_choice(int(fever["uid"]), 0)
	expect("paying settles it: gold spent, mood up", fixed["ok"] and fixed["success"] and TownState.gold == 75 and TownState.happiness("marlow") > mood_all)
	fever = Quests.post("fever")
	var victim: String = String(fever["data"]["victim"])
	var victim_mood: float = TownState.happiness(victim)
	TownDb.quest("fever").links["fail"][0]["chance"] = 1.0
	var ignored: Dictionary = Quests.resolve_choice(int(fever["uid"]), 2)
	expect("waiting it out fails it and the victim suffers", ignored["ok"] and not ignored["success"] and TownState.happiness(victim) < victim_mood - 10.0)
	expect("and it gets worse", Quests.has_live("spreading_fever"))
	TownDb.quest("fever").links["fail"][0]["chance"] = 0.6
	# A gamble.
	TownState.quests = []
	var thief: Dictionary = Quests.post("light_fingers")
	var suspect: String = String(thief["data"]["suspect"])
	TownDb.quest("light_fingers").choices[1]["chance"] = 0.0
	var suspect_mood: float = TownState.happiness(suspect)
	var wrong: Dictionary = Quests.resolve_choice(int(thief["uid"]), 1)
	expect("accusing the wrong person hurts them", wrong["ok"] and not wrong["success"] and TownState.happiness(suspect) < suspect_mood)
	TownDb.quest("light_fingers").choices[1]["chance"] = 0.5
	# A world event.
	TownState.quests = []
	TownState.world_mods = []
	Quests.post("dangerous_dead")
	expect("a world event changes the road", is_equal_approx(Quests.world_mult("gold_mult"), 1.3) and is_equal_approx(Quests.world_mult("health_mult"), 1.35))
	Quests.on_day()
	Quests.on_day()
	expect("it lasts its days", Quests.world_mult("gold_mult") > 1.0)
	Quests.on_day()
	expect("then it ends", is_equal_approx(Quests.world_mult("gold_mult"), 1.0) and not Quests.has_live("dangerous_dead"))
	# World events are switched off: none is ever rolled, and a save's running ones are dropped on load.
	var rolled_world: bool = false
	for i in 60:
		var rolled: Dictionary = Quests.roll_new("matter")
		if not rolled.is_empty() and Quests.def_of(rolled).kind == "world":
			rolled_world = true
		TownState.quests = []
	expect("no world event turns up by itself while they are switched off", not rolled_world)
	TownState.quests = []
	TownState.world_mods = []
	Quests.post("dangerous_dead")
	TownState.world_mods.append({"id": "altar", "monster": 7, "days_left": 2})
	TownState.from_dict(TownState.migrate(JSON.parse_string(JSON.stringify(TownState.to_dict()))))
	expect("a loaded save drops the running world event but keeps a monster's plot effect", is_equal_approx(Quests.world_mult("gold_mult"), 1.0)
		and not Quests.has_live("dangerous_dead") and TownState.world_mods.size() == 1)
	TownState.quests = []
	TownState.world_mods = []
	# Timers: something turns up by itself.
	TownState.quests = []
	TownState.jobs_done = 3
	TownState.quest_clock = {"quest": 1.0, "matter": 1.0}
	var posted: Array[Dictionary] = Quests.tick(2.0)
	expect("when the clocks run out something turns up (a quest and a matter)", posted.size() == 2)
	var none: Array[Dictionary] = Quests.tick(0.5)
	expect("and the clocks start again", none.is_empty() and float(TownState.quest_clock["quest"]) > 100.0)
	for i in 6:
		TownState.quest_clock["quest"] = 0.0
		Quests.tick(0.1)
	expect("only so many quests wait at once", Quests.posted_count() <= Quests.MAX_POSTED)
	# Saving.
	var live_before: int = Quests.live().size()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	var uid_before: int = TownState.quest_uid
	TownState.reset()
	TownState.from_dict(saved)
	expect("live quests, the day and the counter survive saving", Quests.live().size() == live_before and TownState.quest_uid == uid_before
		and TownState.day >= 6 and typeof(TownState.quests[0]["uid"]) == TYPE_INT)
	TownState.reset()
	Quests.news.clear()
	Quests.clocks_in_tests = false

## Quests out in the world: a named monster is put on the road and killing it is measured, a kill counts toward a group, a quest item
## drops and is picked up, the giver gets a coin over their head and takes the hand-in, matters are decided in the giver's panel, and a
## world event pays more.
func _test_quest_world() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.gold = 0
	Quests.news.clear()
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
	var hero: Player = town.player
	var crypt: CryptRoad = town.crypt
	# A named monster.
	var bounty: Dictionary = Quests.post("brute_bounty")
	town.populate_quests()
	var named: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("quest_uid") and int(node.get_meta("quest_uid")) == int(bounty["uid"]):
			named = node
	expect("a quest for a named monster puts it on the road", named != null and named.display_name == "Gorran Hollow-Eye" and bool(bounty["data"]["spawned"]))
	if named != null:
		var def: EnemyDef = EnemyDb.get_def("brute")
		var gate_distance: float = 174.0 - (named.global_position.z - crypt.arena.origin_offset.z)
		expect("it is tougher than its kind and where the quest says (%.0f m from the gate)" % gate_distance, named.max_health >= MonsterScaling.life(1, def.tier, def.role) * 3.0
			and gate_distance >= 95.0 and gate_distance <= 225.0)
		var loot_before: int = get_tree().get_nodes_in_group("loot").size()
		named.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": hero, "skill_id": "x", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, hero.global_position)
		await get_tree().create_timer(0.8).timeout
		expect("killing it finishes the quest", bounty["state"] == "ready")
		expect("it leaves a good item", get_tree().get_nodes_in_group("loot").size() > loot_before)
		var hale: TownNpc = town.npcs["hale"]
		expect("Hale has a coin over his head for it", hale.has_reward_marker())
		TownState.gold = 0
		town.panel.open_npc("hale")
		await get_tree().process_frame
		var hand_in: Button = _find_button(town.panel, "Hand in")
		expect("his panel offers to take it", hand_in != null)
		if hand_in != null:
			hand_in.pressed.emit()
		await get_tree().process_frame
		expect("handing it in pays 120 gold and the coin goes", TownState.gold == 120 and not Quests.has_live("brute_bounty"))
		town.panel.close()
	# A group.
	TownState.quests = []
	TownDb.quest("ghoul_cull").count = 2
	var cull: Dictionary = Quests.post("ghoul_cull")
	for i in 2:
		var ghoul: Enemy = town.director.spawn_enemy(crypt.at(0, 140 + i), "ghoul", 1.0)
		ghoul.aggro_range = 0.0
		ghoul.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": hero, "skill_id": "x", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, hero.global_position)
		await get_tree().create_timer(0.5).timeout
	TownDb.quest("ghoul_cull").count = 8
	expect("two ghouls killed in the world count toward the quest", cull["state"] == "ready")
	TownState.quests = []
	# A quest item drops from a kill and is picked up.
	TownDb.quest("lost_satchel").count = 1
	var satchel: Dictionary = Quests.post("lost_satchel")
	var zombie: Enemy = town.director.spawn_enemy(crypt.at(0, 142), "zombie", 1.0)
	zombie.aggro_range = 0.0
	zombie.receive({"outcome": Combat.Outcome.HIT, "damage": 99999.0, "source": hero, "skill_id": "x", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, hero.global_position)
	await get_tree().create_timer(0.6).timeout
	TownDb.quest("lost_satchel").count = 10
	var pickups: Array = get_tree().get_nodes_in_group("quest_pickups")
	expect("the satchel drops where the zombie fell", pickups.size() == 1 and bool(satchel["data"]["dropped"]))
	if pickups.size() == 1:
		hero.global_position = (pickups[0] as QuestPickup).global_position + Vector3(0.5, 0, 0)
		hero.reset_physics_interpolation()
		await get_tree().create_timer(0.4).timeout
		expect("walking over it finds it, and the quest is ready for Maren", satchel["state"] == "ready" and (town.npcs["maren"] as TownNpc).has_reward_marker())
		expect("it is gone from the ground", get_tree().get_nodes_in_group("quest_pickups").is_empty())
	TownState.quests = []
	# A matter, decided in the giver's panel.
	TownState.gold = 100
	var fever: Dictionary = Quests.post("fever")
	town._refresh_reward_marker()
	var maren: TownNpc = town.npcs["maren"]
	expect("a matter puts a coin over its giver", maren.has_reward_marker())
	town.panel.open_npc("maren")
	await get_tree().process_frame
	var poultice: Button = _find_button(town.panel, "Pay Maren")
	expect("her panel lists what you can do about it", poultice != null and not poultice.disabled)
	if poultice != null:
		poultice.pressed.emit()
	await get_tree().process_frame
	expect("choosing one settles it", TownState.gold == 75 and not Quests.has_live("fever"))
	town.panel.close()
	# A world event pays more.
	TownState.quests = []
	TownState.world_mods = []
	Quests.post("dangerous_dead")
	expect("under a world event with a gold bonus the gold a drop holds grows (%d for 10)" % town.director.gold_for_drop(10), town.director.gold_for_drop(10) == 13)
	TownState.world_mods = []
	expect("with no world event it is not", town.director.gold_for_drop(10) == 10)
	Quests.post("dangerous_dead")
	# The HUD tracks what is running.
	await get_tree().process_frame
	expect("the tracker lists the world event", town.hud.side_lines.size() >= 1)
	town.queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	for node in get_tree().get_nodes_in_group("quest_pickups"):
		node.queue_free()
	TownState.reset()
	Quests.news.clear()
