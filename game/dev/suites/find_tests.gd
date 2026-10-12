extends DevSuite
const SAMPLE := 100000

func _kill_cases(hero: Player, cutter: Player) -> void:
	var party := PartyManager.current()
	for attack in ["melee", "arrow", "fireball", "burn", "reflect"]:
		var enemy := _spawn_enemy(Vector3(27, 0, 27))
		enemy.set_physics_process(false)
		enemy.health = 1.0
		enemy.armor = 0.0
		enemy.fire_resist = 0.0
		enemy.dodge_chance = 0.0
		enemy.block_chance = 0.0
		enemy.ranged_block_chance = 0.0
		var before: int = game.director.kills
		var expected_bonuses := party.loot_bonuses()
		var observed: Dictionary = {}
		enemy.died.connect(func(_actor: Actor): observed.merge(party.loot_bonuses(), true))
		party.select("hero")
		if attack == "arrow":
			var arrow := CompanionArrow.fire(self, hero, enemy.global_position + Vector3.UP, enemy.global_position, 10.0)
			arrow.set_physics_process(false)
			party.select("cutter")
			arrow._hit_enemy(enemy, enemy.global_position)
			arrow.queue_free()
		elif attack == "fireball":
			var spell := Projectile.new()
			spell.owner_actor = hero
			spell.damage = 10.0
			add_child(spell)
			spell.set_physics_process(false)
			spell.global_position = enemy.global_position
			party.select("cutter")
			spell._hit(enemy, enemy.global_position)
			spell.queue_free()
		elif attack == "burn":
			enemy.apply_burn(10.0, 2.0, true, hero, "fireball", hero.combat_identity())
			party.select("cutter")
			enemy._tick_burn(0.5)
		elif attack == "reflect":
			var original_gear := cutter.stats.gear.duplicate()
			cutter.stats.gear["reflect"] = 100.0
			cutter.invulnerable_time = 0.0
			var incoming := Combat.resolve(enemy, cutter, 10.0, Combat.DamageType.RANGED, false, 0.1, false, false)
			incoming.calm = true
			cutter.receive(incoming, enemy.global_position)
			cutter.stats.gear = original_gear
		else:
			var hit := Combat.resolve(hero, enemy, 10.0, Combat.DamageType.PHYSICAL, false, 0.1, false, false)
			hit.skill_id = "basic"
			hit.calm = true
			party.select("cutter")
			enemy.receive(hit, hero.global_position)
		expect(attack + " real kill uses selection-independent party bonuses", enemy.dead and observed == expected_bonuses and enemy.has_meta("loot_generated"))
		game.director._on_enemy_died(enemy)
		game.director._drop_loot(enemy)
		expect(attack + " duplicate death cannot regenerate rewards", game.director.kills == before + 1)
		enemy.queue_free()
		await get_tree().process_frame

func _category(loot: Dictionary) -> int:
	if loot.gold > 0: return 1
	if loot.health > 0: return 2
	if loot.mana > 0: return 3
	if loot.item.is_empty(): return 0
	return 5 if int(loot.item.rarity) >= Items.Rarity.RARE else 4

