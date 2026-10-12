extends DevSuite
## Real receive/resolve tests; --selftest enforces SavePolicy isolation.

func _hit(source: Actor, victim: Actor, amount: float, kind: int = Combat.DamageType.PHYSICAL,
		skill: String = "basic", extra: Dictionary = {}) -> Dictionary:
	var critical := int(extra.get("outcome", -1)) == Combat.Outcome.CRITICAL
	var result := Combat.resolve(source, victim, amount, kind, false, 0.1, critical, critical)
	result["skill_id"] = skill
	result["calm"] = true
	result.merge(extra, true)
	victim.receive(result, source.global_position)
	return result

func _plain(body: Actor) -> void:
	body.level = 1
	body.armor = 0.0
	body.toughness = 0.0
	body.fire_resist = 0.0
	body.block_chance = 0.0
	body.ranged_block_chance = 0.0
	body.dodge_chance = 0.0
	body.crit_chance = 0.0
	body.added_fire = 0.0
	body.invulnerable_time = 0.0
	body.ward_time = 0.0

func _test_equipment_hits() -> void:
	TownState.persist = false
	var hero := player
	var cutter := PartyManager.current().bodies.get("cutter") as Player
	expect("equipment hits has both common-character bodies", cutter != null)
	if cutter == null: return
	var saved_hero := hero.character.to_dict()
	var saved_cutter := cutter.character.to_dict()
	var active := PartyManager.current().active_id
	for body in [hero, cutter]:
		body.set_physics_process(false)
		_plain(body)
	var enemy := _spawn_enemy(Vector3(28, 0, 28))
	enemy.set_physics_process(false)
	_plain(enemy)
	enemy.max_health = 10000.0
	enemy.health = 10000.0
	hero.stats.gear = {"life_steal": 5.0, "mana_steal": 3.0, "life_per_hit": 2.0, "mana_per_hit": 2.0}
	hero.health = 10.0
	hero.stats.mana = 0.0
	_hit(hero, enemy, 10.0)
	expect("successful melee restores all four modifiers", is_equal_approx(hero.health, 12.5) and is_equal_approx(hero.stats.mana, 2.3))
	_hit(hero, enemy, 10.0, Combat.DamageType.PHYSICAL, "basic", {"outcome": Combat.Outcome.CRITICAL})
	expect("critical restores once using its complete damage", is_equal_approx(hero.health, 15.5) and is_equal_approx(hero.stats.mana, 4.9))
	var life := hero.health
	var mana := hero.stats.mana
	for extra in [{"outcome": Combat.Outcome.MISS, "damage": 0.0}, {"outcome": Combat.Outcome.BLOCK, "damage": 0.0},
		{"damage": 0.0}, {"secondary": true}, {"quiet": true}]:
		_hit(hero, enemy, 10.0, Combat.DamageType.PHYSICAL, "basic", extra)
	expect("miss block zero secondary and quiet events restore nothing", is_equal_approx(hero.health, life) and is_equal_approx(hero.stats.mana, mana))
	var projectile := Projectile.new()
	projectile.owner_actor = hero
	projectile.damage = 10.0
	add_child(projectile)
	projectile.set_physics_process(false)
	projectile.global_position = enemy.global_position
	PartyManager.current().select("cutter")
	projectile._hit(enemy, enemy.global_position)
	expect("real Fireball hit after switching restores its original caster", is_equal_approx(hero.health, life + 2.6) and is_equal_approx(hero.stats.mana, mana + 2.36))
	life = hero.health
	mana = hero.stats.mana
	enemy._tick_burn(0.5)
	expect("Fireball burn never repeats restoration", is_equal_approx(hero.health, life) and is_equal_approx(hero.stats.mana, mana))
	projectile.queue_free()
	var arrow := CompanionArrow.fire(self, hero, enemy.global_position + Vector3.UP, enemy.global_position, 10.0)
	arrow.set_physics_process(false)
	arrow._hit_enemy(enemy, enemy.global_position)
	expect("real bow arrow restores shooter, not active member", hero.health > life and hero.stats.mana > mana)
	arrow.queue_free()
	var other := _spawn_enemy(Vector3(26, 0, 28))
	other.set_physics_process(false)
	_plain(other)
	other.health = 1000.0
	other.max_health = 1000.0
	life = hero.health
	mana = hero.stats.mana
	_hit(hero, enemy, 10.0)
	_hit(hero, other, 10.0)
	expect("distinct direct victims each restore exactly once", is_equal_approx(hero.health, life + 5.0) and is_equal_approx(hero.stats.mana, mana + 4.6))
	hero.health = hero.max_health - 0.1
	hero.stats.mana = hero.stats.max_mana - 0.1
	_hit(hero, other, 10.0)
	expect("restoration caps both resources", is_equal_approx(hero.health, hero.max_health) and is_equal_approx(hero.stats.mana, hero.stats.max_mana))
	cutter.stats.gear = {"life_per_hit": 4.0, "mana_per_hit": 1.0}
	cutter.health = 10.0
	cutter.stats.mana = 0.0
	_hit(cutter, enemy, 10.0, Combat.DamageType.RANGED)
	expect("members use independent modifier combinations", is_equal_approx(cutter.health, 14.0) and is_equal_approx(cutter.stats.mana, 1.0))
	hero.stats.gear = {"reflect": 20.0, "life_per_hit": 9.0, "mana_per_hit": 9.0}
	hero.health = 50.0
	hero.stats.mana = 0.0
	hero.ward_time = 10.0
	hero.ward_reduction = 0.5
	var before := enemy.health
	_hit(enemy, hero, 10.0, Combat.DamageType.RANGED)
	expect("ranged reflection uses post-ward damage", is_equal_approx(hero.health, 45.0) and is_equal_approx(before - enemy.health, 1.0))
	expect("reflected damage does not restore resources", is_equal_approx(hero.stats.mana, 0.0) and is_equal_approx(hero.health, 45.0))
	hero.ward_time = 0.0
	before = enemy.health
	_hit(enemy, hero, 1.0)
	expect("tiny reflection has no minimum-one floor", absf(before - enemy.health - 0.2) < 0.001)
	hero.ward_time = 10.0
	hero.ward_reduction = 1.0
	before = enemy.health
	life = hero.health
	_hit(enemy, hero, 10.0)
	expect("fully absorbed hit neither hurts nor reflects", is_equal_approx(hero.health, life) and is_equal_approx(enemy.health, before))
	hero.ward_time = 0.0
	before = enemy.health
	_hit(enemy, hero, 10.0, Combat.DamageType.FIRE, "fireball")
	expect("spells are not reflected", is_equal_approx(enemy.health, before))
	hero.stats.gear = {"reflect": 20.0}
	cutter.stats.gear = {"reflect": 20.0, "life_per_hit": 9.0}
	hero.health = 50.0
	cutter.health = 50.0
	_hit(cutter, hero, 10.0)
	expect("two reflectors terminate after one return without healing", is_equal_approx(hero.health, 40.0) and is_equal_approx(cutter.health, 57.0))
	# Cutter gained its legitimate direct-hit +9, then took 2 reflection. No further proc.
	hero.stats.gear = {"life_steal": 5.0, "mana_steal": 3.0, "life_per_hit": 2.0, "mana_per_hit": 2.0}
	hero.health = 10.0
	hero.stats.mana = 0.0
	enemy.health = 3.0
	_hit(hero, enemy, 100.0)
	expect("killing overkill uses only actual three health removed", is_equal_approx(hero.health, 12.15) and is_equal_approx(hero.stats.mana, 2.09))
	for id in ["gravecutter", "wardens_oath"]:
		var item := Items.unique(UniqueDb.get_unique(id))
		var restored := Items.from_save(Items.to_save(item))
		hero.stats.wear(int(item.slot), restored)
		expect(id + " unique modifier survives reload and updates equipment", is_equal_approx(hero.stats.gear_stat("life_steal" if id == "gravecutter" else "reflect"), 5.0 if id == "gravecutter" else 20.0))
		_plain(hero)
		hero.health = 50.0
		before = other.health
		if id == "gravecutter":
			_hit(hero, other, 10.0)
			expect("Gravecutter actually steals five percent", is_equal_approx(hero.health, 50.5))
		else:
			_hit(other, hero, 10.0)
			expect("The Warden's Oath actually reflects twenty percent", is_equal_approx(before - other.health, 2.0))
	hero.stats.unequip(Items.Slot.SHIELD)
	expect("unequip removes reflect immediately", is_zero_approx(hero.stats.gear_stat("reflect")))
	hero.stats.equipment = {}
	var ring := Items.build(ItemDb.of_slot(Items.Slot.RING)[0], 1, Items.Rarity.MAGIC, ["life_per_hit_1", "mana_per_hit_1"])
	hero.stats.wear(Items.Slot.RING, ring)
	hero.stats.wear(Items.Slot.RING2, Items.from_save(Items.to_save(ring)))
	var flat_life := hero.stats.gear_stat("life_per_hit")
	var flat_mana := hero.stats.gear_stat("mana_per_hit")
	expect("two equipped pieces stack their unchanged affix values", is_equal_approx(flat_life, 2.0 * AffixDb.get_def("life_per_hit_1").value) and is_equal_approx(flat_mana, 4.0))
	var reload := CharacterState.from_dict("hero", JSON.parse_string(JSON.stringify(hero.character.to_dict())))
	PartyManager.current().members["hero"] = reload
	hero.stats.refresh()
	hero.health = 10.0
	hero.stats.mana = 0.0
	_hit(hero, other, 1.0)
	expect("serialized and reloaded equipment produces actual restoration", is_equal_approx(hero.health, 10.0 + flat_life) and is_equal_approx(hero.stats.mana, flat_mana))
	# Exercise normal death/revival without a party wipe or production persistence.
	cutter.stats.gear = {"life_per_hit": 4.0}
	cutter.health = 1.0
	_hit(other, cutter, 100.0)
	expect("member really dies in combat", cutter.dead)
	cutter.revive_at(cutter.global_position)
	cutter.invulnerable_time = 0.0
	cutter.health = 10.0
	_hit(cutter, other, 1.0)
	expect("revived member retains independent restoration", not cutter.dead and is_equal_approx(cutter.health, 14.0))
	for weapon_id in ["longsword", "short_bow"]:
		var def := ItemDb.get_def(weapon_id)
		if def == null:
			# The bow definition is looked up by type, not by presentation identity.
			for candidate in ItemDb.all().values():
				if candidate.item_type == "bow": def = candidate; break
		hero.stats.wear(Items.Slot.WEAPON, Items.build(def, 1, Items.Rarity.NORMAL))
		hero.health = 10.0
		_hit(hero, other, 1.0, Combat.DamageType.RANGED if hero.stats.is_ranged() else Combat.DamageType.PHYSICAL)
		expect("equipped " + weapon_id + " retains jewelry restoration", is_equal_approx(hero.health, 10.0 + flat_life))
	hero.stats.gear = {"reflect": 20.0}
	hero.health = 50.0
	other.health = 1.0
	_hit(other, hero, 10.0)
	expect("reflection killing blow retains character and owner attribution", other.dead and other.member_damage.has("hero") and other.member_owners.get("hero") == hero.character.owner_id and other.last_result.get("skill_id") == "reflect")
	# Restore fixture state without any disk save or permanent purchases.
	PartyManager.current().members["hero"] = CharacterState.from_dict("hero", saved_hero)
	PartyManager.current().members["cutter"] = CharacterState.from_dict("cutter", saved_cutter)
	for body in [hero, cutter]:
		body.stats.refresh()
		body.health = body.max_health
		body.stats.mana = body.stats.max_mana
		body.set_physics_process(true)
	PartyManager.current().select(active)
	enemy.queue_free()
	other.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
