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
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 40) and waited < 900:
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
	# Stocking, over many groups: a Spitters' Nest makes the groups with spitters in them much likelier, and Shambling makes them bigger.
	var zone: ZoneDef = TownDb.zones()["crypt_approach"]
	var with_spitter: Callable = func() -> int:
		crypt._fill_rng.seed = 5
		var n: int = 0
		for i in 300:
			n += 1 if "spitter" in crypt._fill_kinds(zone) else 0
		return n
	town.director.set_job({})
	var plain_groups: int = with_spitter.call()
	town.director.set_job({"modifiers": ["nest"], "objective": JobObjective.destroy_nest(3), "site": CryptRoad.SITE_ID})
	town.director.wave = 3
	var nest_groups: int = with_spitter.call()
	expect("with a Spitters' Nest far more groups have spitters (%d of 300 against %d)" % [nest_groups, plain_groups], nest_groups > plain_groups * 1.3)
	town.director.set_job({"modifiers": ["shambling"], "objective": JobObjective.destroy_nest(3), "site": CryptRoad.SITE_ID})
	town.director.wave = 3
	crypt._fill_rng.seed = 5
	var sizes: int = 0
	for i in 100:
		sizes += crypt._fill_kinds(zone).size()
	town.director.set_job({})
	crypt._fill_rng.seed = 5
	var plain_sizes: int = 0
	for i in 100:
		plain_sizes += crypt._fill_kinds(zone).size()
	expect("and with Shambling the groups are bigger (%d against %d monsters in 100 groups)" % [sizes, plain_sizes], sizes > plain_sizes)
	TownState.road_seed = 8
	town.director.set_job({})
	await crypt.regrow()
	await get_tree().process_frame
	expect("each reset of the road stocks it differently", get_tree().get_nodes_in_group("enemies").size() != plain_total or count_kind.call("ghoul") != 0)
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
	while (town.director == null or get_tree().get_nodes_in_group("enemies").size() < 40) and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var crypt: CryptRoad = town.crypt
	expect("the plaza and the road are both there from the start", town.npcs.size() == 5 and crypt != null and crypt.nests.size() == 3)
	var monsters: Array = get_tree().get_nodes_in_group("enemies")
	var awake: int = 0
	var beyond_gate: int = 0
	for node in monsters:
		awake += 1 if (node as Enemy)._aggro else 0
		beyond_gate += 1 if (node as Enemy).global_position.z < -TownScene.HALF else 0
	expect("every monster is already out on the road, asleep to the hero", monsters.size() >= 40 and awake == 0 and beyond_gate == monsters.size())
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
	while get_tree().get_nodes_in_group("enemies").size() < 40 and waited < 300:
		await get_tree().physics_frame
		waited += 1
	var grown: int = 0
	for nest in crypt.nests:
		grown += 1 if is_instance_valid(nest) and not nest.broken else 0
	expect("the road is corrupted again: three nests and the monsters are back", grown == 3 and crypt.nests_destroyed == 0
		and get_tree().get_nodes_in_group("enemies").size() >= 40)
	# A fallen hero is dragged back to the plaza, whole.
	hero.global_position = crypt.at(0, 100)
	hero.reset_physics_interpolation()
	await get_tree().process_frame
	hero.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "source": null, "skill_id": "x", "weight": 1.0, "type": Combat.DamageType.PHYSICAL}, hero.global_position)
	await get_tree().process_frame
	expect("the hero fell", hero.dead)
	await get_tree().create_timer(4.0).timeout
	expect("he is dragged back to the plaza on his feet, with the world as it was", not hero.dead and hero.health > hero.max_health * 0.9
		and hero.global_position.z > -TownScene.HALF and get_tree().get_nodes_in_group("enemies").size() >= 40)
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
	# The monsters.
	var run: RunDirector = game.director
	run.set_job(offer)
	run.start_location(place)
	await get_tree().process_frame
	var all: Array = get_tree().get_nodes_in_group("enemies")
	var near_start: int = 0
	var awake: int = 0
	var kinds: Dictionary = {}
	for node in all:
		var e: Enemy = node
		near_start += 1 if e.global_position.distance_to(CryptRoad.START) < 12.0 else 0
		awake += 1 if e._aggro else 0
		kinds[e.variant] = true
	print("  monsters ", all.size(), " awake ", awake, " within 12 m of the start ", near_start)
	expect("monsters already exist across the road, none awake and none on the hero", all.size() >= 40 and awake == 0 and near_start == 0)
	expect("it uses the whole cast: zombies, ghouls, spitters, a bloater, a priest, brutes and a warden", kinds.size() == 7 and kinds.has("zombie") and kinds.has("ghoul")
		and kinds.has("spitter") and kinds.has("bloater") and kinds.has("priest") and kinds.has("brute") and kinds.has("warden"))
	expect("the road is crowded: about four times the old hand-placed count", all.size() >= 170 and all.size() <= 280)
	# No long stretch is left empty: from the first walkers to the crypt door, across the road and out under the trees.
	var worst: float = 0.0
	var worst_at: Vector2 = Vector2.ZERO
	var z_probe: float = 128.0
	while z_probe > -150.0:
		for x_probe in [-18.0, 0.0, 18.0]:
			var probe: Vector3 = place.at(x_probe, z_probe)
			var nearest: float = 9999.0
			for node in all:
				nearest = minf(nearest, (node as Enemy).global_position.distance_to(probe))
			if nearest > worst:
				worst = nearest
				worst_at = Vector2(x_probe, z_probe)
		z_probe -= 10.0
	print("  road monsters ", all.size(), "; the emptiest probe point is ", snappedf(worst, 0.1), " m from the nearest one, at ", worst_at)
	expect("nowhere along the road is more than 32 m from a monster", worst <= 32.0)
	var feeder: Enemy = null
	var spitter: Enemy = null
	var melee_front: float = -INF
	for node in all:
		var e: Enemy = node
		if e.idle_mode == "feed" and feeder == null:
			feeder = e
		if e.variant == "spitter" and e.global_position.z < 80.0 and e.global_position.z > 60.0:
			spitter = e
		if e.variant == "zombie" and e.group_id == 7:
			melee_front = maxf(melee_front, e.global_position.z)
	expect("some are feeding at a corpse", feeder != null)
	expect("the cottage spitters stand behind its melee line (farther from the way in)", spitter != null and spitter.global_position.z < melee_front - 4.0)
	await get_tree().create_timer(1.0).timeout
	expect("a feeder is hunched over, a sleeper has not walked off", feeder.visual.rotation.x > 0.3 and not feeder._aggro)
	var walkers: Array[Enemy] = []
	var walked_from: Array[Vector3] = []
	for node in all:
		if (node as Enemy).group_id == 1:
			walkers.append(node)
			walked_from.append((node as Enemy).global_position)
	await get_tree().create_timer(2.5).timeout
	var strolled: bool = false
	var calm: bool = true
	for i in walkers.size():   # (any of the group may be in a pause)
		strolled = strolled or walkers[i].global_position.distance_to(walked_from[i]) > 0.6
		calm = calm and not walkers[i]._aggro
	expect("a walker strolls about on its own", strolled and calm)
	# Far, unaware monsters sleep and wake as the hero comes near, so the crowd costs little.
	run.player.global_position = place.at(0.0, -100.0)
	await get_tree().create_timer(0.8).timeout
	var asleep_far: int = 0
	var asleep_near: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var sleeper: Enemy = node
		if sleeper.process_mode == Node.PROCESS_MODE_DISABLED:
			if sleeper.global_position.distance_to(run.player.global_position) > RunDirector.SLEEP_BEYOND:
				asleep_far += 1
			elif sleeper.global_position.distance_to(run.player.global_position) < RunDirector.WAKE_WITHIN:
				asleep_near += 1
	expect("monsters far from the hero (at the crypt) sleep and none near him do (%d far)" % asleep_far, asleep_far > 60 and asleep_near == 0)
	run.player.global_position = CryptRoad.START
	await get_tree().create_timer(0.8).timeout
	var woken: int = 0
	for node in get_tree().get_nodes_in_group("enemies"):
		var sleeper: Enemy = node
		if sleeper.global_position.distance_to(run.player.global_position) < RunDirector.WAKE_WITHIN and sleeper.process_mode != Node.PROCESS_MODE_DISABLED:
			woken += 1
	expect("and they wake when he comes close", woken > 20)
	run.player.global_position = CryptRoad.START
	await get_tree().create_timer(0.8).timeout
	# Noticing one wakes its group.
	var mates: Array[Enemy] = []
	for node in all:
		if (node as Enemy).group_id == 6:
			mates.append(node)
	mates[0].wake()
	var all_awake: bool = true
	for m in mates:
		all_awake = all_awake and m._aggro
	expect("when one of a group notices the hero the whole group does", mates.size() >= 3 and all_awake)
	# The nests.
	var count_before: int = get_tree().get_nodes_in_group("enemies").size()
	var first: Destructible = place.nests[0]
	var nearby: Enemy = null
	for node in all:
		var e: Enemy = node
		if not e._aggro and e.global_position.distance_to(first.global_position) < 20.0:
			nearby = e
	first.hit(999.0, Vector3.FORWARD)
	await get_tree().process_frame
	expect("the hero's own swings can break a nest (and a click picks it)", Destructible.near(get_tree(), place.nests[1].global_position, 3.0, Destructible.HERO) == place.nests[1])
	expect("destroying a nest counts once and shows on the HUD line", place.nests_destroyed == 1 and run.progress()["stage"] == 1
		and run.objective_line() == "Destroy nests: 1 / 3")
	expect("it stirs up what lived nearby", nearby == null or nearby._aggro)
	expect("something climbs out of the broken nest", get_tree().get_nodes_in_group("enemies").size() >= count_before + 3)
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
