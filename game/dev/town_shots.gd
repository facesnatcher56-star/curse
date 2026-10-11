class_name TownShots
extends Node
## Developer tools for the town and road world, kept out of the game proper: `--townshot` pictures and the `--xpdemo` / `--builddemo=`
## walk-throughs. TownScene adds one under itself only when --townshot is given; everything here drives the town through `town`.

var town: TownScene

## `--xpdemo` (with --townshot): the hero's own blows kill a zombie and a Brute on the road, break a nest, hand in the quest and kill a named
## monster; every step prints the XP total it moved to. Not part of the game.
func _xp_demo() -> void:
	HeroProgression.logging = true
	var z: float = CryptRoad.EXIT_Z - 40.0
	town.player.global_position = town.crypt.at(town.crypt.road_centre_x(z), z)
	await get_tree().create_timer(0.5).timeout
	var hit_dead: Callable = func(e: Enemy) -> void:
		var tries: int = 0
		while is_instance_valid(e) and not e.dead and tries < 40:
			tries += 1
			e.receive(Combat.resolve(town.player, e, 9999.0, Combat.DamageType.PHYSICAL, false, 1.0), town.player.global_position)
		await get_tree().create_timer(0.2).timeout
	var step: Callable = func(label: String, before: int) -> void:
		print("[xpdemo] %-34s %+4d XP  -> total %d  (level %d)" % [label, TownState.hero_xp - before, TownState.hero_xp, TownState.hero_level])
	var before: int = TownState.hero_xp
	var zombie: Enemy = town.director.spawn_enemy(town.player.global_position + Vector3(2, 0, 0), "zombie", town.crypt.threat_at(town.player.global_position))
	await hit_dead.call(zombie)
	step.call("zombie killed by the hero", before)
	before = TownState.hero_xp
	var brute: Enemy = town.director.spawn_enemy(town.player.global_position + Vector3(2, 0, 0), "brute", town.crypt.threat_at(town.player.global_position))
	await hit_dead.call(brute)
	step.call("Brute killed by the hero", before)
	before = TownState.hero_xp
	var stray: Enemy = town.director.spawn_enemy(town.player.global_position + Vector3(2, 0, 0), "zombie", 1.25)
	stray._apply_damage(stray.max_health + 10.0)   # dies of nothing the hero did
	await get_tree().create_timer(0.2).timeout
	step.call("zombie that died on its own", before)
	before = TownState.hero_xp
	town.crypt.nests[0].hit(9999.0, Vector3.FORWARD)
	await get_tree().create_timer(0.2).timeout
	step.call("nest destroyed", before)
	before = TownState.hero_xp
	if is_instance_valid(town.crypt.nests[0]):
		town.crypt.nests[0].hit(9999.0, Vector3.FORWARD)   # a broken nest is gone: nothing more to pay
	step.call("same nest again", before)
	var mon: Dictionary = Monsters.rise()
	mon["kind"] = "ghoul"
	mon["dist"] = 40.0
	mon["level"] = 3.4
	mon["kills"] = 1
	town.populate_monsters()
	var named: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("monster_uid") and int(node.get_meta("monster_uid")) == int(mon["uid"]):
			named = node
	before = TownState.hero_xp
	var expected: int = HeroProgression.kill_xp(2, 3.4) + HeroProgression.named_xp(3.4, 1, false)
	await hit_dead.call(named)
	step.call("named monster lvl 3.4, 1 hero kill (expect %d)" % expected, before)
	before = TownState.hero_xp
	TownState.board[0]["ready"] = true
	town.claim_rewards()
	step.call("standing quest handed in", before)
	await get_tree().create_timer(0.8).timeout

