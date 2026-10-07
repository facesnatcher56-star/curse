extends SceneTree
## Display-independent check of combat impact presentation: light vs heavy vs crushing profiles, dedup of melee and body impacts,
## the voice and flash caps, the settings toggles, and that presentation never resolves or deals damage.
## Run: tools/run_godot.sh LOG 90 -- --script res://tools/combat_impact_check.gd -- --impactcheck
## (user arguments make it a developer session: the production save is never touched). Exit code 1 if any check fails.

var failures: int = 0
var scene: Node3D
var rig: CameraRig
var hero: Node3D

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	await process_frame
	await _run()
	Sfx.enabled = false
	Fx.reset_time()
	quit(1 if failures > 0 else 0)

func _fresh() -> void:
	if scene != null:
		scene.free()
	Fx.reset_time()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	hero = Node3D.new()
	scene.add_child(hero)
	rig = CameraRig.new()
	scene.add_child(rig)
	rig.target = hero
	rig.global_position = Vector3.ZERO

func lights() -> int:
	return get_nodes_in_group("flash_light").size()

func _run() -> void:
	GameSettings.screen_shake = 1.0
	GameSettings.slow_motion = true
	var damage_before: Dictionary = Combat.tally.duplicate()

	# --- profiles: strictly ordered and bounded
	var light: Dictionary = Fx.impact_profile(Combat.Outcome.HIT, 1.0)
	var crit: Dictionary = Fx.impact_profile(Combat.Outcome.CRITICAL, 1.0)
	var crush: Dictionary = Fx.impact_profile(Combat.Outcome.CRUSHING, 1.0)
	check("light hit: tier 0, no hit-stop", light.tier == 0 and light.hitstop == 0.0)
	check("critical stronger than light", crit.tier > light.tier and crit.kick > light.kick and crit.hitstop > 0.0)
	check("crushing stronger than critical", crush.tier > crit.tier and crush.kick > crit.kick and crush.hitstop > crit.hitstop)
	var huge: Dictionary = Fx.impact_profile(Combat.Outcome.CRUSHING, 99.0)
	check("heavy profile bounded", huge.kick <= 1.4 and huge.hitstop <= 0.08, str(huge))
	check("miss/block map to the light profile", Fx.impact_profile(Combat.Outcome.MISS, 1.0).tier == 0 and Fx.impact_profile(Combat.Outcome.BLOCK, 1.0).hitstop == 0.0)

	# --- melee tiers draw once, heavier tiers draw more, and stay compact
	_fresh()
	var p := Vector3(2, 1, 0)
	var n0: int = scene.get_child_count()
	check("light draws once", Fx.melee_impact(scene, p, Vector3.RIGHT, 0, 1) and not Fx.melee_impact(scene, p, Vector3.RIGHT, 0, 1))
	var light_nodes: int = scene.get_child_count() - n0
	_fresh()
	n0 = scene.get_child_count()
	check("crushing draws once", Fx.melee_impact(scene, p, Vector3.RIGHT, 2, 2) and not Fx.melee_impact(scene, p, Vector3.RIGHT, 2, 2))
	var crush_nodes: int = scene.get_child_count() - n0
	check("crushing heavier than light but compact", crush_nodes > light_nodes and crush_nodes <= 4 and lights() == 1, "light=%d crush=%d" % [light_nodes, crush_nodes])

	# --- a sweep over many targets: flash lights capped
	_fresh()
	for i in 10:
		Fx.melee_impact(scene, p + Vector3(i * 0.2, 0, i * 0.7), Vector3.RIGHT, 2, 100 + i)
	check("multi-target sweep: flash lights capped", lights() <= Fx.MAX_FLASH_LIGHTS, "lights=%d" % lights())

	# --- body impacts: deduped per kind, bounded
	_fresh()
	check("body-wall draws once", Fx.body_impact(scene, p, Vector3.RIGHT, "wall", 10.0) and not Fx.body_impact(scene, p, Vector3.RIGHT, "wall", 10.0))
	check("body-enemy independent of wall, draws once", Fx.body_impact(scene, p, Vector3.RIGHT, "enemy", 8.0) and not Fx.body_impact(scene, p, Vector3.RIGHT, "enemy", 8.0))
	check("body impact elsewhere still draws", Fx.body_impact(scene, p + Vector3(5, 0, 0), Vector3.RIGHT, "wall", 10.0))

	# --- audio: respects the switch, files come from existing families, voices capped
	Sfx.enabled = false
	var played: int = Sfx.samples_played
	Sfx.body_impact(scene, "wall", 10.0)
	Sfx.sword_hit(scene, Combat.Outcome.CRUSHING, 1.0)
	check("Sfx.enabled=false stays silent", Sfx.samples_played == played)
	Sfx.enabled = true
	Sfx.played_log.clear()
	Sfx.body_impact(scene, "wall", 14.0)
	Sfx.body_impact(scene, "wall", 14.0)   # same family inside the gap
	check("same-family repeat inside the gap is one voice", Sfx.played_log.size() == 1, str(Sfx.played_log))
	check("wall thud uses an existing recording", Sfx.played_log.size() == 1 and Sfx.played_log[0] in Sfx.FAMILIES["body_wall"])
	for i in 12:   # fill the room with voices
		var v := AudioStreamPlayer.new()
		v.add_to_group("sfx_voice")
		scene.add_child(v)
	var before: int = Sfx.samples_played
	await create_timer(0.1).timeout
	Sfx.body_impact(scene, "enemy", 10.0)
	check("voice cap blocks a body-impact pile-up", Sfx.samples_played == before)
	Sfx.enabled = false

	# --- camera toggles
	_fresh()
	GameSettings.screen_shake = 0.0
	Fx.shake(rig, 0.5)
	check("screen_shake=0 gives no shake", rig._shake == 0.0)
	GameSettings.screen_shake = 1.0
	Fx.shake(rig, 0.05)
	check("screen_shake=1 shakes", rig._shake > 0.0)
	GameSettings.slow_motion = false
	Fx.slowmo(scene, 0.1, 0.2)
	check("slow_motion off: clock untouched", Engine.time_scale == 1.0)
	GameSettings.slow_motion = true

	# --- presentation never resolves damage
	check("presentation resolved no combat outcomes", Combat.tally == damage_before, str(Combat.tally))
