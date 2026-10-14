extends DevSuite
## Self-test: the connected world, the Crypt Road and its rules.

## The road's rules: its stretches are data (what lives where, how tough), the road gets conditions each time it is corrupted afresh
## (about half the time none), the conditions change what the empty stretches are stocked with and how the road looks, and world
## events reach the monsters already out there and the town's days.
func _test_road_rules() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.road_conditions_in_tests = true
	# The stretches.
	var zones: Dictionary = TownDb.zones()
	var tidy: bool = zones.size() == 4
	var reach: float = 0.0
	for id in TownDb.sorted_ids(zones):
		var zone: ZoneDef = zones[id]
		for template in zone.groups:
			tidy = tidy and float(template["weight"]) > 0.0 and not (template["members"] as Array).is_empty()
			for kind in template["members"]:
				tidy = tidy and EnemyDb.all().has(String(kind))
	expect("four stretches, each stocked with real monsters", tidy)
	expect("together they cover the whole road with no gap", TownDb.zone_at(0.0).id == "road_in" and TownDb.zone_at(63.9).id == "road_in"
		and TownDb.zone_at(64.0).id == "graveyard" and TownDb.zone_at(150.0).id == "wood" and TownDb.zone_at(300.0).id == "crypt_approach")
	expect("the further out, the tougher", TownDb.zone_at(10.0).base_threat < TownDb.zone_at(300.0).base_threat)
	# Conditions: about half the time none, never more than two, never ones that clash, always the same for the same seed.
	var none: int = 0
	var most: int = 0
	var clash: bool = false
	var repeatable: bool = true
	for seed_value in 400:
		var conditions: Array[String] = TownState.roll_road_conditions(seed_value)
		none += 1 if conditions.is_empty() else 0
		most = maxi(most, conditions.size())
		if conditions.size() == 2:
			clash = clash or conditions[1] in TownDb.modifier(conditions[0]).excludes or conditions[0] in TownDb.modifier(conditions[1]).excludes
		repeatable = repeatable and conditions == TownState.roll_road_conditions(seed_value)
	expect("about half of all roads have no condition (%d of 400)" % none, none > 150 and none < 250)
	expect("never more than two, never two that clash, the same every time for a seed", most <= 2 and not clash and repeatable)
	TownState.road_seed = 3
	var found: Dictionary = {}
	for i in 60:
		TownState.road_seed = i
		var offer: Dictionary = TownState.crypt_road_offer()
		if not (offer["modifiers"] as Array).is_empty():
			found = offer
			break
	var mult: float = 1.0
	for id in found["modifiers"]:
		mult *= TownDb.modifier(id).reward_mult
	expect("the board posts the road's conditions and they change its pay", not found.is_empty()
		and int(found["reward"]) == int(round(float(150 + 20 * mini(TownState.jobs_done, 10)) * mult)))
	TownState.reset()
	# What a condition does to the stocking, without a scene.
	var director := RunDirector.new()
	add_child(director)
	director.set_job({"modifiers": ["nest"]})
	director.wave = 3
	expect("a Spitters' Nest makes groups with spitters likelier", director.group_weight(["zombie", "spitter"]) > director.group_weight(["zombie", "zombie"]))
	director.set_job({"modifiers": ["shambling"]})
	expect("Shambling makes every group bigger", director.group_count_mult() > 1.1)
	director.set_job({})
	expect("no conditions change nothing", is_equal_approx(director.group_weight(["spitter"]), 1.0) and is_equal_approx(director.group_count_mult(), 1.0))
	director.queue_free()
	# The road itself.
	TownState.road_conditions_in_tests = false
	TownState.persist = false
	TownState.reset()
	TownState.gold = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	var town := TownScene.new()
	game.add_child(town)
	var waited: int = 0
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 36) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var crypt: CryptRoad = town.crypt
	var count_kind = func(kind: String) -> int:
		var n: int = 0
		for node in get_tree().get_nodes_in_group("enemies"):
			n += 1 if (node as Enemy).variant == kind else 0
		return n
	TownState.road_seed = 7
	await crypt.regrow()
	await get_tree().process_frame
	var plain_total: int = get_tree().get_nodes_in_group("enemies").size()
	# Road composition is authored; event modifiers must not restore filler or multiply packs.
	town.director.set_job({"modifiers": ["shambling", "nest"]})
	await crypt.regrow()
	await get_tree().process_frame
	expect("road modifiers cannot multiply authored encounters", get_tree().get_nodes_in_group("enemies").size() == plain_total)
	town.director.set_job({})
	# Light: a Darkness road is darker out on the road than a plain one, and the same in the plaza.
	var hero: Player = town.player
	hero.global_position = crypt.at(0, 100)
	town._update_world(0.1)
	var plain_light: float = town.world_environment.ambient_light_energy
	town.director.set_job({"modifiers": ["darkness"], "objective": JobObjective.destroy_nest(3), "site": CryptRoad.SITE_ID})
	town.director.wave = 3
	town._update_world(0.1)
	expect("a Darkness road is darker on the road", town.world_environment.ambient_light_energy < plain_light * 0.6)
	hero.global_position = Vector3(0, 0, 10)
	town._update_world(0.1)
	expect("and the plaza is the same", is_equal_approx(town.world_environment.ambient_light_energy, town._base_ambient))
	town.director.set_job({})
	# World events: they reach the monsters already out there, and the town's days.
	var sample: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		sample = node
		break
	var before: float = sample.max_health
	Quests.post("dangerous_dead")
	town.populate_quests()
	expect("a world event that makes the dead tougher reaches the ones already out there", is_equal_approx(sample.max_health, before * 1.35))
	town.populate_quests()
	expect("and only once", is_equal_approx(sample.max_health, before * 1.35))
	TownState.quests = []
	TownState.world_mods = []
	var food: int = TownState.food
	var mood: float = TownState.happiness("marlow")
	Quests.post("fat_harvest")
	Quests.on_day()
	expect("a fat harvest fills the granary and lifts moods each day", TownState.food == food + 2 and TownState.happiness("marlow") > mood)
	TownState.quests = []
	TownState.world_mods = []
	food = TownState.food
	mood = TownState.happiness("marlow")
	Quests.post("vulnerable_town")
	Quests.on_day()
	expect("thin walls cost food and spirits", TownState.food == food - 1 and TownState.happiness("marlow") < mood)
	# Saving remembers which road it is.
	TownState.road_seed = 12
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.road_seed = 0
	TownState.from_dict(saved)
	expect("the road's seed survives saving", TownState.road_seed == 12 and typeof(TownState.road_seed) == TYPE_INT)
	town.queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	TownState.reset()
	Quests.news.clear()

