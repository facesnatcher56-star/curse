extends DevSuite
## Monsters that plot, the Warden (self-test and --wardenshot) and the archer companion.

## The monsters that act on their own: they rise on the road, grow every day, plot (raids, altars, hordes, scouts), the plots end on their
## own days or when the monster is killed, a kill of the hero makes a nemesis, and all of it is told in the Chronicle and saved.
func _test_monsters() -> void:
	TownState.persist = false
	TownState.reset()
	# Named monsters are switched off (Monsters.ENABLED): a saved one stays inert, so nothing grows or spawns, whatever the save holds.
	TownState.monsters = [{"uid": 99, "name": "Saved", "level": 3.4, "kills": 0, "nemesis": false, "plot": {}}]
	expect("named monsters are off: none alive and no card, though one is saved", Monsters.alive().is_empty() and Monsters.cards().is_empty())
	TownState.reset()
	Monsters.in_tests = true
	Monsters.rng.seed = 11
	Monsters.gossip.clear()
	Quests.news.clear()
	var mon: Dictionary = Monsters.rise()
	expect("a named monster rises with a name, a level and a place on the road", TownState.monsters.size() == 1 and String(mon["name"]) != ""
		and float(mon["level"]) == Monsters.START_LEVEL and float(mon["dist"]) >= 50.0 and EnemyDb.all().has(String(mon["kind"])))
	expect("it is in the Chronicle, in the banner news and as gossip", TownState.chronicle.size() == 1 and String(TownState.chronicle[0]["kind"]) == "monster"
		and Quests.news.size() == 1 and Monsters.gossip.size() == 1)
	var uid: int = int(mon["uid"])
	# Days: it grows.
	var before: float = float(mon["level"])
	Monsters.on_day()
	TownState.monsters = [mon]   # (a second one may have risen: the checks follow this one)
	expect("it grows every day", is_equal_approx(float(Monsters.find(uid)["level"]), before + Monsters.EVOLVE_PER_DAY))
	# A raid, forced to end tomorrow.
	TownState.food = 10
	TownState.gold = 100
	mon["level"] = 3.0
	mon["plot"] = {"type": "raid", "days_left": 1, "total": 3}
	var mood: float = TownState.happiness("marlow")
	Monsters.on_day()
	TownState.monsters = [mon]
	expect("a raid that comes to its end costs food, gold and nerve, and is over", (mon["plot"] as Dictionary).is_empty() and TownState.food < 10
		and TownState.gold < 100 and TownState.happiness("marlow") < mood)
	var told: bool = false
	for entry in TownState.chronicle:
		told = told or String(entry["text"]).contains("hit the gate")
	expect("and told", told)
	# A plot that has days to go counts down and shows as a card with a bar.
	mon["plot"] = {"type": "altar", "days_left": 3, "total": 4}
	var card: Dictionary = Monsters.cards()[0]
	expect("a plot in progress shows on a card with how far it has got", String(card["sub"]).contains("altar") and is_equal_approx(float(card["frac"]), 0.25))
	# The altar finishes: a standing effect on the road, until its maker is killed.
	mon["plot"] = {"type": "altar", "days_left": 1, "total": 4}
	Monsters.on_day()
	TownState.monsters = [mon]
	expect("a finished altar makes the dead harder, and asks the road to apply it", Quests.world_mult("health_mult") > 1.19 and String(mon["fired"]) == "altar")
	expect("and it shows as a card", Monsters.cards().size() == 2)
	# The hero is killed by it.
	var level_before: float = float(mon["level"])
	var line: String = Monsters.hero_fell(uid)
	expect("a monster that kills the hero is a nemesis: stronger, with a title and a line", bool(mon["nemesis"]) and int(mon["kills"]) == 1
		and float(mon["level"]) > level_before and Monsters.title_of(mon).ends_with("Slayer of 1") and line.contains(String(mon["name"])))
	# And killed in turn.
	var gold: int = TownState.gold
	var paid: Dictionary = Monsters.killed(uid)
	expect("killing it pays the bounty (more for a nemesis), takes the altar down and leaves two good items", int(paid["items"]) == 2 and TownState.gold > gold + 70
		and Quests.world_mult("health_mult") == 1.0 and Monsters.find(uid).is_empty() and TownState.monsters.is_empty())
	# A killer that was not named is named now.
	var promoted: Dictionary = Monsters.promote("ghoul", 120.0)
	expect("a monster that was not named takes a name when it kills the hero", bool(promoted["nemesis"]) and int(promoted["kills"]) == 1 and TownState.monsters.size() == 1)
	# Plots all fire.
	var kinds_ok: bool = true
	for type in Monsters.PLOTS:
		promoted["plot"] = {"type": type, "days_left": 1, "total": 2}
		TownState.world_mods = []
		Monsters.on_day()
		TownState.monsters = [promoted]
		kinds_ok = kinds_ok and (promoted["plot"] as Dictionary).is_empty()
	expect("every kind of plot comes to its end", kinds_ok)
	# Saving.
	TownState.chronicle.append({"day": 4, "kind": "event", "text": "x"})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	TownState.monsters = []
	TownState.chronicle = []
	TownState.from_dict(saved)
	expect("the monsters and the Chronicle survive saving, whole numbers and all", TownState.monsters.size() >= 1 and typeof(TownState.monsters[0]["uid"]) == TYPE_INT
		and typeof(TownState.monsters[0]["kills"]) == TYPE_INT and not TownState.chronicle.is_empty() and typeof(TownState.chronicle[0]["day"]) == TYPE_INT)
	# The Chronicle keeps its size, and the quests write to it too.
	TownState.chronicle = []
	for i in Chronicle.MAX_ENTRIES + 20:
		Chronicle.add("town", "n%d" % i)
	expect("the Chronicle keeps only the latest entries", TownState.chronicle.size() == Chronicle.MAX_ENTRIES and String(Chronicle.recent(1)[0]["text"]) == "n%d" % (Chronicle.MAX_ENTRIES + 19))
	TownState.chronicle = []
	Quests.clocks_in_tests = true
	Quests.post("fog_bank")
	expect("a world event is written to the Chronicle when it starts", TownState.chronicle.size() == 1 and String(TownState.chronicle[0]["kind"]) == "event")
	Monsters.in_tests = false
	Quests.clocks_in_tests = false
	TownState.reset()
	Quests.news.clear()
	Monsters.gossip.clear()

