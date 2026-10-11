extends SceneTree
## Developer check of ground-loot rarity cues (task rare-ground-drop-visibility-084): common drops have no pool/light/column, rare and
## unique have all three (unique stronger), and everything is gone when the drop is picked up. Optional screenshot with --shot.
##   tools/run_godot.sh LOG 60 -- --script res://tools/loot_visibility_check.gd -- --check
## User arguments make it a developer session: the production save is never touched.

var failures: int = 0

func expect(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1

func _initialize() -> void:
	_run()

func _run() -> void:
	TownState.reset()
	TownState.job = {}
	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 6:
		await process_frame
	var player: Player = main.hud.player
	var drops: Array[LootDrop] = []
	var rarities := [Items.Rarity.NORMAL, Items.Rarity.MAGIC, Items.Rarity.RARE]
	for i in 3:
		var d: LootDrop = main.director.drop_item(player.global_position + Vector3(-1.6 + i * 1.6, 0, -3.0), Items.make(Items.Slot.WEAPON, rarities[i], 1))
		drops.append(d)
	for i in 40:
		await process_frame
	var pools: Array[bool] = []
	for d in drops:
		pools.append(d._pool != null)
		print("rarity=%d pool=%s light=%s column=%s" % [int(d.item["rarity"]), d._pool != null, d._light != null, d._column != null])
	expect("common: no pool, light or column", not pools[0] and drops[0]._light == null and drops[0]._column == null)
	expect("rare: pool, light and column", pools[1] and drops[1]._light != null and drops[1]._column != null)
	expect("unique: pool, light and column", pools[2] and drops[2]._light != null and drops[2]._column != null)
	expect("unique pool larger/stronger than rare", (drops[2]._pool.mesh as PlaneMesh).size.x > (drops[1]._pool.mesh as PlaneMesh).size.x and drops[2]._pool_alpha > drops[1]._pool_alpha)
	if "--shot" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png("res://tools/loot_visibility.png")
	var rare_pool: Node = drops[1]._pool
	player.global_position = drops[1].global_position
	drops[1].pick_up(player)
	await process_frame
	await process_frame
	expect("picked-up rare and its pool are freed", not is_instance_valid(drops[1]) and not is_instance_valid(rare_pool))
	expect("other drops unaffected", is_instance_valid(drops[2]) and is_instance_valid(drops[0]))
	print("RESULT failures=%d" % failures)
	quit(1 if failures > 0 else 0)