## The connected world: the plaza and the Crypt Road load together with every monster at the start, the hero simply walks out of the gate
## (no scene change, nothing to accept), a finished quest is waiting for him at Warden Hale, who has a coin over his head, and handing in
## pays, posts the next quest and puts the road back as it was; coming back stashes the bag, and a fallen hero is dragged home.
func _test_world() -> void:
	TownState.persist = false
	TownState.reset()
	TownState.gold = 0
	var scene_before: Node = get_tree().current_scene
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()   # the harness's own 80 m arena (and its invisible walls) would be in the way of the real world
	await get_tree().process_frame
	var town := TownScene.new()
	game.add_child(town)
	var waited: int = 0
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 36) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var crypt: CryptRoad = town.crypt
	expect("the plaza and the road are both there from the start", town.npcs.size() == 5 and crypt != null and crypt.nests.size() == 3)
	var monsters: Array = get_tree().get_nodes_in_group("enemies")
	var opening: Array = monsters.filter(func(e: Enemy): return e.group_id in [1, 2, 3, 4, 5])
	expect("authored opening uses fourteen low-threat fighters", opening.size() == 14 and opening.all(func(e: Enemy): return e.level == 1 and e.def.tier == "trivial" and e.max_health < 8 and e.damage_max <= 6.5))
	var awake: int = 0
	var beyond_gate: int = 0
	for node in monsters:
		awake += 1 if (node as Enemy)._aggro else 0
		beyond_gate += 1 if (node as Enemy).global_position.z < -TownScene.HALF else 0
	expect("every monster is already out on the road, asleep to the hero", monsters.size() >= 36 and awake == 0 and beyond_gate == monsters.size())
	expect("there is no gate to load: leaving town is not a function any more", not town.has_method("leave_through_gate"))
	# One walkable world: from the plaza through the gate, all the way to the crypt, and to every nest.
	var map: RID = town.get_world_3d().navigation_map
	var to_crypt: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(0, 0, 10), crypt.at(0, -150), true)
	var through_gate: bool = false
	for point in to_crypt:
		through_gate = through_gate or (absf(point.x) < 5.0 and point.z < -TownScene.HALF + 2.0 and point.z > -TownScene.HALF - 2.0)
	expect("a path runs from the plaza, through the gate, to the crypt", not to_crypt.is_empty() and to_crypt[to_crypt.size() - 1].distance_to(crypt.at(0, -150)) < 4.0 and through_gate)
	var reachable: int = 0
	for nest in crypt.nests:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, Vector3(0, 0, 10), nest.global_position, true)
		reachable += 1 if not path.is_empty() and path[path.size() - 1].distance_to(nest.global_position) < 4.5 else 0
	expect("every nest can be walked to from the plaza", reachable == 3)
	# The hero really walks out: click-to-move through the opening, under physics, no scene change.
	var hero: Player = town.player
	hero.global_position = Vector3(0, 0, -10)
	hero.reset_physics_interpolation()
	hero.movement.goal = crypt.at(0, 150)
	hero.movement.has_goal = true
	var seconds: float = 0.0
	while hero.global_position.z > -40.0 and seconds < 14.0:
		await get_tree().physics_frame
		seconds += 1.0 / 60.0
	expect("the hero walks out through the gate onto the road and nothing loads", hero.global_position.z < -40.0 and get_tree().current_scene == scene_before
		and town.outside and TownState.expedition)
	# Quests: progress is measured as it happens, nothing was accepted.
	expect("the quest is active without being taken and not yet done", not TownState.has_reward() and TownState.job.get("site") == CryptRoad.SITE_ID)
	hero.movement.has_goal = false
	for i in 3:
		crypt.nests[i].hit(999.0, Vector3.FORWARD)
		await get_tree().process_frame
		if i < 2:
			expect("nest %d destroyed: not done yet" % (i + 1), not TownState.has_reward() and crypt.nests_destroyed == i + 1)
	var hale: TownNpc = town.npcs["hale"]
	expect("the third nest finishes the quest and Hale has a coin over his head", TownState.has_reward() and hale.has_reward_marker())
	var others: bool = false
	for id in town.npcs:
		others = others or (id != "hale" and (town.npcs[id] as TownNpc).has_reward_marker())
	expect("nobody else has one", not others)
	# Home again: the bag goes to the stash, the quest is still waiting.
	hero.stats.bag.append(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 1, "Falchion"))
	var stash_before: int = TownState.stash.size()
	hero.global_position = Vector3(0, 0, -10)
	hero.reset_physics_interpolation()
	await get_tree().process_frame
	await get_tree().process_frame
	expect("coming home stashes the bag", not town.outside and hero.stats.bag.is_empty() and TownState.stash.size() == stash_before + 1)
	expect("the finished quest stays finished", TownState.has_reward() and hale.has_reward_marker())
	# Handing in.
	var gold_before: int = TownState.gold
	var reward: int = int(TownState.board[0]["reward"])
	town.panel.open_npc("hale")
	await get_tree().process_frame
	var collect: Button = _find_button(town.panel, "Collect")
	expect("Hale offers to pay out", collect != null and not collect.disabled)
	if collect != null:
		collect.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	expect("he pays the reward and posts the next quest", TownState.gold == gold_before + reward and TownState.jobs_done == 1 and TownState.board.size() == 1
		and not bool(TownState.board[0].get("ready", false)) and not hale.has_reward_marker())
	town.panel.close()
	waited = 0
	while get_tree().get_nodes_in_group("enemies").size() < 36 and waited < 300:
		await get_tree().physics_frame
		waited += 1
	var grown: int = 0
	for nest in crypt.nests:
		grown += 1 if is_instance_valid(nest) and not nest.broken else 0
	expect("the road is corrupted again: three nests and the monsters are back", grown == 3 and crypt.nests_destroyed == 0
		and get_tree().get_nodes_in_group("enemies").size() >= 36)
	# A fallen hero is dragged back to the plaza, whole.
	hero.global_position = crypt.at(0, 100)
	hero.reset_physics_interpolation()
	await get_tree().process_frame
	hero.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "source": null, "skill_id": "x", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, hero.global_position)
	await get_tree().process_frame
	expect("the hero fell", hero.dead)
	for member in PartyManager.current().living():
		member.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "source": null, "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, member.global_position)
	await get_tree().create_timer(4.0).timeout
	expect("he is dragged back to the plaza on his feet, with the world as it was", not hero.dead and hero.health > hero.max_health * 0.9
		and hero.global_position.z > -TownScene.HALF and get_tree().get_nodes_in_group("enemies").size() >= 36)
	town.queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	TownState.reset()