## The monsters on the road itself: a named monster has its body, marks and strength, a plot has its sign, a kill pays the bounty and clears the
## sign, and a killer that was not named is named.
func _test_monster_scene() -> void:
	TownState.persist = false
	TownState.reset()
	Monsters.in_tests = true
	Monsters.rng.seed = 5
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
	var mon: Dictionary = Monsters.rise()
	mon["kind"] = "ghoul"
	mon["plot"] = {"type": "raid", "days_left": 2, "total": 3}
	town.populate_monsters()
	var body: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("monster_uid"):
			body = node
	expect("a named monster is put on the road with its name and strength", body != null and body.display_name == String(mon["name"])
		and body.max_health > MonsterScaling.life(1, EnemyDb.get_def("ghoul").tier, EnemyDb.get_def("ghoul").role) * 1.4 and body.get_child_count() > 3)
	expect("it is marked: a diamond and its name over its head", body.find_children("*", "Label3D", false, false).size() == 1 and body.find_children("*", "Sprite3D", false, false).size() == 1)
	expect("its plot has a sign on the road", get_tree().get_nodes_in_group("plot_signs").size() == 1)
	var strength: float = body.max_health
	mon["level"] = float(mon["level"]) + 2.0
	town.populate_monsters()
	expect("it grows with its level, and is not made again", body.max_health > strength * 1.4 and get_tree().get_nodes_in_group("enemies").filter(func(n: Node) -> bool: return n.has_meta("monster_uid")).size() == 1)
	var hud_cards: Array[Dictionary] = Monsters.cards()
	expect("the HUD has a card for it", hud_cards.size() == 1)
	# Its death: the bounty, the drop, the sign gone.
	var drops: int = get_tree().get_nodes_in_group("loot").size()
	TownState.gold = 0
	town.director._report_to_quests(body)
	town.populate_monsters()
	await get_tree().process_frame
	expect("killing it pays the bounty and leaves an item", TownState.gold > 50 and get_tree().get_nodes_in_group("loot").size() > drops and Monsters.alive().is_empty())
	expect("and its sign comes down", get_tree().get_nodes_in_group("plot_signs").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion()).is_empty())
	# A killer that was not named takes a name (it can fail the roll: try a few).
	var plain: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if not (node as Enemy).dead and not node.has_meta("quest_uid") and not node.has_meta("monster_uid"):
			plain = node
			break
	var line: String = ""
	for attempt in 12:
		town.player.last_hit_by = plain
		line = town._killer_takes_credit()
		if line != "":
			break
	expect("a monster that kills the hero takes a name and a mark", line != "" and plain.has_meta("monster_uid") and Monsters.alive().size() == 1
		and plain.display_name == String(Monsters.alive()[0]["name"]))
	town.queue_free()
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	Monsters.in_tests = false
	TownState.reset()
	Quests.news.clear()
	Monsters.gossip.clear()

