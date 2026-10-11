class_name TownShots
extends Node
## Developer tools for the town and road world, kept out of the game proper: `--townshot` pictures and the `--xpdemo`
## walk-through. TownScene adds one under itself only when --townshot is given; everything here drives the town through `town`.

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
	await hit_dead.call(named)
	step.call("named monster threat 3.4 (level %d), 1 hero kill" % WorldThreat.monster_level(3.4), before)
	before = TownState.hero_xp
	TownState.board[0]["ready"] = true
	town.claim_rewards()
	step.call("standing quest handed in", before)
	await get_tree().create_timer(0.8).timeout

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
		if arg.begins_with("--panel="):   # --panel=marlow | board | stash | character: open that panel first
			var what: String = arg.substr(8)
			match what:
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