## The Crypt Road: the objective's bookkeeping, an elongated authored layout with three reachable nests, monsters that exist from the
## start and do their own thing until noticed (a group wakes together), and what destroying a nest does.
func _test_crypt_road() -> void:
	var offer: Dictionary = TownState.crypt_road_offer()
	var objective: Dictionary = offer["objective"]
	expect("a destroy_nest job reads as nests, not waves", JobObjective.describe(offer) == "Destroy 3 corrupted nests"
		and JobObjective.progress_text(offer, {"stage": 1}) == "Destroy nests: 1 / 3" and not JobObjective.uses_waves(offer)
		and not JobObjective.ends_run_when_complete(offer) and int(objective["count"]) == 3)
	expect("it completes at the third nest only", not JobObjective.is_complete(offer, {"stage": 2}) and JobObjective.is_complete(offer, {"stage": 3}))
	expect("a wave job still uses waves", JobObjective.uses_waves(JobObjective.upgrade_legacy({"name": "x", "waves": 3})))
	# Swap the wave arena for the location, as Main does for this job.
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena.queue_free()
	await get_tree().process_frame
	var place_arena: Arena = CryptRoad.make_arena()
	game.add_child(place_arena)
	place_arena.build(false)
	var place := CryptRoad.new()
	game.add_child(place)
	place.build(place_arena)
	player.global_position = CryptRoad.START
	player.reset_physics_interpolation()
	var footprint: float = place_arena.half_x * place_arena.half_z * 4.0
	expect("it is 3-5 times the old arena and long rather than square", footprint >= Arena.HALF * Arena.HALF * 4.0 * 3.0
		and footprint <= Arena.HALF * Arena.HALF * 4.0 * 5.0 and place_arena.half_z >= place_arena.half_x * 4.0)
	expect("it holds three nests", place.nests.size() == 3)
	var inside: bool = true
	for entry in place.placed:
		var pos: Vector3 = entry["pos"]
		inside = inside and absf(pos.x) < place_arena.half_x and absf(pos.z) < place_arena.half_z
	expect("everything placed is inside the walls", inside and place.placed.size() > 150)
	expect("the middle of the road is clear of solid props", place.road_distance(0.0, 100.0) < 3.0
		and not place.placed.any(func(e: Dictionary) -> bool: return e["name"] == "dead_tree" and place.road_distance(e["pos"].x, e["pos"].z) < CryptRoad.ROAD_HALF_WIDTH))
	await place.wait_for_navigation()
	expect("the navigation map takes the whole road", place.navigation_ready())
	var map: RID = game.get_world_3d().navigation_map
	var reachable: int = 0
	for nest in place.nests:
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, CryptRoad.START, nest.global_position, true)
		var gap: float = path[path.size() - 1].distance_to(nest.global_position) if not path.is_empty() else -1.0
		if gap >= 0.0 and gap < 4.5:
			reachable += 1
		else:
			print("  nest at ", nest.global_position, " path points ", path.size(), " ends ", gap, " m from it")
	expect("every nest can be walked to from the start", reachable == 3)
	var crypt_path: PackedVector3Array = NavigationServer3D.map_get_path(map, CryptRoad.START, Vector3(0, 0, -150), true)
	expect("the road runs the whole length, to the crypt courtyard", not crypt_path.is_empty() and crypt_path[crypt_path.size() - 1].z < -140.0)
	# Structural checks complement real starter combat in road_pacing_check.gd.
	var run: RunDirector = game.director
	run.set_job(offer)
	run.start_location(place)
	await get_tree().process_frame
	var all: Array = get_tree().get_nodes_in_group("enemies")
	var groups: Dictionary = {}
	for e: Enemy in all:
		groups[e.group_id] = int(groups.get(e.group_id, 0)) + 1
	expect("road has twenty-four authored groups and no multiplied filler", groups.size() == 24 and all.size() == 61 and groups.values().all(func(n): return int(n) <= 3))
	expect("road has no acid or explosive/support packs", all.all(func(e: Enemy): return e.variant in ["zombie", "rock_thrower", "ghoul", "brute", "warden"]))
	var mates: Array = all.filter(func(e: Enemy): return e.group_id == 6)
	mates[0].wake()
	expect("only the small local group wakes together", mates.size() == 2 and mates.all(func(e: Enemy): return e._aggro))
	# The nests.
	var count_before: int = get_tree().get_nodes_in_group("enemies").size()
	var first: Destructible = place.nests[0]
	var nearby: Enemy = null
	for node in all:
		var e: Enemy = node
		if not e._aggro and e.global_position.distance_to(first.global_position) < 8.0:
			nearby = e
	first.hit(999.0, Vector3.FORWARD)
	await get_tree().process_frame
	expect("the hero's own swings can break a nest (and a click picks it)", Destructible.near(get_tree(), place.nests[1].global_position, 3.0, Destructible.HERO) == place.nests[1])
	expect("destroying a nest counts once and shows on the HUD line", place.nests_destroyed == 1 and run.progress()["stage"] == 1
		and run.objective_line() == "Destroy nests: 1 / 3")
	expect("it stirs up what lived nearby", nearby == null or nearby._aggro)
	expect("something climbs out of the broken nest", get_tree().get_nodes_in_group("enemies").size() >= count_before + 2)
	expect("there is no wave (the world does not borrow one), and the run does not end when the field is cleared", run.location == null or run.wave == 0)
	place.nests[1].hit(999.0, Vector3.FORWARD)
	place.nests[2].hit(999.0, Vector3.FORWARD)
	await get_tree().process_frame
	expect("three nests complete the job", JobObjective.is_complete(offer, run.progress()) and run.objective_line() == "Destroy nests: 3 / 3")
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	# Walking out through the road gate with the job done hands it in.
	player.global_position = Vector3(0, 0, CryptRoad.EXIT_Z)
	player.reset_physics_interpolation()
	await get_tree().create_timer(1.2).timeout
	expect("walking out through the gate with the nests gone ends the run", run.is_ending())

