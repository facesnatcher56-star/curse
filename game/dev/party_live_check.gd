extends SceneTree
## Real common bodies, shared combat, switching and menu routing in an isolated arena.
var failures: int = 0

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s: %s" % ["PASS" if passed else "FAIL", label])
	if not passed: failures += 1

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var game := load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await process_frame
	await physics_frame
	await physics_frame
	var party := PartyManager.current()
	var hero := party.bodies.hero as Player
	var cutter := party.bodies.cutter as Player
	check("both bodies use shared character components", hero.stats is PlayerStats and cutter.stats is PlayerStats and cutter.skills is SkillController)
	check("Cutter bow is ordinary equipped gear", cutter.stats.is_ranged() and cutter.bow != null and not cutter.stats.can_use("take_aim"))
	var id_before := cutter.get_instance_id()
	check("switch is immediate without respawn", party.select("cutter") and party.active_body() == cutter and cutter.get_instance_id() == id_before)
	check("camera and HUD follow active member", game.player == cutter and game.rig.target == cutter and game.hud.player == cutter)
	check("switch action is rebindable for keyboard and controller", InputMap.action_get_events("party_switch").size() >= 2)
	TownState.add_member_xp("cutter", 300, false, {"ranged": 1.0})
	check("Cutter purchases use shared rules", TownState.buy_passives({"critical_shot": 1}, "cutter") and PowerDb.hero_rank("take_aim", "cutter") == 1 and PowerDb.hero_rank("take_aim", "hero") == 0)
	var enemy := Enemy.new()
	enemy.target = hero
	game.add_child(enemy)
	enemy.global_position = Vector3(15, 0, 15)
	enemy.max_health = 10000
	enemy.health = 10000
	enemy.dodge_chance = 0.0
	enemy.ranged_block_chance = 0.0
	enemy.set_physics_process(false)
	var arrow := CompanionArrow.fire(game, cutter, cutter.global_position + Vector3.UP, enemy.global_position + Vector3.UP, 20.0)
	arrow.set_physics_process(false)
	party.select("hero")
	arrow._hit_enemy(enemy, cutter.global_position)
	check("arrow released before switch retains Cutter ownership", enemy.member_damage.has("cutter") and float(enemy.member_damage.cutter.get("ranged", 0.0)) > 0.0 and not enemy.member_damage.has("hero"))
	check("delayed arrow retains persistent owner identity", enemy.member_owners.get("cutter") == cutter.character.owner_id and arrow.origin.character_id == "cutter")
	enemy.apply_burn(5.0, 2.0, true, cutter, "fireball")
	party.select("cutter")
	party.select("hero")
	enemy._tick_burn(0.5)
	check("ongoing burn retains character and owner identity", enemy.burn_origin.character_id == "cutter" and enemy.burn_origin.owner_id == cutter.character.owner_id and float(enemy.member_damage.cutter.get("combat", 0.0)) > 0.0)
	check("cannot switch to a member outside own subgroup", party.assign_subgroups({"local": ["hero"], "guest": ["cutter"]}) and not party.select("cutter", "local"))
	party.assign_subgroups({"local": ["hero", "cutter"]})
	cutter.stats.equip(Items.starting_gear()[0], false)
	check("Cutter can wield melee gear", not cutter.stats.is_ranged())
	hero.stats.equip(Items.make(Items.Slot.WEAPON, Items.Rarity.NORMAL, 2, "Short Bow"), false)
	check("Hero can wield bow through same component", hero.stats.is_ranged() and hero.bow != null)
	game.hud.open_skills()
	party.select("cutter")
	check("switch while paused rebuilds menu for correct member", paused and game.hud.character_panel.hero == cutter)
	game.hud.close_character()
	cutter.dead = true
	party.cycle()
	check("fallen member cannot retain active control", party.active_body() == hero)
	cutter.dead = false
	# Reload into newly instantiated common bodies, not just a dictionary round-trip.
	for body in party.bodies.values(): body.set_physics_process(false)
	hero.health = 23.0
	hero.stats.mana = 19.0
	hero.bow.reload_required = 100.0
	hero.bow.reload_remaining = 40.0
	cutter.powers.reload_required = {"detonation": 120.0}
	cutter.powers.reload_remaining = {"detonation": 35.0}
	cutter.skills.hotbar[0] = "fireball"
	party.select("cutter")
	var stored := JSON.parse_string(JSON.stringify(TownState.to_dict())) as Dictionary
	current_scene = null
	game.free()
	TownState.from_dict(TownState.migrate(stored))
	game = load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	for body in party.bodies.values(): body.set_physics_process(false)
	hero = party.bodies.hero as Player
	cutter = party.bodies.cutter as Player
	check("live reload restores active member and personal hotbar", party.active_body() == cutter and cutter.skills.hotbar[0] == "fireball" and hero.skills.hotbar[0] != "fireball")
	check("live reload restores independent vital and recharge states", is_equal_approx(hero.health, 23.0) and is_equal_approx(hero.stats.mana, 19.0) and is_equal_approx(hero.bow.reload_remaining, 40.0) and is_equal_approx(float(cutter.powers.reload_remaining.get("detonation", 0.0)), 35.0))
	print("PARTY LIVE CHECK: %d failure(s)" % failures)
	quit(1 if failures else 0)