func _test_find() -> void:
	TownState.persist = false
	expect("Gold Find scales amount before one rounding", MonsterLoot.gold_amount(10.4, 50.0) == 16 and MonsterLoot.gold_amount(0.2, 70.0) == 1 and MonsterLoot.gold_amount(10.5, 0.0) == 11)
	expect("ordinary modifier thresholds match source including high MF", Items.ordinary_mod_count(0.4, 0) == 1 and Items.ordinary_mod_count(0.401, 0) == 2 and Items.ordinary_mod_count(0.6, 0) == 2 and Items.ordinary_mod_count(0.601, 0) == 0 and Items.ordinary_mod_count(0.9, 100) == 2 and Items.ordinary_mod_count(1.0, 150) == 1)
	var weights := Items.rarity_weights({"item": 0.08, "rare": 0.0075, "unique": 0.0025, "set": 0.0025, "magic1": 0.3}, 100)
	expect("MF scales only explicit rare unique set weights", weights == {"item": 0.08, "rare": 0.015, "unique": 0.005, "set": 0.005, "magic1": 0.3})
	var party := PartyManager.current()
	var hero := party.bodies.hero as Player
	var cutter := party.bodies.cutter as Player
	var active := party.active_id
	var original_hero := hero.stats.gear.duplicate()
	var original_cutter := cutter.stats.gear.duplicate()
	hero.stats.gear = {"magic_find": 20.0, "gold_find": 70.0}
	cutter.stats.gear = {"magic_find": 80.0, "gold_find": 10.0}
	expect("party averages independent bonuses including racial MF", party.loot_bonuses() == {"magic_find": 60.0, "gold_find": 40.0})
	party.select("cutter")
	expect("selection does not change find", party.loot_bonuses() == {"magic_find": 60.0, "gold_find": 40.0} and is_equal_approx(game.director.magic_find(), 60.0))
	cutter.dead = true
	expect("dead members are excluded", party.loot_bonuses() == {"magic_find": 30.0, "gold_find": 70.0})
	cutter.dead = false
	await _kill_cases(hero, cutter)
	var extra: Array[Player] = []
	var fixture_ids: Array[String] = []
	for i in 4:
		var body := Player.new()
		body.member_id = "find_fixture_%d" % i
		add_child(body)
		body.set_physics_process(false)
		body.stats.gear = {"magic_find": 50.0, "gold_find": 40.0}
		extra.append(body)
		fixture_ids.append(body.member_id)
	expect("six deployed common characters average rather than sum", party.living().size() == 6 and party.loot_bonuses() == {"magic_find": 60.0, "gold_find": 40.0})
	for body in extra:
		party.bodies.erase(body.member_id)
		body.queue_free()
	await get_tree().process_frame
	expect("undeployed persistent records do not enter averages", party.loot_bonuses() == {"magic_find": 60.0, "gold_find": 40.0})
	for id in fixture_ids: party.members.erase(id)
	# Actual shared pickup, deferred deletion must not allow a second collector.
	var before_gold := TownState.gold
	var pickup := HealthOrb.new()
	pickup.gold_amount = MonsterLoot.gold_amount(10.4, 50.0)
	add_child(pickup)
	pickup.global_position = hero.global_position + Vector3(0, 0.6, 0)
	hero.stats.collect_orbs()
	hero.stats.collect_orbs()
	expect("gold pickup pays final amount exactly once", TownState.gold == before_gold + 16)
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(TownState.to_dict()))
	expect("shared gold total survives serialization", int(serialized.gold) == TownState.gold)
	TownState.gold = 0
	TownState.from_dict(serialized)
	expect("shared gold reload pays no additional find bonus", TownState.gold == before_gold + 16)
	var saved_member := hero.character.to_dict()
	var lucky_ring := Items.build(ItemDb.get_def("signet"), 20, Items.Rarity.MAGIC, ["magic_find_1", "gold_find_1"])
	hero.stats.equipment = {Items.Slot.RING: lucky_ring}
	hero.stats.refresh()
	var expected_bonuses := party.loot_bonuses()
	var restored := CharacterState.from_dict("hero", JSON.parse_string(JSON.stringify(hero.character.to_dict())))
	party.members.hero = restored
	hero.stats.refresh()
	expect("find equipment JSON reload preserves calculated party bonuses", party.loot_bonuses() == expected_bonuses)
	hero.stats.unequip(Items.Slot.RING)
	expect("unequip immediately removes both find effects", is_zero_approx(hero.stats.gear_stat("magic_find")) and is_zero_approx(hero.stats.gear_stat("gold_find")))
	party.members.hero = CharacterState.from_dict("hero", saved_member)
	hero.stats.refresh()
	expect("container distribution remains the old explicit non-find distribution", Items.container_item_kind(0.499) == "normal" and Items.container_item_kind(0.5) == "magic1" and Items.container_item_kind(0.8) == "magic2")
	hero.stats.gear = original_hero
	cutter.stats.gear = original_cutter
	party.select(active)
	await get_tree().process_frame
	# Every tier/bonus uses real generation, not a substitute probability simulator.
	for tier in ["weak", "normal", "strong"]:
		for mf in [0.0, 100.0]:
			var counts := [0, 0, 0, 0, 0, 0]
			var categories := PackedByteArray()
			var base_gold := 0
			seed(271828)
			for i in SAMPLE:
				var loot := MonsterLoot.roll(30, tier, mf)
				var category := _category(loot)
				categories.append(category)
				counts[category] += 1
				base_gold += int(loot.gold)
			var boosted_gold := 0
			var identical := true
			seed(271828)
			for i in SAMPLE:
				var loot := MonsterLoot.roll(30, tier, mf, 1.0, 70.0)
				identical = identical and _category(loot) == categories[i]
				boosted_gold += int(loot.gold)
			var table: Array = MonsterLoot.TABLES[tier]
			var equipment: Dictionary = Items.DROPS[tier]
			var rare: float = (float(equipment.rare) + float(equipment.unique) + float(equipment.set)) * (1.0 + float(mf) / 100.0)
			var expected := [float(table[0]), float(table[1]) + float(table[2]), float(table[3]), float(table[4]), float(equipment.item), rare]
			var total := 0.0
			for w in expected: total += w
			var distribution_ok := true
			for i in expected.size():
				var probability: float = expected[i] / total
				var tolerance := 6.0 * sqrt(SAMPLE * probability * (1.0 - probability)) + 1.0
				distribution_ok = distribution_ok and absf(counts[i] - SAMPLE * probability) <= tolerance
			expect("%s MF %.0f real rarity distribution" % [tier, mf], distribution_ok)
			expect("%s MF %.0f GF leaves every outcome unchanged" % [tier, mf], identical)
			expect("%s MF %.0f GF scales aggregate gold with only rounding error" % [tier, mf], absf(boosted_gold - base_gold * 1.7) <= counts[1] * 1.35)
			print("FIND_SAMPLE tier=", tier, " MF=", mf, " n=", SAMPLE, " counts=", counts, " gold=", base_gold, " boosted=", boosted_gold)
			await get_tree().process_frame
	for i in 100:
		expect("miniboss always produces exactly one item", not MonsterLoot.roll(30, "miniboss", 100.0).item.is_empty())
		expect("named reward stays one eligible item", not Items.roll_reward(30, Items.REWARD, 100.0).is_empty())
	var slots: Dictionary = {}
	for i in 1000:
		var item := Items.item_of_kind("item", 30, Items.DROPS.normal.window, Vector2i.ZERO, 100.0)
		slots[item.slot] = true
	expect("no supported equipment slot becomes impossible", slots.size() == Items.KINDS.size() - 1)