## `--builddemo=wallspike|reaping_recall|ricochet` (with --townshot): the hero is raised to level 12, spends points on a few passives and the
## named Weapon Throw evolution through the real API (a developer session never touches the production save), then throws in the real world:
## a stone wall and a few monsters are put on the road and the throw is run with a picture at each moment worth seeing
## (%TEMP%/curse_build_<name>_N.png). Prints the build state and what happened.
func _build_demo(which: String) -> void:
	TownState.dev_set_hero_level(12)
	for id in ["unbowed", "retaliation", "iron_recovery"]:
		TownState.buy_passive(id)
	if BuildDefs.is_evolution("throw", which):
		TownState.select_evolution("throw", which)
	print("[builddemo] level %d  passive points %d/%d free  evolution points %d/%d free  passives %s  evolutions %s" % [TownState.hero_level,
		TownState.passive_points_available(), HeroProgression.passive_points_for_level(TownState.hero_level), TownState.evolution_points_available(),
		HeroProgression.evolution_points_for_level(TownState.hero_level), str(TownState.purchased_passives), str(TownState.skill_evolutions)])
	var z: float = CryptRoad.EXIT_Z - 30.0
	var origin: Vector3 = town.crypt.at(town.crypt.road_centre_x(z), z)
	town.player.global_position = origin
	for node in get_tree().get_nodes_in_group("enemies"):
		if (node as Node3D).global_position.distance_to(origin) < 45.0:
			node.queue_free()
	await get_tree().create_timer(0.6).timeout
	var shot: Callable = func(label: String) -> void:
		await get_tree().create_timer(0.12).timeout
		var path: String = OS.get_environment("TEMP") + "/curse_build_%s_%s.png" % [which, label]
		get_viewport().get_texture().get_image().save_png(path)
		print("[builddemo] picture ", path)
	var dummy: Callable = func(at: Vector3, kind: String = "zombie") -> Enemy:
		var e: Enemy = town.director.spawn_enemy(at, kind, 1.25)
		e.aggro_range = 0.0
		e.max_health = 4000.0
		e.health = 4000.0
		return e
	var wall_at: Callable = func(centre: Vector3, wall_size: Vector3) -> StaticBody3D:
		var wall := StaticBody3D.new()
		wall.collision_layer = Actor.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_size
		shape.shape = box
		wall.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = wall_size
		mesh.mesh = cube
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.27, 0.25, 0.23)
		stone.roughness = 0.95
		mesh.material_override = stone
		wall.add_child(mesh)
		town.add_child(wall)
		wall.global_position = centre
		return wall
	var wt: WeaponThrowSkill = town.player.weapon_throw
	var throw_now: Callable = func(aim: Vector3, hold: float) -> void:
		wt._profile = wt.profile()
		wt.evolution = town.player.evolution_of("throw")
		wt.state = WeaponThrowSkill.State.CHARGING
		wt._hold = hold
		wt.charge = wt.charge_fraction()
		wt.release(aim)
	town.player.stats.cooldowns.clear()
	var east: Vector3 = Vector3(1, 0, 0)
	town.player.visual.rotation.y = atan2(east.x, east.z)
	match which:
		"iron":   # Iron Recovery: a heavy blow knocks him down; when he is back on his feet he shoves the lesser enemies round him back
			var ring: Array[Enemy] = []
			for angle in [0.0, 2.1, 4.2]:
				ring.append(dummy.call(origin + Vector3(cos(angle), 0, sin(angle)) * 2.0))
			var heavy_brute: Enemy = dummy.call(origin + Vector3(cos(1.05), 0, sin(1.05)) * 2.3, "brute")
			await get_tree().create_timer(0.4).timeout
			await shot.call("0_surrounded")
			var attacker: Enemy = dummy.call(origin + Vector3(0, 0, 4.0), "brute")
			var blow: Dictionary = Combat.resolve(attacker, town.player, 20.0, Combat.DamageType.PHYSICAL, false, 2.7)
			blow["outcome"] = Combat.Outcome.CRUSHING
			blow["damage"] = 20.0
			blow["weight"] = 2.7
			town.player.receive(blow, attacker.global_position)
			town.player.knock = Vector3.ZERO
			var near: PackedStringArray = []
			for e in ring:
				near.append("%.1f m" % e.flat_distance_to(town.player))
			print("[builddemo] heavy blow taken: stun ", snappedf(town.player.stun_time, 0.01), " s; ring distances ", ", ".join(near), "; brute ", snappedf(heavy_brute.flat_distance_to(town.player), 0.1), " m")
			await get_tree().create_timer(0.2).timeout
			await shot.call("1_knockdown_impact")
			await get_tree().create_timer(0.4).timeout
			await shot.call("2_downed")
			await get_tree().create_timer(0.45).timeout
			await shot.call("3_getting_up")
			await get_tree().create_timer(0.5).timeout
			await shot.call("4_shoved")
			var far: PackedStringArray = []
			for e in ring:
				far.append("%.1f m" % e.flat_distance_to(town.player))
			print("[builddemo] after he shook it off (shoves ", town.player.iron_shoves, "): ring distances ", ", ".join(far), "; brute ", snappedf(heavy_brute.flat_distance_to(town.player), 0.1), " m")
		"wallspike":
			wall_at.call(origin + Vector3(14.0, 2.0, 0.0), Vector3(1.0, 4.0, 7.0))
			var victim: Enemy = dummy.call(origin + Vector3(6.0, 0, 0))
			dummy.call(origin + Vector3(8.5, 0, 0.4))
			await shot.call("0_before")
			throw_now.call(origin + east * 40.0, 10.0)
			await _wait_throw(wt, WeaponThrowSkill.State.EMBEDDED, 4.0)
			await shot.call("1_pinned")
			print("[builddemo] pinned=", wt.pinned == victim, " impaled=", victim.impaled, " victim x offset from hero=", snappedf(victim.global_position.x - origin.x, 0.1))
			await get_tree().create_timer(1.0).timeout
			wt.recall()
			await get_tree().create_timer(0.35).timeout
			await shot.call("2_released")
			print("[builddemo] after recall pinned=", wt.pinned == null, " victim released=", not victim.impaled, " ragdolled=", victim.is_ragdolled())
		"ricochet":
			wall_at.call(origin + Vector3(11.5, 2.0, 0.0), Vector3(1.0, 4.0, 22.0))
			var aim: Vector3 = Vector3(1.0, 0.0, 0.5).normalized()
			var hit: Vector3 = origin + aim * (11.0 / aim.x)
			var bounce_out: Vector3 = aim.bounce(Vector3(-1, 0, 0)).normalized()
			dummy.call(hit + bounce_out * 3.5)
			dummy.call(hit + bounce_out * 5.0 + Vector3(0, 0, 1.0))
			await get_tree().physics_frame   # the new wall must be in the physics space before the lane looks for it
			await get_tree().physics_frame
			wt._profile = wt.profile()
			wt.evolution = "ricochet"
			wt.state = WeaponThrowSkill.State.CHARGING
			wt._hold = 10.0
			wt.charge = 1.0
			wt.update_preview(origin + aim * 20.0)
			await shot.call("0_preview")
			print("[builddemo] preview bounce length ", snappedf(wt.preview.bounce_length, 0.1), " dir ", wt.preview.bounce_dir)
			wt.cancel_charge()
			throw_now.call(origin + aim * 40.0, 10.0)
			var frames: int = 0
			while wt.bounces == 0 and frames < 300:
				await get_tree().physics_frame
				frames += 1
			await shot.call("1_bounce")
			await _wait_throw(wt, WeaponThrowSkill.State.EMBEDDED, 4.0)
			await shot.call("2_embedded")
			print("[builddemo] bounces=", wt.bounces, " struck after the bounce=", wt.last_out_hits.size())
		_:
			var targets: Array[Enemy] = []
			throw_now.call(origin + east * 40.0, 10.0)
			await _wait_throw(wt, WeaponThrowSkill.State.EMBEDDED, 4.0)
			var rest: Vector3 = wt.thrown.center()
			var back_spot: Vector3 = Vector3(rest.x - 14.0, 0.0, rest.z + 7.0)
			town.player.global_position = back_spot
			for f in [0.35, 0.6]:
				targets.append(dummy.call(Vector3(rest.x, 0.0, rest.z).lerp(back_spot, f)))
			await get_tree().create_timer(0.3).timeout
			await shot.call("0_set")
			wt.recall()
			await get_tree().create_timer(1.2).timeout
			await shot.call("1_dragging")
			await get_tree().create_timer(1.4).timeout
			await shot.call("2_gathered")
			var gathered: PackedStringArray = []
			for e in targets:
				gathered.append("%.1f m" % e.flat_distance_to(town.player))
			print("[builddemo] pulled ", wt.pulled_ids.size(), " enemies; distances to hero now ", ", ".join(gathered))
	await get_tree().create_timer(0.5).timeout

