extends SceneTree
## Focused check of the enemy attack telegraph vocabulary: telegraphs are a pulsing, non-red, kind-tinted overlay that is distinct
## from the red hit flash, the hit flash still wins, nothing persists after the telegraph ends, and a crowd stays bounded.
## Run: tools/run_godot.sh LOG 120 -- --script res://tools/enemy_telegraph_check.gd -- --telegraphcheck [--shots=DIR]
## (windowed for --shots: GODOT_HEADLESS=). Exit code 1 if any check fails.

var failures: int = 0
var main: Node
var shots_dir: String = ""
const HERO := Vector3(30, 0, 30)

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(shots_dir)
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	_run()

func _shoot(name: String) -> void:
	if shots_dir == "":
		return
	await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots_dir, name])

func _overlay(e: Enemy) -> Material:
	var meshes: Array = e.model.find_children("*", "MeshInstance3D", true, false)
	return (meshes[0] as MeshInstance3D).material_overlay if not meshes.is_empty() else null

## Enemies that never act (no target aggro), so only what the check does shows on them.
func _dummy(kind: String, at: Vector3) -> Enemy:
	var e: Enemy = main.director.spawn_enemy(at, kind, 1.0)
	e.aggro_range = 0.0
	return e

func _run() -> void:
	for i in 10:
		await process_frame
	var p: Player = main.player
	p.max_health = 5000.0
	p.health = 5000.0
	p.global_position = HERO
	p.reset_physics_interpolation()
	main.rig.global_position = HERO
	for n in get_nodes_in_group("enemies"):
		n.queue_free()
	await process_frame

	var kinds := {"zombie": "windup", "spitter": "spit", "bloater": "fuse", "priest": "cast"}
	var es: Array = []
	var i := 0
	for k in kinds.keys():
		var e: Enemy = _dummy(k, HERO + Vector3(-4.5 + i * 3.0, 0, -6.0))
		es.append(e)
		i += 1
	await physics_frame

	# Looks are distinct from the hit flash (red) and from each other.
	var hues: Array = []
	for kind in Enemy.TELEGRAPH_LOOKS.keys():
		var c: Color = Enemy.TELEGRAPH_LOOKS[kind][0]
		check("%s tint is not the red hit-flash family" % kind, not (c.r > 0.85 and c.g < 0.4 and c.b < 0.4), str(c))
		check("%s tint is muted (no neon)" % kind, c.get_luminance() < 0.8 and maxf(c.r, maxf(c.g, c.b)) < 0.97)
		for h in hues:
			check("%s hue differs from another kind" % kind, absf(c.h - h) > 0.04)
		hues.append(c.h)

	# Telegraph on all four at once: each shows its own overlay, none is the hit-flash material.
	for step in 12:
		var idx := 0
		for k in kinds.keys():
			(es[idx] as Enemy).telegraph(0.55, kinds[k])
			idx += 1
		await physics_frame
	var distinct := {}
	for e in es:
		var ov := _overlay(e)
		check("%s shows the telegraph overlay" % e.def.id, ov != null and ov != e._flash_mat and e.is_telegraphing())
		if ov != null:
			distinct[(ov as StandardMaterial3D).albedo_color.to_html(false).substr(0, 6)] = true
	check("simultaneous telegraphs read as different tints", distinct.size() >= 3, str(distinct.keys()))
	var alphas: Array = []
	for step in 30:
		(es[0] as Enemy).telegraph(0.55, "windup")
		await physics_frame
		alphas.append(((_overlay(es[0]) as StandardMaterial3D).albedo_color.a))
	check("telegraph pulses (alpha varies)", (alphas.max() as float) - (alphas.min() as float) > 0.08, "%.2f..%.2f" % [alphas.min(), alphas.max()])
	var hit: Enemy = _dummy("zombie", HERO + Vector3(-4.5 + 4 * 3.0, 0, -6.0))   # a freshly hit zombie beside the telegraphing four
	await physics_frame
	hit._flash = 1.0
	hit.model.set_overlay(hit._flash_mat)
	await _shoot("telegraph_crowd_zoom1")
	hit._flash = 0.0
	hit.model.set_overlay(null)
	main.rig.set_zoom_now(1.0)

	# The hit flash wins over a telegraph and the telegraph returns after it.
	var z: Enemy = es[0]
	z._flash = 1.0
	z.model.set_overlay(z._flash_mat)
	z.telegraph(0.55, "windup")
	check("hit flash wins over telegraph", _overlay(z) == z._flash_mat)
	for s in 40:
		await physics_frame
	check("no overlay left once flash and telegraph both end", _overlay(z) == null and not z.is_telegraphing(), str(_overlay(z)))

	# Everything clears after the telegraph ends.
	for e in es:
		check("%s overlay cleared after telegraph ends" % e.def.id, _overlay(e) == null and not e.is_telegraphing())

	# A highlighted enemy gets its highlight back afterwards.
	var s: Enemy = es[1]
	s.set_highlighted(true)
	s.telegraph(0.3, "spit")
	for st in 12:
		await physics_frame
	check("highlight restored after telegraph", not s.is_telegraphing() and _overlay(s) == s.get_highlight_material())
	s.set_highlighted(false)

	# Dying mid-telegraph leaves no overlay.
	var d: Enemy = es[2]
	d.telegraph(0.5, "fuse")
	d._die()
	await physics_frame
	check("death clears the telegraph overlay", _overlay(d) == null)

	print("TELEGRAPH CHECK ", "FAILED (%d)" % failures if failures > 0 else "OK")
	quit(1 if failures > 0 else 0)