func _test_archer_companion() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().process_frame
	var archer: ArcherCompanion = game.companion
	archer.testing_disabled = false
	archer.target = null
	archer.shots_fired = 0
	archer.last_hit_target = null
	archer.take_aim_armed = false
	archer.take_aim_reload_required = 0.0
	archer.take_aim_reload_remaining = 0.0
	archer.global_position = Vector3(2.0, 0.0, 2.0)
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	_test_archer_draw(archer)
	var quiet: Enemy = _spawn_enemy(Vector3(-4.0, 0.0, -8.0))
	quiet.aggro_range = 0.0
	quiet.max_health = 500.0
	quiet.health = quiet.max_health
	var threats: Array[Enemy] = []
	for pos in [Vector3(0.0, 0.0, -8.0), Vector3(4.0, 0.0, -9.0)]:
		var enemy: Enemy = _spawn_enemy(pos)
		enemy.set_physics_process(false)   # Test draw/impact separately from chase/retreat below.
		enemy.max_health = 500.0
		enemy.health = enemy.max_health
		enemy.target = player
		enemy.wake()
		threats.append(enemy)
	archer.target = threats[0]
	archer._cooldown = 0.9
	archer._draw = 0.45
	archer.activate_take_aim_now()
	expect("Take Aim interrupts Cutter's normal shot and bypasses its recovery instead of queueing",
		archer.take_aim_armed and is_zero_approx(archer._cooldown) and is_zero_approx(archer._draw) and archer.target == threats[0])
	var saw_draw: bool = false
	var elapsed: float = 0.0
	while elapsed < 3.5 and archer.last_hit_target == null:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		saw_draw = saw_draw or archer._draw > 0.25
	var hit_threat: bool = archer.last_hit_target in threats
	if not hit_threat:
		print("  archer shot fixture: pos=", archer.global_position, " draw=", archer._draw, " target=", archer.target, " shots=", archer.shots_fired)
	expect("Cutter carries Blender-authored bow, quiver and draw arrow", archer._draw_arrow != null and ResourceLoader.exists(ArcherCompanion.BOW_MODEL)
		and ResourceLoader.exists(ArcherCompanion.QUIVER_MODEL) and ResourceLoader.exists(ArcherCompanion.ARROW_MODEL))
	expect("Cutter draws before loosing a visible physical arrow", saw_draw and archer.shots_fired >= 1)
	expect("Cutter attacks only an enemy aggroed onto the hero", hit_threat and quiet.health == quiet.max_health)
	expect("the arrow uses the normal hit/reaction path", hit_threat and archer.last_hit_target.health < archer.last_hit_target.max_health
		and archer.last_hit_target.flinch_serial > 0 and archer.last_hit_target.hero_credited())
	var expected_take_aim_reload: float = player.stats.power_recharge_damage(ArcherCompanion.TAKE_AIM_COMBAT_SECONDS, "ranged", archer)
	expect("Cutter's first Ranged power is a 1500% non-crit Take Aim shot with DS2's fast recharge",
		hit_threat and archer.last_hit_target.max_health - archer.last_hit_target.health > (3.0 + 0.65 * archer.level) * 5.0
		and not archer.take_aim_armed and is_equal_approx(archer.take_aim_reload_required, expected_take_aim_reload)
		and is_equal_approx(archer.take_aim_reload_remaining, expected_take_aim_reload))
	var take_aim_before_party_hit: float = archer.take_aim_reload_remaining
	player.on_dealt_hit(archer.last_hit_target,
		{"outcome": Combat.Outcome.HIT, "damage": 25.0, "skill_id": "basic", "secondary": false})
	expect("active-party damage recharges Cutter's Take Aim",
		is_equal_approx(archer.take_aim_reload_remaining, take_aim_before_party_hit - 25.0))
	var spacing_target: Enemy = threats[0]
	# Isolate retreat from random threat selection, chasing bodies and kills.
	for threat_enemy in threats:
		threat_enemy.set_physics_process(false)
		threat_enemy.health = threat_enemy.max_health
		if threat_enemy != spacing_target:
			threat_enemy.target = null
			threat_enemy.global_position += Vector3(60, 0, 60)
	spacing_target.move_speed = 0.0
	archer.target = spacing_target
	# Start inside bow distance but outside the two bodies' collision overlap, so this measures AI retreat rather than depenetration.
	archer.global_position = spacing_target.global_position + Vector3(0.0, 0.0, 6.0)
	player.global_position = spacing_target.global_position + Vector3(11.0, 0.0, 0.0)
	player.reset_physics_interpolation()
	var spacing_elapsed: float = 0.0
	while spacing_elapsed < 3.0 and archer.flat_distance_to(spacing_target) < ArcherCompanion.MIN_COMBAT_RANGE - 0.6:
		await get_tree().physics_frame
		spacing_elapsed += 1.0 / 60.0
	expect("Cutter backs out to archer range instead of following the hero into melee",
		archer.flat_distance_to(spacing_target) >= ArcherCompanion.MIN_COMBAT_RANGE - 0.6
		and archer.flat_distance_to(player) > ArcherCompanion.FOLLOW_DISTANCE + 1.0)
	var tether_before: float = ArcherCompanion.HARD_TETHER_DISTANCE + 4.0
	player.global_position = archer.global_position + Vector3(tether_before, 0.0, 0.0)
	player.reset_physics_interpolation()
	await get_tree().create_timer(0.8).timeout
	expect("the hard player tether overrides combat spacing", archer.flat_distance_to(player) < tether_before - 1.0)
	for enemy in threats:
		enemy.queue_free()
	quiet.queue_free()
	await get_tree().process_frame
	archer.target = null
	player.global_position += Vector3(8.0, 0.0, 0.0)
	player.reset_physics_interpolation()
	var displaced_gap: float = archer.flat_distance_to(player)
	await get_tree().create_timer(1.0).timeout
	expect("Cutter automatically follows the moving hero", archer.flat_distance_to(player) < displaced_gap - 1.0)
	archer.testing_disabled = true
	archer.target = null

