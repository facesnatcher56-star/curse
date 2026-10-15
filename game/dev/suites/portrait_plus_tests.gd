extends DevSuite
## Self-test: the skill-point plus on party portraits (#46). It counts through TownState only, shows while a member has unspent points,
## appears on a companion's level-up, clears once the points are spent, and a press on it opens that member's skill tree without the
## press reaching the world. Visible runs (`-- --portraitshot=NAME`) save the HUD under docs/screenshots/portrait-plus.

func _settle() -> void:
	for i in 3: await get_tree().process_frame

func _shot(name: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--portraitshot=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var dir := ProjectSettings.globalize_path("res://docs/screenshots/portrait-plus")
			DirAccess.make_dir_recursive_absolute(dir)
			var path := dir.path_join("%s-%s.png" % [arg.substr(15), name])
			get_viewport().get_texture().get_image().save_png(path)
			print("PORTRAIT_SHOT ", path)

## A press and release on a screen point, routed through the viewport's GUI like a real mouse click.
func _click(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	get_viewport().push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	get_viewport().push_input(release, true)
	await _settle()

## Moves the pointer onto a point (a motion event, so the GUI's hovered control follows it, as with a real mouse).
func _hover(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	get_viewport().push_input(motion, true)
	await _settle()

func _badge_point(card: Control) -> Vector2:
	return card.get_global_rect().position + Ds2PartyCard.BADGE_CENTRE

func _skill_view_for(member: String) -> bool:
	return is_instance_valid(hud.character_panel) and hud.character_panel.get_script() == preload("res://game/ui/skill_tree_view.gd") \
		and hud.character_panel.member_id == member

func _test_portrait_plus() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--portraitui="):   # interface size for the visible check (0.5, 1.0 or 1.5: the supported boundaries)
			GameSettings.ui_size = float(arg.substr(13))
			GameSettings.apply_ui_scale()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--portraitsize="):
			var wh := arg.substr(15).split("x")
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
			DisplayServer.window_set_position(DisplayServer.screen_get_position(DisplayServer.window_get_current_screen()))
			for i in 30: await get_tree().process_frame
	# This suite runs early in the self-test, so it puts back exactly the progression it changes (the hero and Cutter: XP, class XP and
	# passive ranks) rather than resetting the whole game, which the later suites depend on.
	var saved_persist: bool = TownState.persist
	TownState.persist = false
	var hero_member := PartyManager.current().member("hero")
	var cutter_member := PartyManager.current().member("cutter")
	var saved_hero := [hero_member.xp, hero_member.class_xp.duplicate(true), hero_member.passive_ranks.duplicate(true)]
	var saved_cutter := [cutter_member.xp, cutter_member.class_xp.duplicate(true), cutter_member.passive_ranks.duplicate(true)]
	TownState.dev_set_hero_level(1)
	hero_member.passive_ranks = TownState.STARTING_RANKS.duplicate()
	cutter_member.xp = 0
	cutter_member.passive_ranks = {}
	for enemy in get_tree().get_nodes_in_group("enemies"): enemy.queue_free()
	Gamepad.active = false
	await _settle()
	var frame := hud.ds2_party_frame as Ds2PartyFrame
	var hero_card := frame.hero_card as Ds2PartyCard
	var companion := frame.companion_card as Ds2PartyCard
	var cutter := PartyManager.current().bodies.get("cutter") as Player
	expect("the Cutter companion is in the party for this check", cutter != null and companion.visible)

	# Counting: one rule, shared by both cards, and the same number the tree shows.
	expect("a new hero has two points, so the plus shows from the start", TownState.skill_points_left() == 2 and hero_card.skill_points == 2 and hero_card._badge.visible)
	expect("the Cutter card counts through TownState too", companion.skill_points == TownState.skill_points_left({}, "cutter"))

	# Spending clears it: the points go into Fortitude (a melee rank, so the hero needs Melee 1 first).
	TownState.dev_set_hero_level(3)
	frame.update_frame(player)
	await _settle()
	expect("a hero who has earned points shows the plus", hero_card.skill_points > 0 and hero_card._badge.visible)
	var spend := TownState.skill_points_left()
	expect("the points can be spent on Fortitude", TownState.buy_passives({"fortitude": spend}))
	frame.update_frame(player)
	await _settle()
	expect("no points left: the plus is gone", TownState.skill_points_left() == 0 and hero_card.skill_points == 0 and not hero_card._badge.visible)
	await _shot("badge-off")

	# A companion's level-up mid-run brings the plus up for Cutter.
	var member := PartyManager.current().member("cutter")
	var leveled := [0]
	var on_leveled := func(id: String, _old: int, _new: int, _xp: int) -> void:
		if id == "cutter": leveled[0] += 1
	TownState.events.member_leveled.connect(on_leveled)
	var before: int = TownState.skill_points_left({}, "cutter")
	TownState.add_member_xp("cutter", HeroProgression.xp_for_level(member.level + 1) - member.xp, false, {"ranged": 1})
	TownState.events.member_leveled.disconnect(on_leveled)
	frame.update_frame(player)
	await _settle()
	expect("Cutter levelled up mid-run (member_leveled fired once)", leveled[0] == 1 and TownState.skill_points_left({}, "cutter") == before + 1)
	expect("the level-up shows Cutter's plus, counted once", companion.skill_points == before + 1 and companion._badge.visible)

	# Click the Cutter plus: his tree opens, and the press never selects a body or moves the hero into the world.
	hud.close_character()
	await _settle()
	var cutter_at := _badge_point(companion)
	await _hover(cutter_at)
	expect("the plus is the GUI under the mouse (the world ignores that press)", get_viewport().gui_get_hovered_control() == companion)
	await _click(cutter_at)
	expect("clicking the Cutter plus opens Cutter's skill tree", _skill_view_for("cutter") and hud.player == cutter)
	await _shot("cutter-tree")
	hud.close_character()
	await _settle()

	# Click the hero plus: the hero is active again, and the hero's tree opens.
	TownState.dev_set_hero_level(4)
	frame.update_frame(player)
	await _settle()
	expect("the hero's plus is up again after another level", hero_card._badge.visible)
	await _shot("badge-on-both")
	var hero_at := _badge_point(hero_card)
	await _hover(hero_at)
	expect("the hero plus is the GUI under the mouse", get_viewport().gui_get_hovered_control() == hero_card)
	await get_tree().create_timer(1.5).timeout   # the card's tooltip (the points line) shows
	await _shot("hover-badge")
	await _click(hero_at)
	expect("clicking the hero plus opens the hero's skill tree and selects the hero", _skill_view_for("hero") and hud.player.member_id == "hero")
	hud.close_character()
	await _settle()

	# Controller: the plus takes focus, and accept on it opens the same tree a click does.
	companion._badge.grab_focus()
	await _settle()
	expect("the Cutter plus takes keyboard or pad focus", companion._badge.has_focus())
	await _shot("focus-ring")
	var accept: InputEvent = InputMap.action_get_events("ui_accept")[0].duplicate()
	accept.pressed = true
	get_viewport().push_input(accept)
	accept.pressed = false
	get_viewport().push_input(accept)
	await _settle()
	expect("accept on the focused plus opens Cutter's skill tree", _skill_view_for("cutter"))
	hud.close_character()
	await _settle()

	# Fallen: a fallen member's plus still shows and opens their tree (points can be spent), without selecting them or changing control.
	var active_before := PartyManager.current().active_id
	var was_dead: bool = cutter.dead
	cutter.dead = true
	frame.update_frame(player)
	await _settle()
	expect("a fallen member's plus still shows while points are unspent", companion.skill_points > 0 and companion._badge.visible)
	await _click(_badge_point(companion))
	expect("clicking a fallen member's plus opens their tree", _skill_view_for("cutter"))
	expect("and does not select the fallen member (control is unchanged)", PartyManager.current().active_id == active_before)
	hud.close_character()
	await _settle()
	cutter.dead = was_dead
	frame.update_frame(player)
	await _settle()

	# A press on the rest of a card still selects that member as before (the plus takes only its own corner).
	var body_offset := Vector2(170, 60)
	await _click(companion.get_global_rect().position + body_offset)
	expect("a press on the Cutter card body selects Cutter", PartyManager.current().active_id == "cutter")
	await _click(hero_card.get_global_rect().position + body_offset)
	expect("a press on the hero card body selects the hero", PartyManager.current().active_id == "hero")
	await _shot("hover-and-click")
	# Put the progression back as it was, for the suites after this one.
	hero_member.xp = saved_hero[0]
	hero_member.class_xp = saved_hero[1]
	hero_member.passive_ranks = saved_hero[2]
	cutter_member.xp = saved_cutter[0]
	cutter_member.class_xp = saved_cutter[1]
	cutter_member.passive_ranks = saved_cutter[2]
	TownState.persist = saved_persist
	frame.update_frame(player)