func _wait_throw(wt: WeaponThrowSkill, state: int, seconds: float) -> void:
	var waited: float = 0.0
	while int(wt.state) != state and waited < seconds:
		await get_tree().physics_frame
		waited += 1.0 / 60.0

func run(args: PackedStringArray) -> void:
	TownState.persist = false   # a developer screenshot never writes the player's save
	await get_tree().create_timer(3.0).timeout
	for arg in args:
		if arg == "--seen":   # developer tool: orientation already seen, demonstrate concise welcome
			TownState.orientation_seen = true
			town.hud.log_lines.clear()
			town._welcome_back()
		if arg == "--ready":   # developer tool: pretend the quest is done, to see Hale's coin and the HUD
			TownState.board[0]["ready"] = true
			TownState.job = (TownState.board[0] as Dictionary).duplicate(true)
			town._refresh_reward_marker()
		if arg == "--quests":   # developer tool: put some quests and matters up, to see the tracker and the panels
			TownState.jobs_done = 2
			for id in ["ghoul_cull", "brute_bounty", "lost_satchel", "fever", "light_fingers", "blood_moon"]:
				Quests.post(id)
			town.populate_quests()
			town._refresh_reward_marker()
			town._flush_quest_news()
		if arg == "--monsters":   # developer tool: two named monsters (one a nemesis) with plots under way, and the hero near the first
			TownState.jobs_done = 2
			for i in 2:
				var made: Dictionary = Monsters.rise()
				made["dist"] = 60.0 + 12.0 * i
				made["level"] = 3.4 + i
			var first: Dictionary = TownState.monsters[0]
			first["nemesis"] = true
			first["kills"] = 2
			first["plot"] = {"type": "altar", "days_left": 2, "total": 4}
			TownState.monsters[1]["plot"] = {"type": "raid", "days_left": 1, "total": 3}
			Quests.tell("The Hollow has been seen near the wood.", "monster")
			Quests.tell("Fog Bank: a fog bank has rolled in.", "event")
			town.populate_monsters()
			town.player.global_position = town.crypt.monster_spot(first) + Vector3(0, 0, 14)
			await get_tree().create_timer(1.5).timeout
		if arg.begins_with("--zoom="):   # --zoom=n: pull the camera back (the plaza opens at 2.6)
			town.rig.set_zoom_now(float(arg.substr(7)))
		if arg.begins_with("--at="):   # --at=x,z: move the hero first
			var parts: PackedStringArray = arg.substr(5).split(",")
			town.player.global_position = Vector3(float(parts[0]), 0, float(parts[1]))
			town.player.reset_physics_interpolation()
			town.rig.global_position = town.player.global_position
			await get_tree().create_timer(1.0).timeout
		if arg.begins_with("--road="):   # --road=D: stand D metres out from the town gate, on the Crypt Road
			var z: float = CryptRoad.EXIT_Z - float(arg.substr(7))
			town.player.global_position = town.crypt.at(town.crypt.road_centre_x(z), z)
			await get_tree().create_timer(1.0).timeout
		if arg.begins_with("--abilitytoast="):   # developer tool: show the "New ability learned" plate for a skill id
			town.combat_hud.show_ability_toast(arg.substr(15))
			await get_tree().create_timer(0.8).timeout
		if arg == "--xpdemo":   # developer tool: earn XP the real way (hits, a nest, a hand-in, a named monster) and print each change
			await _xp_demo()
		if arg.begins_with("--builddemo="):   # developer tool: buy a Weapon Throw evolution and use it on the road, with pictures
			await _build_demo(arg.substr(12))
		if arg.begins_with("--panel="):   # --panel=marlow | board | stash | character | progression | evolutions | evolution-confirm: open that panel first
			var what: String = arg.substr(8)
			match what:
				"progression", "evolutions", "evolution-confirm":
					TownState.dev_set_hero_level(maxi(TownState.hero_level, 12))
					TownState.buy_passive("unbowed")
					town.combat_hud.show_gear = true
					town.combat_hud._open_character()
					town.combat_hud.open_progression()
					if what != "progression":
						town.combat_hud.progression_panel.show_section("evolutions")
					if what == "evolution-confirm":
						town.combat_hud.progression_panel._request_evolution("throw", "wallspike")
				"character":
					town.combat_hud.show_gear = true
					town.combat_hud._open_character()
				"chronicle":
					town.panel.open_chronicle()
				"board":
					town.panel.open_board()
				"stash":
					town.panel.open_stash()
				_:
					town.panel.open_npc(what)
			await get_tree().create_timer(0.8).timeout
	for arg in args:
		if arg.begins_with("--hover="):
			var spot: Dictionary = town._spot(arg.substr(8))
			if not spot.is_empty():
				get_viewport().warp_mouse(get_viewport().get_camera_3d().unproject_position(spot["pos"] + Vector3(0, 1.1, 0)))
				await get_tree().create_timer(0.7).timeout
	if args.has("--xpreport") and town.director != null:   # developer tool: what this road would pay if it were all cleared
		var report: Dictionary = town.director.xp_report()
		print("[xpreport] %d ordinary monsters %s = %d XP; %d nests = %d XP; standing quest = %d XP; TOTAL %d XP (a fresh hero needs %d for level 2, %d for level 5)"
			% [report["kills"], str(report["by_kind"]), report["kill_xp"], report["nests"], report["nest_xp"], report["quest_xp"], report["total"],
			HeroProgression.xp_for_level(2), HeroProgression.xp_for_level(5)])
		print("[xpreport] plus %d named monsters worth %d XP in bounties if killed" % [report["named"], report["named_xp"]])
	if args.has("--threats"):   # developer tool: how strong are the monsters round the hero (hero level, then kind / threat / health / damage)
		print("[threats] hero level %d" % TownState.hero_level)
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and not e.dead and e.global_position.distance_to(town.player.global_position) < 30.0:
				print("[threats]   %-8s %-22s threat %.2f  health %5.1f  damage %4.1f-%4.1f  %s" % [e.variant, e.display_name, e.level_scale, e.max_health,
					e.damage_min, e.damage_max, "NAMED" if e.has_meta("monster_uid") else ""])
	if args.has("--timing"):
		print("[world] %.0f fps with %d monsters, %d people" % [Performance.get_monitor(Performance.TIME_FPS), get_tree().get_nodes_in_group("enemies").size(), town.npcs.size()])
	for arg in args:
		if arg.begins_with("--res="):
			var res_parts := arg.substr(6).split("x")
			if res_parts.size() == 2:
				var w := int(res_parts[0])
				var h := int(res_parts[1])
				DisplayServer.window_set_size(Vector2i(w, h))
				get_viewport().size = Vector2i(w, h)
				await get_tree().create_timer(0.5).timeout
	var out_path: String = OS.get_environment("TEMP") + "/curse_town.png"
	for arg in args:
		if arg.begins_with("--out="):
			out_path = arg.substr(6)
	var tex := get_viewport().get_texture()
	var img := tex.get_image() if tex != null else null
	if img != null:
		var err: Error = img.save_png(out_path)
		if err == OK:
			print("[screenshot] saved to ", out_path)
	else:
		print("[screenshot] skipped (headless/null viewport image)")
	get_tree().quit()
