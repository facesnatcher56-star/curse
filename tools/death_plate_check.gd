extends SceneTree
## Developer check of the HUD death plate (task death-recovery-feedback-047): the world (town/road) never offers a restart and says the hero is
## dragged back; the arena asks for the restart control as it is bound now (keyboard rebinding, controller button), and the job case still
## says it returns to town. With --deathshots=DIR it also saves screenshots (needs a real window):
##   GODOT_HEADLESS= tools/run_godot.sh LOG 120 -- --script res://tools/death_plate_check.gd -- --deathshots=DIR
## User arguments make it a developer session: the production save is never touched.

var out_dir: String = ""
var failures: int = 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--deathshots="):
			out_dir = arg.substr(13)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	_run()

func expect(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _shot(shot_name: String) -> void:
	if out_dir == "":
		return
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, shot_name])

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _run() -> void:
	TownState.reset()
	TownState.job = {}   # a plain arena run: no job
	Gamepad.active = false

	# Arena.
	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 4:
		await process_frame
	var hud: Hud = main.hud
	expect("arena HUD is not in world mode", not hud.world_mode)
	hud.player.dead = true
	expect("arena: restart prompt present, default key R", hud.death_subline() == "Press R to restart")
	GameSettings.rebind("restart", _key(KEY_F5))
	expect("arena: rebinding the restart key changes the prompt", hud.death_subline() == "Press F5 to restart")
	Gamepad.active = true
	var pad: String = Gamepad.label_for("restart")
	expect("arena: controller active shows the pad button (%s)" % pad, pad != "" and hud.death_subline() == "Press %s to restart" % pad)
	Gamepad.active = false
	await _shot("arena_death")
	TownState.job = {"name": "x"}
	expect("arena job run keeps its existing 'Returning to town...' line", hud.death_subline() == "Returning to town...")
	TownState.job = {}
	hud.player.dead = false
	GameSettings.reset_bindings()
	main.queue_free()
	await process_frame
	await process_frame

	# World (town + road).
	var town := TownScene.new()
	root.add_child(town)
	for i in 4:
		await process_frame
	var world: Hud = town.combat_hud
	expect("world HUD is in world mode", world.world_mode)
	town.player.dead = true
	for active in [false, true]:
		Gamepad.active = active
		var text: String = world.death_subline()
		expect("world (pad=%s): no restart prompt, drag-back text" % active, text == "Dragged back to town..." and not text.contains("restart"))
	Gamepad.active = false
	town.hud.show_banner("You were dragged back\nTaunt goes here", 4.0)
	await _shot("world_death")
	town.queue_free()
	await process_frame

	print("death plate check: %s" % ("OK" if failures == 0 else "%d failure(s)" % failures))
	quit(1 if failures > 0 else 0)
