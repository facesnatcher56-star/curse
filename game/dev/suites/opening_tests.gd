extends DevSuite
## The Opening passive and Shield Openings (game/player/openings.gd): the rank tables and their description, the weapon-to-execution map, the
## two triggers (a melee hit, a successful shield block), the 1.5 s window and cooldown, the guaranteed-critical execution with its payoff, and
## the shield's guard clip. Values are provisional Curse choices (see data/passives/opening.tres).

const TRIALS := 4000
const TOLERANCE := 0.03

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.ranged_dodge_chance = -1.0
	body.crit_chance = 0.0
	body.invulnerable_time = 0.0
	body.forced_crits = 0

func _near(value: float, expected: float, tolerance: float = TOLERANCE) -> bool:
	return absf(value - expected) <= tolerance

func _test_opening() -> void:
	TownState.persist = false
	TownState.reset()
	var hero := player
	hero.set_physics_process(false)
	var stats: PlayerStats = hero.stats
	var openings: Openings = hero.openings
	var enemy := _spawn_enemy(hero.global_position + Vector3(1.6, 0, 0))
	enemy.set_physics_process(false)
	enemy.alert_delay = 999.0
	enemy.max_health = 50000.0
	enemy.health = 50000.0
	_plain(enemy)
	TownState.dev_set_hero_level(40)
	stats.equipment.clear()
	stats.bag.clear()
	stats.refresh()
	openings.cooldown = 0.0
	openings.clear_mark(false)

	# --- Data: the passive, its rank tables and the tooltip wording ---------------------------------------------------------------------------
	var def := PassiveDb.get_def("opening")
	expect("Opening is a melee passive opening at class level 12 (no prerequisites)", def != null and def.tree == "melee" and def.class_level == 12 and def.prereqs.is_empty())
	expect("rank 20 gives 12%% melee and 30%% shield spot chance, +120%% execution damage, +60%% drops, 25%% charge", def != null
		and _near(def.extra_value("spot", 20), 12.0, 0.01) and _near(def.extra_value("shield", 20), 30.0, 0.01)
		and _near(def.extra_value("damage", 20), 120.0, 0.01) and _near(def.extra_value("drop", 20), 60.0, 0.01)
		and _near(def.extra_value("charge", 20), 25.0, 0.01))
	var detail_20: String = def.describe_detail(20) if def != null else ""
	expect("the tooltip at rank 20 shows the damage, drop and charge values",
		detail_20.contains("+120% damage") and detail_20.contains("+60% item drop chance") and detail_20.contains("restores 25% power charge"))
	expect("the tooltip at rank 1 shows the first values (+20% damage, +10% drop, 5% charge)", def != null
		and def.describe_detail(1).contains("+20% damage") and def.describe_detail(1).contains("+10% item drop chance") and def.describe_detail(1).contains("restores 5% power charge"))
	expect("a DS2 passive has no description block (only Opening does)", PassiveDb.get_def("rebuke") != null and PassiveDb.get_def("rebuke").describe_detail(5) == "")

	# --- Rank 0: nothing happens --------------------------------------------------------------------------------------------------------------
	TownState.passive_ranks.erase("opening")
	stats.refresh()
	expect("without the passive there is no melee or shield spot chance", is_zero_approx(openings.spot_chance()) and is_zero_approx(openings.shield_chance()))
	openings.on_melee_hit(enemy)
	openings.on_block(enemy)
	expect("without the passive a hit or block marks nothing", openings.mark_target == null and openings.marks_made == 0)

	TownState.passive_ranks["opening"] = 20
	stats.refresh()
	expect("rank 20 gives spot chance 12 and shield chance 30", _near(openings.spot_chance(), 12.0, 0.01) and _near(openings.shield_chance(), 30.0, 0.01))

	# --- Weapon -> execution, and the shield overriding it -----------------------------------------------------------------------------------
	var weapons := {"longsword": "stab", "falchion": "stab", "greatsword": "impale", "axe_1h": "chop", "axe_2h": "chop", "mace": "crush",
		"club": "crush", "hammer_2h": "crush", "dagger": "backstab"}
	var mapped := true
	for id in weapons:
		var item := Items.build(ItemDb.get_def(id), 10, Items.Rarity.NORMAL, [])
		stats.equipment.erase(Items.Slot.SHIELD)
		stats.equipment[Items.Slot.WEAPON] = item
		stats.refresh()
		if openings.style_id() != weapons[id]:
			mapped = false
	expect("every melee weapon has its execution (sword stab, axe chop, mace crush, dagger backstab, two-hander impale)", mapped)
	stats.equipment.clear()
	stats.equipment[Items.Slot.WEAPON] = Items.unique(UniqueDb.get_unique("gravecutter"))
	stats.refresh()
	expect("the Gravecutter (unique falchion) has its own execution, the grave cleave, not the falchion's stab",
		openings.style_id() == "grave_cleave" and String(openings.style().get("clip", "")) == "atk_slash_r")
	var longsword := Items.build(ItemDb.get_def("longsword"), 10, Items.Rarity.NORMAL, [])
	stats.equipment.clear()
	stats.equipment[Items.Slot.WEAPON] = longsword
	stats.refresh()
	# A shield needs Barricade 1 (DS2: aegis 1), so the test grants it, as the dodge and block suite does.
	TownState.passive_ranks["barricade"] = 1
	var buckler := Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL, [])
	expect("the buckler equips beside the longsword (Barricade 1 granted)", stats.equip(buckler, false) != null)
	expect("a worn shield gives the bash, over the weapon's own execution", openings.style_id() == "bash" and openings.style().get("clip", "") == "stomp")
	TownState.passive_ranks.erase("barricade")
	stats.equipment.clear()
	stats.refresh()
	expect("unarmed or ranged there is no execution (Openings are a melee passive)", openings.style_id() == "" and openings.style().is_empty())

	# --- The execution is a guaranteed critical with bonus damage, and the window and mark ----------------------------------------------------
	stats.equipment[Items.Slot.WEAPON] = longsword
	stats.refresh()
	enemy.global_position = hero.global_position + Vector3(1.6, 0, 0)
	openings.clear_mark(false)
	openings.cooldown = 0.0
	openings._mark(enemy)
	expect("a mark is made, once, with a 1.5 s window, and a pulsing ring on the enemy", openings.is_open_on(enemy) and openings.marks_made == 1
		and is_instance_valid(openings._ring) and is_equal_approx(openings.mark_left, Openings.WINDOW))
	openings.on_melee_hit(enemy)
	expect("one mark at a time: a melee hit does not replace the open mark", openings.mark_target == enemy and openings.marks_made == 1)
	openings.tick(0.9)
	expect("the mark is still open at 0.9 s", openings.is_open_on(enemy))
	openings.tick(0.7)
	expect("the mark expires after its 1.5 s window and starts the cooldown", openings.mark_target == null and openings.marks_expired == 1 and openings.cooldown > 0.0)
	openings.cooldown = 0.0
	openings._mark(enemy)
	var hp_before: float = enemy.health
	expect("striking the marked enemy takes the attack (the execution starts)", openings.try_execute(enemy))
	expect("the execution uses the weapon's stab, the hero is invulnerable for a moment, and the mark is spent",
		hero.skills.busy and hero.skills.busy_skill == "opening" and hero.invulnerable_time >= Openings.INVULNERABLE - 0.01 and openings.mark_target == null)
	var guard := 0
	while hero.skills.busy and guard < 400:
		hero.skills.tick_busy(0.02)
		guard += 1
	expect("the execution lands as a guaranteed critical that removes life", enemy.health < hp_before and enemy.last_result.get("outcome", -1) == Combat.Outcome.CRITICAL
		and String(enemy.last_result.get("skill_id", "")) == "opening")
	expect("the executed enemy gains the drop multiplier (rank 20: +60%% = x1.60, read %.2f)" % float(enemy.get_meta("opening_drop_mult", 0.0)),
		_near(float(enemy.get_meta("opening_drop_mult", 0.0)), 1.6, 0.001))
	expect("the cooldown starts after an execution", openings.cooldown > 0.0 and openings.executions == 1)
	expect("a mark never executes on a different enemy", not openings.try_execute(_spawn_enemy(hero.global_position + Vector3(9, 0, 9))))

	# --- Payoff: power charge refund --------------------------------------------------------------------------------------------------------
	hero.powers.reload_required["whirling_strike"] = 100.0
	hero.powers.reload_remaining["whirling_strike"] = 100.0
	stats.brutal_reload_required = 80.0
	stats.brutal_reload_remaining = 80.0
	stats.refund_power_charge(0.25)
	expect("an execution refunds 25%% of each charging power's recharge (100 -> 75, 80 -> 60)",
		_near(float(hero.powers.reload_remaining["whirling_strike"]), 75.0, 0.01) and _near(stats.brutal_reload_remaining, 60.0, 0.01))
	hero.powers.reload_remaining.erase("whirling_strike")

	# --- Payoff: a stun for a crushing blow, on the enemies around the target --------------------------------------------------------------------
	var bystander := _spawn_enemy(enemy.global_position + Vector3(1.2, 0, 0))
	bystander.set_physics_process(false)
	bystander.stun_time = 0.0
	openings.on_executed(enemy, {"outcome": Combat.Outcome.CRITICAL}, {"stun": 1.5})
	expect("a crushing execution stuns the enemies within 2.5 m for 1.5 s", bystander.stun_time >= 1.5 - 0.01)

	# --- Gear: +Opening chance adds to both triggers; Openings heal ----------------------------------------------------------------------------
	var charm := Items.build(ItemDb.get_def("longsword"), 10, Items.Rarity.MAGIC, ["opening_1"])
	stats.equipment[Items.Slot.WEAPON] = charm
	stats.refresh()
	expect("a worn +Opening chance adds to the melee and shield chance (12 + 3 = 15, 30 + 3 = 33)",
		_near(openings.spot_chance(), 15.0, 0.01) and _near(openings.shield_chance(), 33.0, 0.01))
	var healer := Items.build(ItemDb.get_def("longsword"), 10, Items.Rarity.MAGIC, ["openings_heal_1"])
	stats.equipment[Items.Slot.WEAPON] = healer
	stats.refresh()
	hero.health = 10.0
	openings.on_executed(enemy, {"outcome": Combat.Outcome.CRITICAL}, {})
	expect("Openings heal gives life back when an execution lands (2%% of maximum life)", hero.health > 10.0 + 0.5 and hero.health <= hero.max_health)
	stats.equipment.clear()
	stats.refresh()

	# --- Shield Openings: only a successful block rolls, and it marks the attacker ----------------------------------------------------------------
	seed(20261014)
	stats.equipment[Items.Slot.SHIELD] = Items.build(ItemDb.get_def("buckler"), 6, Items.Rarity.NORMAL, [])
	stats.refresh()
	var marks := 0
	for i in TRIALS:
		openings.clear_mark(false)
		openings.cooldown = 0.0
		openings.on_block(enemy)
		if openings.mark_target == enemy:
			marks += 1
	expect("a successful block marks the attacker at the shield chance (%d of %d = %.3f, expected 0.30)" % [marks, TRIALS, float(marks) / TRIALS],
		_near(float(marks) / TRIALS, 0.30))
	openings.clear_mark(false)
	openings.cooldown = 0.0
	var hero_marks := 0
	for i in 300:   # the hero is not an enemy: a block from him can never mark anything, whatever the roll
		openings.on_block(hero)
		if openings.mark_target != null:
			hero_marks += 1
			openings.clear_mark(false)
	expect("a block whose attacker is not an enemy marks nothing (%d marks in 300 rolls)" % hero_marks, hero_marks == 0)
	openings.clear_mark(false)
	openings.cooldown = 0.0

	# --- The shield's guard clip is in the live rig -------------------------------------------------------------------------------------------------
	expect("the knight2 rig carries the shield-block clip (game/block)", hero.model != null and hero.model.anim != null and hero.model.anim.has_animation("game/block"))
	hero.invulnerable_time = 0.0
	hero.skills.busy = false
	var life_before: float = hero.health
	hero.receive({"outcome": Combat.Outcome.BLOCK, "damage": 0.0, "weight": 1.0, "source": enemy, "type": Combat.DamageType.PHYSICAL,
		"origin": {}}, enemy.global_position)
	expect("a blocked blow plays the guard clip (the model's current clip is block)", hero.model.current == "block")
	expect("a blocked blow spends no life", is_equal_approx(hero.health, life_before))

	# --- Restore the shared fixtures ------------------------------------------------------------------------------------------------------------
	openings.clear_mark(false)
	openings.cooldown = 0.0
	stats.equipment.clear()
	stats.refresh()
	TownState.passive_ranks.erase("opening")
	stats.refresh()
	stats.bag.clear()
	enemy.queue_free()
	bystander.queue_free()