## Geometry checks catch detached props, a fixed string hand and reversed projectile axes.
func _test_archer_draw(archer: ArcherCompanion) -> void:
	archer.visual.rotation.y = 0.0
	var carry_attached: bool = true
	var carry_upright: bool = true
	var carry_clear: bool = true
	for clip in ["walk", "run"]:
		archer.model.manual(clip)
		archer._draw = 0.0
		archer._release = 0.0
		for phase in [0.0, 0.25, 0.50, 0.75]:
			archer.model.scrub(phase)
			var left_hand: Vector3 = archer._skeleton.to_global(archer._skeleton.get_bone_global_pose(int(archer._pose_bones["LeftHand"])).origin)
			carry_attached = carry_attached and archer._bow_holder.to_global(Vector3(-0.065, 0.0, 0.0)).distance_to(left_hand) < 0.01
			carry_upright = carry_upright and archer._bow_holder.global_basis.y.normalized().dot(Vector3.UP) > 0.95
			carry_clear = carry_clear and archer._bow_holder.to_global(Vector3(0.065, -0.78, 0.0)).y > archer.global_position.y + 0.10
	expect("walk/run keep the bow grip attached to the left hand", carry_attached)
	expect("walk/run carry the bow upright without dragging a limb or showing a nocked arrow", carry_upright and carry_clear and not archer._draw_arrow.visible)
	archer.model.manual("idle")
	archer._draw = 0.20
	archer.model.scrub(0.0)
	var hand: int = int(archer._pose_bones["RightHand"])
	var start: Vector3 = archer._skeleton.to_global(archer._skeleton.get_bone_global_pose(hand).origin)
	archer._draw = 0.92
	archer.model.scrub(0.0)
	var drawn: Vector3 = archer._skeleton.to_global(archer._skeleton.get_bone_global_pose(hand).origin)
	var box: AABB = archer._draw_arrow.get_meta("mesh_bounds")
	var nock: Vector3 = archer._draw_arrow.to_global(Vector3(0.0, -box.size.y * 0.5, 0.0))
	var left: Vector3 = archer._skeleton.to_global(archer._skeleton.get_bone_global_pose(int(archer._pose_bones["LeftHand"])).origin)
	var grip: Vector3 = archer._bow_holder.to_global(Vector3(-0.065, 0.0, 0.0))
	expect("bow draw pulls the string hand backward before release", start.z - drawn.z > 0.15)
	expect("bow grip and arrow nock stay attached to solved hands", grip.distance_to(left) < 0.01 and nock.distance_to(drawn) < 0.01)
	expect("nocked arrow points along the character's facing, not across the bow", archer._draw_arrow.global_basis.y.normalized().dot(archer.visual.global_basis.z.normalized()) > 0.95)
	var from: Vector3 = archer.global_position + Vector3.UP * 5.0
	var normal: CompanionArrow = CompanionArrow.fire(game, archer, from, from + Vector3.FORWARD, 1.0)
	var power: CompanionArrow = CompanionArrow.fire(game, archer, from, from + Vector3.FORWARD, 1.0, true)
	expect("only Take Aim carries the enhanced flight streak", normal.get_node_or_null("TakeAimCore") == null and power.get_node_or_null("TakeAimCore") != null)
	expect("arrows face their flight path immediately and Take Aim keeps double velocity", power.basis.y.dot(power.velocity.normalized()) > 0.99
		and is_equal_approx(normal.velocity.length(), 30.0) and is_equal_approx(power.velocity.length(), 60.0))
	power._stick(null)
	expect("Take Aim's streak stops on impact", not (power.get_node("TakeAimCore") as Node3D).visible)
	normal.queue_free()
	power.queue_free()
	archer._cancel_draw(true)
	archer.model.loop("idle")