## Wave 3 road density: how many bodies each stretch of the Crypt Road holds, how far apart they stand, where the brutes and elites
## are, and that a regrow puts the whole population back exactly once.
func _test_road_density() -> void:
	TownState.road_seed = 7
	var arena_before: Arena = arena
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	arena_before.queue_free()
	await get_tree().process_frame
	var place_arena: Arena = CryptRoad.make_arena()
	game.add_child(place_arena)
	place_arena.build(false)
	var place := CryptRoad.new()
	game.add_child(place)
	place.build(place_arena)
	await place.wait_for_navigation()
	var run: RunDirector = game.director
	run.set_job(TownState.crypt_road_offer())
	run.start_location(place)
	await get_tree().process_frame
	var segments: Dictionary = {"intro": 0, "graveyard": 0, "wood": 0, "courtyard": 0, "forecourt": 0}
	var positions: Array[Vector3] = []
	var brute_z: Array[float] = []
	var warden_z: float = 999.0
	var kinds: Dictionary = {}
	var groups: Dictionary = {}
	var nest: Vector3 = place.nests[2].global_position
	var brute_near_nest: bool = false
	var enemies: Array = get_tree().get_nodes_in_group("enemies").filter(func(n): return n is Enemy and n.group_id > 0 and n.group_id < 100)
	for e: Enemy in enemies:
		var z: float = e.global_position.z - place_arena.origin_offset.z
		var seg: String = "forecourt" if z <= -146.0 else ("courtyard" if z <= -40.0 else ("wood" if z <= 40.0 else ("graveyard" if z <= 110.0 else "intro")))
		segments[seg] = int(segments[seg]) + 1
		positions.append(e.global_position)
		kinds[e.variant] = int(kinds.get(e.variant, 0)) + 1
		groups[e.group_id] = int(groups.get(e.group_id, 0)) + 1
		if e.variant == "brute":
			brute_z.append(z)
			brute_near_nest = brute_near_nest or e.global_position.distance_to(nest) < 18.0
		if e.variant == "warden":
			warden_z = minf(warden_z, z)
	print("  road density: ", segments, " total ", enemies.size(), " groups ", groups.size(), " kinds ", kinds)
	var intro: int = int(segments["intro"])
	var graveyard: int = int(segments["graveyard"])
	var wood: int = int(segments["wood"])
	var courtyard: int = int(segments["courtyard"])
	expect("the opening stretch stays manageable (%d bodies)" % intro, intro >= 8 and intro <= 10)
	expect("the graveyard stretch is 40%% to 100%% busier than before, not a swarm (%d)" % graveyard, graveyard >= 14 and graveyard <= 20)
	expect("the wooded choke is at least half again as busy as before (%d)" % wood, wood >= 12 and wood <= 16)
	expect("the courtyard is at least half again as busy as before (%d)" % courtyard, courtyard >= 12 and courtyard <= 16)
	expect("the forecourt keeps its own two bodies (%d)" % int(segments["forecourt"]), int(segments["forecourt"]) == 2)
	expect("no stretch holds more bodies than the per-segment cap (%d)" % RoadEncounterRoster.SEGMENT_CAP,
		graveyard <= RoadEncounterRoster.SEGMENT_CAP and wood <= RoadEncounterRoster.SEGMENT_CAP and courtyard <= RoadEncounterRoster.SEGMENT_CAP)
	expect("the road holds no more than %d bodies in all" % RoadEncounterRoster.TOTAL_CAP, enemies.size() <= RoadEncounterRoster.TOTAL_CAP)
	expect("no group is larger than four bodies", groups.values().all(func(n): return int(n) <= 4))
	var overlapping: int = 0
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			var a: Vector3 = positions[i]
			var b: Vector3 = positions[j]
			if Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) < 1.2:
				overlapping += 1
				print("  overlap: ", a, " ", b, " groups ", enemies[i].group_id, " ", enemies[j].group_id)
	expect("no two enemies spawn overlapping (%d pairs)" % overlapping, overlapping == 0)
	expect("brutes guard the wooded choke, the graveyard and the third nest's approach", brute_z.size() == 3 and brute_near_nest
		and brute_z.any(func(z): return z > 40.0 and z <= 110.0) and brute_z.any(func(z): return z > -40.0 and z <= 40.0))
	expect("a warden stands in the courtyard, before the forecourt (z %.0f)" % warden_z, warden_z > -146.0 and warden_z <= -110.0)
	# A regrow (the quest is handed in again) puts the whole population back once, with nothing doubled.
	await place.regrow()
	await get_tree().process_frame
	var after: Array = get_tree().get_nodes_in_group("enemies").filter(func(n): return n is Enemy and n.group_id > 0 and n.group_id < 100)
	expect("a regrow restores the same population exactly once (%d, was %d)" % [after.size(), enemies.size()], after.size() == enemies.size())
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	place.queue_free()
	place_arena.queue_free()
	await get_tree().process_frame
