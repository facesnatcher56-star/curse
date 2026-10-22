extends SceneTree
## Focused checks for the modular equipment visuals (game/modular_appearance.gd). Not part of --selftest.
##   headless:  godot --headless --path . --script game/dev/modular_check.gd -- --modular
##   windowed:  godot --path . --script game/dev/modular_check.gd -- --modular --shots=<abs dir>
## The windowed run saves Godot renders of the real gameplay camera (labelled GAMEPLAY_*) and close inspection
## renders (labelled CLOSE_*). Images need personal review; this script asserts only structure and state.

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1

func item(slot: int, base: String) -> Dictionary:
	return Items.make(slot, Items.Rarity.NORMAL, 2, base)

func pieces(hero: Player) -> Array:
	return hero.appearance.worn

func attached(hero: Player) -> Array:
	var names: Array = []
	for node in hero.appearance.skeleton.get_children():
		if node is MeshInstance3D and (node as MeshInstance3D).visible and not node.is_queued_for_deletion():   # the rig's own body pieces hide rather than detach
			names.append(String(node.name))
	names.sort()
	return names

func wear_set(hero: Player, set: Dictionary) -> void:
	for place in [Items.Slot.ARMOR, Items.Slot.HELM, Items.Slot.GLOVES, Items.Slot.BOOTS, Items.Slot.SHIELD]:
		hero.stats.unequip(place)
	for place in set:
		hero.stats.wear(place, set[place])

