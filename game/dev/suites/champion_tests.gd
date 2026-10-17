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
	var chance_before: float = Champion.chance_override   # restored at the end, whatever the harness had set

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
	Champion.chance_override = chance_before

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
	var first_adds: Array = summon.adds.duplicate()
	for i in 6:
		summon.summon_cd = 0.0
		summon.tick(summoner, 0.016)
	expect("a summoner summons once per fight: no second cast", summon.has_summoned and summon.adds.size() == 2)
	for add in first_adds:
		bodies.append(add)
	for add in first_adds:
		add.xp_eligible = false
		add.health = 0.0
		add._die()
	summon.summon_cd = 0.0
	summon.tick(summoner, 0.016)
	expect("killing its adds does not bring a new cast", summon.adds.is_empty())
	# The fight ends when the hero has gone away long enough; then it may cast once more.
	summon.has_summoned = true
	var party: Array[Player] = PartyManager.current().living()
	var homes: Array[Vector3] = []
	for member in party:
		homes.append(member.global_position)
		member.global_position += Vector3(Enemy.DISENGAGE_RANGE + 60.0, 0, 0)
	summon.tick(summoner, Enemy.DISENGAGE_SECONDS + 0.5)
	for i in party.size():
		party[i].global_position = homes[i]
	expect("losing the hero for good re-arms the summoner", not summon.has_summoned)
	summon.summon_cd = 0.0
	summon.tick(summoner, 0.016)
	expect("a re-armed summoner casts once more", summon.adds.size() == 2)
	var second_adds: Array = summon.adds.duplicate()
	bodies.append_array(second_adds)
	summoner.receive(Combat.resolve(player, summoner, 99999.0, Combat.DamageType.PHYSICAL, false, 1.0, false), player.global_position)
	expect("killing the summoner kills its living adds, which pay nothing",
		summoner.dead and second_adds.all(func(a: Enemy) -> bool: return a.dead and a.get_meta("loot_generated", false) and not a.xp_eligible))

	# No floating title: a champion carries no Label3D, only its glow.
	var plain_champ: Enemy = _test_body(Vector3(-20, 0, 0))
	bodies.append(plain_champ)
	Champion.attach(plain_champ, "summoner")
	expect("a champion has no Label3D title over its head", plain_champ.find_children("*", "Label3D", true, false).is_empty())

	# The target banner: coloured name and an affix tag for a champion; plain for a regular monster.
	var regular: Enemy = _test_body(Vector3(-22, 0, 0))
	bodies.append(regular)
	expect("a champion's banner shows its plain name, affix colour and affix tag",
		Ds2TargetBanner.name_of(plain_champ) == regular.display_name
		and Ds2TargetBanner.status_color(plain_champ) == Champion.AFFIXES.summoner.color
		and Ds2TargetBanner.tag_of(plain_champ) == "SUMMONING CHAMPION")
	expect("a regular monster's banner has no tag and no recolour",
		Ds2TargetBanner.tag_of(regular).is_empty() and Ds2TargetBanner.name_of(regular) == regular.display_name)
	var banner := Ds2TargetBanner.new()
	game.add_child(banner)
	banner.update_target(plain_champ, 0.1)
	expect("the banner node shows the tag and frame for a champion", banner._tag_label.text == "SUMMONING CHAMPION" and banner._elite_frame.visible
		and banner._name_label.get_theme_color("font_color") == Champion.AFFIXES.summoner.color and banner._name_label.text == regular.display_name.to_upper())
	banner.update_target(regular, 0.1)
	expect("the banner node is plain for a regular monster", banner._tag_label.text.is_empty() and not banner._elite_frame.visible)
	banner.queue_free()

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
	Champion.chance_override = chance_before