## Deterministic Warden state/geometry coverage; no random combat outcomes inferred.
func _warden_fixture() -> Enemy:
	var enemy: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -2.8), "warden")
	enemy.set_physics_process(false)
	enemy.target = player
	enemy.xp_eligible = false
	enemy.aggro_range = 0.0
	return enemy

func _warden_begin(enemy: Enemy) -> WardenBehavior:
	var behavior := enemy.behavior as WardenBehavior
	behavior._special_cool = 0.0
	behavior._cool = 0.0
	behavior.tick(0.01, enemy.flat_distance_to(player))
	return behavior

func _warden_events() -> int:
	var count: int = 0
	for value in Combat.tally.values():
		count += int(value)
	return count

func _test_warden() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	player.set_physics_process(false)
	player.global_position = Vector3(20, 0, 20)
	player.reset_physics_interpolation()
	player.health = player.max_health
	player.invulnerable_time = 0.0
	var definition: EnemyDef = EnemyDb.get_def("warden")
	expect("Warden definition and mapping load", definition.display_name == "Crypt Warden" and EnemyBehaviors.create(definition.behavior) is WardenBehavior)
	expect("Warden is authored-only at every wave", EnemyDb.count_for(definition, 9999) == 0 and not EnemyDb.spawnable(9999).has(definition))
	var brute_def: EnemyDef = EnemyDb.get_def("brute")
	expect("the Warden is a DS2 miniboss, outliving a Brute of its level, without immunity", definition.tier == "miniboss"
		and MonsterScaling.life(5, definition.tier, definition.role) > MonsterScaling.life(5, brute_def.tier, brute_def.role)
		and definition.knock_resist < 1.0 and definition.stun_resist < 1.0)
	var enemy: Enemy = _warden_fixture()
	enemy.global_position = player.global_position + Vector3(0, 0, -8)
	var start: float = enemy.flat_distance_to(player)
	for i in 30:
		enemy.behavior.tick(1.0 / 60.0, enemy.flat_distance_to(player))
		await get_tree().physics_frame
	expect("Warden approaches from outside melee range", enemy.flat_distance_to(player) < start - 0.3 and not enemy.behavior.is_attacking())
	enemy.global_position = player.global_position + Vector3(0, 0, -2.8)
	var behavior: WardenBehavior = _warden_begin(enemy)
	Combat.tally.clear()
	behavior.tick(0.94, 2.8)
	expect("wind-up owns token without damage", behavior._state == WardenBehavior.State.WINDUP and enemy._attacking and Enemy._token_holders.has(enemy.get_instance_id()) and _warden_events() == 0)
	behavior.tick(0.02, 2.8)
	var facing: float = enemy.visual.rotation.y
	expect("wind-up reaches committed strike", behavior._state == WardenBehavior.State.STRIKE)
	player.global_position += Vector3(3, 0, 0)
	behavior.tick(0.30, enemy.flat_distance_to(player))
	expect("sidestep after commitment evades fixed strike", _warden_events() == 0 and is_equal_approx(facing, enemy.visual.rotation.y))
	expect("strike releases token and enters recovery", behavior._state == WardenBehavior.State.RECOVER and not Enemy._token_holders.has(enemy.get_instance_id()))
	behavior.tick(0.9, enemy.flat_distance_to(player))
	player.global_position = enemy.global_position + Vector3(0, 0, 2.8)
	behavior.tick(0.01, 2.8)
	expect("cooldown prevents immediate special repeat", behavior._state == WardenBehavior.State.PRESSURE and behavior._special_cool > 4.0)
	enemy.queue_free()
	await get_tree().physics_frame

	# In-area strike: count actual Combat.resolve events, including any miss.
	enemy = _warden_fixture()
	behavior = _warden_begin(enemy)
	Combat.tally.clear()
	seed(1)
	var health_before: float = player.health
	behavior.tick(1.26, 2.8)
	var health_after: float = player.health
	for i in 10:
		behavior.tick(0.02, 2.8)
	expect("strike resolves exactly once and damages hero", _warden_events() == 1 and health_after < health_before and player.health == health_after)
	expect("recovery prevents another attack", behavior._state == WardenBehavior.State.RECOVER)
	enemy.queue_free()
	await get_tree().physics_frame

	for kind in ["stun", "knockdown", "death"]:
		for committed in [false, true]:
			enemy = _warden_fixture()
			behavior = _warden_begin(enemy)
			if committed:
				behavior.tick(0.97, 2.8)
			Combat.tally.clear()
			if kind == "stun":
				enemy.interrupt(0.8)
				enemy._physics_process(0.01)
			elif kind == "knockdown":
				enemy.ragdoll_launch(Vector3(2, 0, 0), 1.0, Vector3.ZERO)
			else:
				enemy.receive({"outcome": Combat.Outcome.HIT, "damage": 9999.0, "weight": 0.0, "source": null}, player.global_position)
			expect("%s cancels %s attack/token" % [kind, "committed" if committed else "windup"], not enemy._attacking and not behavior.is_attacking() and not Enemy._token_holders.has(enemy.get_instance_id()))
			behavior.tick(2.0, 2.8)
			expect("%s interruption leaves no pending damage" % kind, _warden_events() == 0)
			enemy.queue_free()
			await get_tree().physics_frame
	enemy = _warden_fixture()
	enemy.global_position = player.global_position + Vector3(0, 0, -2)
	behavior = enemy.behavior as WardenBehavior
	behavior._special_cool = 10.0
	behavior.tick(0.01, 2.0)
	expect("Warden applies ordinary close-range melee pressure between specials", behavior._active and behavior._state == WardenBehavior.State.PRESSURE)
	behavior.on_interrupted()
	expect("ordinary Warden pressure also releases its token", not enemy._attacking and not behavior.is_attacking() and not Enemy._token_holders.has(enemy.get_instance_id()))
	enemy.queue_free()
	await get_tree().physics_frame
	var brute: Enemy = _spawn_enemy(player.global_position + Vector3(0, 0, -2), "brute")
	brute.set_physics_process(false)
	brute.target = player
	expect("existing Brute still maps to MeleeBehavior", brute.behavior is MeleeBehavior and not brute.behavior is WardenBehavior)
	brute.behavior.tick(0.01, 2.0)
	expect("existing Brute starts close-range pressure", brute.behavior.is_attacking() and Enemy._token_holders.has(brute.get_instance_id()))
	brute.ragdoll_launch(Vector3.ZERO, 1.0, Vector3.ZERO)
	expect("shared launch hook cancels Brute attack/token", not brute.behavior.is_attacking() and not brute._attacking and not Enemy._token_holders.has(brute.get_instance_id()))
	brute.queue_free()
	player.set_physics_process(true)

## Focused pose evidence, using the exact runtime attack clip/timings.
func _warden_shots() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		node.queue_free()
	await get_tree().physics_frame
	player.global_position = Vector3.ZERO
	player.reset_physics_interpolation()
	player.set_physics_process(false)
	var enemy: Enemy = _warden_fixture()
	var brute: Enemy = _spawn_enemy(Vector3(-3.2, 0, -2.8), "brute")
	brute.set_physics_process(false)
	brute.visual.rotation.y = PI
	var behavior: WardenBehavior = _warden_begin(enemy)
	var folder: String = "res://.dev_output/warden033-png"
	DirAccess.make_dir_recursive_absolute(folder)
	for sample in [["windup", 0.70], ["commit", 0.27], ["strike-evaded", 0.30], ["recovery", 0.50]]:
		if sample[0] == "strike-evaded":
			player.global_position.x = 3.0
			player.reset_physics_interpolation()
		behavior.tick(float(sample[1]), enemy.flat_distance_to(player))
		enemy.reset_physics_interpolation()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = folder + "/" + str(sample[0]) + ".png"
		var error: Error = get_viewport().get_texture().get_image().save_png(path)
		print("WARDEN PNG ", path, " error=", error)
	get_tree().quit()