func run() -> void:
	TownState.persist = false
	TownState.reset()
	var game := load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(game)
	current_scene = game
	await create_timer(1.0).timeout
	for enemy in get_nodes_in_group("enemies"):
		enemy.set_physics_process(false)
	var hero: Player = PartyManager.current().bodies["hero"]
	if "--classic" in OS.get_cmdline_user_args():
		# classic opt-out: the classic presentation must be exactly the old one
		check("classic: no modular appearance on the hero", hero.appearance == null and not ModularAppearance.enabled_for("hero"))
		check("classic: the rig's own body shows", not hero.model.find_children("body_skin", "MeshInstance3D", true, false).is_empty())
		check("classic: the hands are the rig's own (no gauntlet fists on the barbarian)", hero.model._mounts.is_empty())
		hero.stats.wear(Items.Slot.ARMOR, item(Items.Slot.ARMOR, "Plate Cuirass"))
		check("classic: equipping armour adds no pieces and does not error", hero.appearance == null)
		check("classic: cutter unchanged", PartyManager.current().bodies["cutter"].appearance == null)
		print("MODULAR CHECK ", "OK (classic path)" if failures == 0 else "FAILED (%d)" % failures)
		quit(1 if failures > 0 else 0)
		return
	check("hero uses the modular appearance", hero.appearance != null)
	if hero.appearance == null:
		quit(1)
		return
	var shots := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.substr(8)

	# --- the barbarian hero shows no item models until his are built (owner, 2026-10-22): every outfit shows only his own
	# body, hair, beard and briefs, and equipping still changes nothing but stats
	var base := ["body_beard", "body_hair", "body_skin", "clt_briefs"]
	check("starting gear shows only his own body", pieces(hero) == base)
	check("only the pieces in the table are attached", attached(hero) == pieces(hero))
	check("source knight mesh is gone", hero.model.find_children("char1", "MeshInstance3D", true, false).is_empty())
	# his starting Longsword has a model built for him (equipment_visuals.json item_models): it shows, in his right hand
	check("his Longsword shows, built for him", hero.model.weapon != null and (hero.model.weapon.get_child(0) as Node3D).visible
		and hero._held_path == "res://assets/models/barbarian/items/longsword.glb" and hero.model.weapon_tip != null)
	# a weapon with no model built for him keeps its nodes but draws nothing
	hero.stats.wear(Items.Slot.WEAPON, item(Items.Slot.WEAPON, "Falchion"))
	check("a weapon not built for him draws nothing", hero.model.weapon != null
		and not (hero.model.weapon.get_child(0) as Node3D).visible and hero.model.weapon_tip != null)
	hero.stats.wear(Items.Slot.WEAPON, item(Items.Slot.WEAPON, "Longsword"))
	check("back to the Longsword, it shows again", (hero.model.weapon.get_child(0) as Node3D).visible)

	# --- equip / unequip
	hero.stats.wear(Items.Slot.ARMOR, item(Items.Slot.ARMOR, "Plate Cuirass"))
	check("equip plate cuirass adds no pieces", pieces(hero) == base)
	hero.stats.wear(Items.Slot.HELM, item(Items.Slot.HELM, "Iron Helm"))
	hero.stats.wear(Items.Slot.GLOVES, item(Items.Slot.GLOVES, "Iron Gauntlets"))
	hero.stats.wear(Items.Slot.BOOTS, item(Items.Slot.BOOTS, "Iron Greaves"))
	hero.stats.wear(Items.Slot.SHIELD, item(Items.Slot.SHIELD, "Kite Shield"))
	check("full plate set adds no pieces and keeps his hair", pieces(hero) == base and attached(hero) == base)
	hero.stats.unequip(Items.Slot.HELM)
	hero.stats.unequip(Items.Slot.ARMOR)
	check("unequipping leaves his own body", pieces(hero) == base and attached(hero) == base)

	# --- mixed combinations
	wear_set(hero, {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Apprentice Robe"), Items.Slot.HELM: item(Items.Slot.HELM, "Woven Hood"),
		Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Sorcerer Boots")})
	check("mage set adds no pieces", pieces(hero) == base and attached(hero) == base)
	wear_set(hero, {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Leather Jerkin"), Items.Slot.HELM: item(Items.Slot.HELM, "Iron Helm"),
		Items.Slot.GLOVES: item(Items.Slot.GLOVES, "Iron Gauntlets"), Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Leather Boots")})
	check("mixed set adds no pieces", pieces(hero) == base and attached(hero) == base)

	# --- skinning bound to the real skeleton
	var ok_bind := true
	for node in hero.appearance.skeleton.get_children():
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			ok_bind = ok_bind and mi.skin != null and mi.skin.get_bind_count() > 0 and mi.get_node(mi.skeleton) == hero.appearance.skeleton
			for i in mi.skin.get_bind_count():
				ok_bind = ok_bind and hero.appearance.skeleton.find_bone(mi.skin.get_bind_name(i)) >= 0
	check("every piece is skinned to named bones of the character skeleton", ok_bind)

	# --- save and restore: serialise like a save file, wipe the look, load, and the look comes back from item state alone
	wear_set(hero, {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Apprentice Robe"), Items.Slot.HELM: item(Items.Slot.HELM, "Woven Hood"),
		Items.Slot.GLOVES: item(Items.Slot.GLOVES, "Leather Gloves"), Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Leather Boots")})
	var before: Array = pieces(hero).duplicate()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PartyManager.current().to_dict()))
	wear_set(hero, {})
	check("wiped look is base only", pieces(hero) == base)
	PartyManager.current().load_data(saved)
	hero.refresh_appearance()
	check("save/load restores the same worn pieces", pieces(hero) == before and attached(hero) == before)
	check("restored state alone predicts the pieces", ModularAppearance.pieces_for(PartyManager.current().member("hero").equipment) == before)

	# --- animation compatibility: hit, death and locomotion clips exist and play on the modular rig
	for clip in ["idle_alert", "walk", "run", "hit", "death", "atk_slash", "slash", "thrust"]:
		check("clip %s available on the modular rig" % clip, hero.model.anim.has_animation("game/" + clip))
	hero.set_physics_process(false)
	hero.model.once("hit")
	await create_timer(0.3).timeout
	check("hit clip plays on the modular rig", hero.model.anim.current_animation == "game/hit" and hero.model.anim.is_playing())
	hero.model.once("death")
	await create_timer(0.3).timeout
	check("death clip plays on the modular rig", hero.model.anim.current_animation == "game/death" and hero.model.anim.is_playing())

	# --- controlled-character switching: the other member keeps the default presentation, the hero keeps its pieces
	var party := PartyManager.current()
	var keep: Array = pieces(hero).duplicate()
	check("switch control to cutter", party.select("cutter"))
	check("cutter keeps the default presentation", party.bodies["cutter"].appearance == null)
	check("switch control back to hero", party.select("hero"))
	check("hero pieces unchanged after switching", pieces(hero) == keep and attached(hero) == keep)

	if shots != "":
		await take_shots(game, hero, shots)
	await reload_check(game, hero)
	print("MODULAR CHECK ", "OK" if failures == 0 else "FAILED (%d)" % failures)
	quit(1 if failures > 0 else 0)

func settle() -> void:
	await create_timer(0.35, true).timeout
	await RenderingServer.frame_post_draw

func save(tag: String, dir: String) -> void:
	await settle()
	var path := dir.path_join(tag + ".png")
	root.get_texture().get_image().save_png(path)
	print("SHOT ", path)

func take_shots(game: Node3D, hero: Player, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	root.size = Vector2i(1280, 720)
	root.position = DisplayServer.screen_get_position(0) + Vector2i(40, 40)
	hero.set_physics_process(false)
	var loadouts := {
		"plate": {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Plate Cuirass"), Items.Slot.HELM: item(Items.Slot.HELM, "Iron Helm"),
			Items.Slot.GLOVES: item(Items.Slot.GLOVES, "Iron Gauntlets"), Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Iron Greaves"),
			Items.Slot.SHIELD: item(Items.Slot.SHIELD, "Kite Shield")},
		"leather": {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Leather Jerkin"), Items.Slot.HELM: item(Items.Slot.HELM, "Leather Cap"),
			Items.Slot.GLOVES: item(Items.Slot.GLOVES, "Leather Gloves"), Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Leather Boots")},
		"mage": {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Apprentice Robe"), Items.Slot.HELM: item(Items.Slot.HELM, "Woven Hood"),
			Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Sorcerer Boots")},
		"mixed": {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Plate Cuirass"), Items.Slot.HELM: item(Items.Slot.HELM, "Woven Hood"),
			Items.Slot.GLOVES: item(Items.Slot.GLOVES, "Leather Gloves"), Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Leather Boots")},
	}
	var cam: Camera3D = get_nodes_in_group("camera").front() if not get_nodes_in_group("camera").is_empty() else null
	for tag in loadouts:
		wear_set(hero, loadouts[tag])
		hero.model.loop("idle_alert")
		await save("GAMEPLAY_%s_idle" % tag, dir)
	# close inspection renders with a dedicated camera in the same world (not the gameplay camera)
	var close := Camera3D.new()
	game.add_child(close)
	close.fov = 32.0
	close.make_current()
	var around := hero.global_position + Vector3(0, 1.0, 0)
	for tag in loadouts:
		wear_set(hero, loadouts[tag])
		for view in [["front", Vector3(0, 0.6, 4.6)], ["back", Vector3(0, 0.6, -4.6)], ["side", Vector3(4.6, 0.6, 0)]]:
			close.global_position = around + view[1]
			close.look_at(around)
			hero.model.loop("idle_alert")
			await save("CLOSE_%s_%s" % [tag, view[0]], dir)
		for clip in ["run", "hit", "death", "atk_slash"]:
			close.global_position = around + Vector3(2.6, 1.2, 4.0)
			close.look_at(around)
			hero.model.once(clip, 0.0, 1.0, 0.0)
			hero.model.anim.seek(0.35 if clip != "death" else 2.6, true)
			hero.model.anim.pause()
			await save("CLOSE_%s_%s" % [tag, clip], dir)
			hero.model.anim.play("game/idle_alert")
	# archer: bow equipped
	hero.stats.wear(Items.Slot.WEAPON, item(Items.Slot.WEAPON, "Short Bow"))
	wear_set(hero, {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Leather Jerkin"), Items.Slot.HELM: item(Items.Slot.HELM, "Woven Hood"),
		Items.Slot.GLOVES: item(Items.Slot.GLOVES, "Leather Gloves"), Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Leather Boots")})
	check("archer bow model is the kit bow", hero.appearance.bow_model.ends_with("wpn_bow.glb"))
	for view in [["front", Vector3(0, 0.6, 4.6)], ["side", Vector3(4.6, 0.6, 0)]]:
		close.global_position = around + view[1]
		close.look_at(around)
		hero.model.loop("idle_alert")
		await save("CLOSE_archer_%s" % view[0], dir)
	for clip in ["walk", "run"]:
		close.global_position = around + Vector3(2.6, 1.2, 4.0)
		close.look_at(around)
		hero.model.loop(clip)
		await save("CLOSE_archer_%s" % clip, dir)

## A new game scene built from a serialised save restores the worn pieces (Player._ready path, not just refresh).
func reload_check(game: Node3D, hero: Player) -> void:
	wear_set(hero, {Items.Slot.ARMOR: item(Items.Slot.ARMOR, "Apprentice Robe"), Items.Slot.HELM: item(Items.Slot.HELM, "Woven Hood"),
		Items.Slot.BOOTS: item(Items.Slot.BOOTS, "Sorcerer Boots")})
	var want: Array = pieces(hero).duplicate()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(PartyManager.current().to_dict()))
	game.queue_free()
	await process_frame
	await process_frame
	PartyManager.current().reset(true)
	PartyManager.current().load_data(saved)
	var fresh := load("res://game/main.tscn").instantiate() as Node3D
	root.add_child(fresh)
	current_scene = fresh
	await create_timer(1.0).timeout
	var again: Player = PartyManager.current().bodies["hero"]
	print("RELOAD worn=", pieces(again), " wanted=", want)
	check("reloaded game rebuilds the same worn pieces from the save", again.appearance != null and pieces(again) == want and attached(again) == want)
