extends DevSuite
## Champions (game/enemies/champion.gd): a tougher, named pack member with one affix. The pack roll and its trivial-opener exclusion, each
## affix's behaviour (speed, the shield, the summoner's adds, the exploding blast) and the guaranteed magic-or-better drop.

## A test body in the hero's neighbourhood, kept inert (alert_delay) so the check drives it directly.
func _test_body(offset: Vector3, tier: String = "normal") -> Enemy:
	var e: Enemy = game.director.spawn_enemy(player.global_position + offset, "zombie", WorldThreat.threat_for_level(4), tier)
	e.alert_delay = 999.0
	return e

func _test_champions() -> void:
	var bodies: Array[Enemy] = []

	# The pack roll: a trivial opener never carries one; a chance of 1 gives a normal pack exactly one; a chance of 0 gives none.
	var trivial: Enemy = _test_body(Vector3(12, 0, 0), "trivial")
	var a: Enemy = _test_body(Vector3(13, 0, 0))
	var b: Enemy = _test_body(Vector3(14, 0, 0))
	bodies.append_array([trivial, a, b])
	Champion.chance_override = 1.0
	expect("a trivial opener never carries a champion", Champion.roll_pack([trivial]) == null and trivial.champion == null)
	var chosen: Enemy = Champion.roll_pack([a, b])
	expect("a pack at chance 1 gets exactly one champion, drawn from its members", chosen != null and ((a.champion != null) != (b.champion != null)))
	Champion.chance_override = 0.0
	var plain: Enemy = _test_body(Vector3(15, 0, 0))
	bodies.append(plain)
	expect("a pack at chance 0 gets none", Champion.roll_pack([plain]) == null and plain.champion == null)
	Champion.chance_override = -1.0

	# Every champion is tougher, named for its affix, and its speed follows the affix.
	var base: Enemy = _test_body(Vector3(-12, 0, 0))
	var fast: Enemy = _test_body(Vector3(-13, 0, 0))
	bodies.append_array([base, fast])
	var hp: float = base.max_health
	var speed: float = base.move_speed
	Champion.attach(fast, "fast")
	expect("a champion has its life multiplied and its blows raised", is_equal_approx(fast.max_health, hp * Champion.LIFE_MULT)
		and is_equal_approx(fast.damage_max, base.damage_max * Champion.DAMAGE_MULT) and fast.health == fast.max_health)
	expect("the fast affix quickens it, and it carries its affix name", is_equal_approx(fast.move_speed, speed * float(Champion.AFFIXES.fast.speed))
		and fast.display_name == "Swift " + base.display_name)
	expect("attaching a second champion does nothing", Champion.attach(fast, "shielded") == fast.champion and fast.champion.affix_id == "fast")

	# The shield takes damage before the body does, and breaks once.
	var warded: Enemy = _test_body(Vector3(-14, 0, 0))
	bodies.append(warded)
	var shield: Champion = Champion.attach(warded, "shielded")
	var body_hp: float = warded.health
	var blow: Dictionary = {"outcome": Combat.Outcome.HIT, "damage": 10.0, "weight": 1.0, "source": player, "type": Combat.DamageType.PHYSICAL}
	warded.receive(blow.duplicate(), player.global_position)
	expect("a shield takes a blow and the body is untouched", warded.health == body_hp and shield.shield < shield.shield_max)
	var rest: float = shield.shield
	warded.receive(blow.duplicate().merged({"damage": rest + 30.0}, true), player.global_position)
	expect("the shield breaks and the rest of the blow reaches the body", shield.shield <= 0.0 and is_equal_approx(warded.health, body_hp - 30.0))

	# The summoner calls two adds while it is awake (they pay no XP), no more than its cap, and none while asleep.
	var summoner: Enemy = _test_body(Vector3(-16, 0, 0))
	bodies.append(summoner)
	var summon: Champion = Champion.attach(summoner, "summoner")
	summoner._aggro = false
	summon.summon_cd = 0.0
	summon.tick(summoner, 0.016)
	expect("a sleeping summoner calls nothing", summon.adds.is_empty())
	summoner._aggro = true
	summon.summon_cd = 0.0
	summon.tick(summoner, 0.016)
	expect("an awake summoner calls two adds that pay no XP", summon.adds.size() == 2
		and summon.adds.all(func(add: Enemy) -> bool: return not add.xp_eligible))
	for i in 6:
		summon.summon_cd = 0.0
		summon.tick(summoner, 0.016)
	expect("a summoner's adds stop at its cap", summon.adds.size() == int(Champion.AFFIXES.summoner.summon_max))
	for add in summon.adds:
		bodies.append(add)

	# The exploding champion: its blast hurts the hero inside the radius and leaves one outside it alone.
	var volatile: Enemy = _test_body(Vector3(-18, 0, 0))
	bodies.append(volatile)
	Champion.attach(volatile, "explodes")
	var radius: float = float(Champion.AFFIXES.explodes.blast_radius)
	var before: float = player.health
	Champion._detonate(volatile, player.global_position + Vector3(radius * 0.8, 0, 0), radius, 9.0)
	expect("an exploding champion's blast hurts the hero inside its radius", player.health < before)
	before = player.health
	Champion._detonate(volatile, player.global_position + Vector3(radius * 3.0, 0, 0), radius, 9.0)
	expect("the blast leaves the hero alone outside its radius", is_equal_approx(player.health, before))
	# Its death: the blast waits out the telegraph, then hits whoever is still inside the radius.
	var timed: Enemy = _test_body(Vector3(radius * 0.5, 0, 0))
	bodies.append(timed)
	Champion.attach(timed, "explodes")
	before = player.health
	timed.champion.on_death(timed)
	expect("the telegraph waits: nothing hits the hero straight away", is_equal_approx(player.health, before))
	await game.get_tree().create_timer(float(Champion.AFFIXES.explodes.blast_delay) + 0.3).timeout
	expect("the blast goes off after the telegraph and hits the hero inside its radius", player.health < before)

	# A champion always drops a magic item or better, and rares come up more often than on an ordinary body.
	var all_magic: bool = true
	var rares: int = 0
	for i in 600:
		var item: Dictionary = Champion.loot(5, "normal", 0.0)
		if int(item["rarity"]) < Items.Rarity.MAGIC:
			all_magic = false
		if int(item["rarity"]) == Items.Rarity.RARE:
			rares += 1
	expect("a champion's drop is magic or better every time", all_magic)
	expect("a champion's drop is rare about 30 times in 100", rares >= 120 and rares <= 240)

	for body in bodies:
		if is_instance_valid(body):
			body.queue_free()
	Champion.chance_override = -1.0
