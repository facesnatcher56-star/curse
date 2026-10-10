extends SceneTree
## Display-independent check of the shared impact FX: counts the nodes, lights, particles and lifetimes each effect spawns, that a repeat
## report of the same logical hit is suppressed, and that everything transient is gone afterwards. No window, mouse or focus needed.
## Run: tools/run_godot.sh LOG 90 -- --script res://tools/impact_fx_check.gd -- --fxcheck
## (user arguments make it a developer session: the production save is never touched). Exit code 1 if any check fails.

var failures: int = 0
var scene: Node3D
var hero: Player

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	InputSetup.apply()
	await process_frame
	await _run()
	quit(1 if failures > 0 else 0)

func _fresh() -> void:
	if scene != null:
		scene.free()
	Fx.reset_time()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	hero = Player.new()
	scene.add_child(hero)
	hero.global_position = Vector3.ZERO

## Nodes under the scene apart from the hero: what an effect has drawn so far.
func fx_nodes() -> Array:
	var out: Array = []
	for n in scene.get_children():
		if n != hero:
			out.append(n)
	return out

func count_of(cls: String) -> int:
	var c: int = 0
	for n in fx_nodes():
		if n.is_class(cls):
			c += 1
	return c

func settle(seconds: float) -> void:
	await create_timer(seconds).timeout

## Transient nodes still alive: everything except pooled spark emitters (reused on purpose) and ground scars (they linger and recycle).
func transient_left() -> int:
	var c: int = 0
	for n in fx_nodes():
		if n.is_in_group("stains"):
			continue
		if n is CPUParticles3D and not (n as CPUParticles3D).emitting and (n as CPUParticles3D).one_shot and n.get_child_count() == 0 and n.get_meta("pooled", true):
			continue
		c += 1
	return c

func _run() -> void:
	# --- light melee: a few sparks only
	_fresh()
	var p := Vector3(2, 1, 0)
	check("light melee draws", Fx.melee_impact(scene, p, Vector3.RIGHT, 0, 11))
	var light_nodes: int = fx_nodes().size()
	check("light melee: one small emitter, no light", light_nodes == 1 and count_of("OmniLight3D") == 0, "nodes=%d" % light_nodes)
	check("light melee repeat suppressed", not Fx.melee_impact(scene, p, Vector3.RIGHT, 0, 11))
	check("light melee on another target still draws", Fx.melee_impact(scene, p + Vector3(0.3, 0, 0), Vector3.RIGHT, 0, 12))

	# --- heavy melee: visibly more than light, still compact
	_fresh()
	check("heavy melee draws", Fx.melee_impact(scene, p, Vector3.RIGHT, 1, 21))
	var heavy_nodes: int = fx_nodes().size()
	check("heavy melee reads heavier than light", heavy_nodes > light_nodes and count_of("OmniLight3D") == 1, "heavy nodes=%d light nodes=%d" % [heavy_nodes, light_nodes])
	check("heavy melee compact", heavy_nodes <= 4, "nodes=%d" % heavy_nodes)
	check("heavy melee repeat suppressed", not Fx.melee_impact(scene, p, Vector3.RIGHT, 1, 21) and fx_nodes().size() == heavy_nodes)
	await settle(0.3)
	check("heavy melee flash gone", count_of("OmniLight3D") == 0)

	# --- Power Strike impact
	_fresh()
	SkillFx.power_impact(hero, Vector3(2, 0, 0), Vector3.RIGHT, false)
	var power_nodes: int = fx_nodes().size()
	var power_lights: int = count_of("OmniLight3D")
	check("power strike: bounded node count", power_nodes <= 32, "nodes=%d lights=%d" % [power_nodes, power_lights])
	SkillFx.power_impact(hero, Vector3(2.1, 0, 0), Vector3.RIGHT, false)
	check("power strike duplicate report suppressed", fx_nodes().size() == power_nodes, "nodes=%d" % fx_nodes().size())
	await settle(1.8)
	check("power strike cleans up", transient_left() == 0, "left=%d" % transient_left())

	# --- Earthshatter / ground slam
	_fresh()
	SkillFx.earthshatter_impact(hero, Vector3(0, 0, 0), 7.0)
	var es_nodes: int = fx_nodes().size()
	check("earthshatter: bounded node count", es_nodes <= 26, "nodes=%d lights=%d" % [es_nodes, count_of("OmniLight3D")])
	SkillFx.earthshatter_impact(hero, Vector3(0, 0, 0), 7.0)
	check("earthshatter duplicate suppressed", fx_nodes().size() == es_nodes)
	await settle(1.8)
	check("earthshatter cleans up (scars linger by design)", transient_left() == 0, "left=%d" % transient_left())

	# --- light cap when a crowd flashes at once
	_fresh()
	for i in 10:
		Fx.light_flash(scene, Vector3(i * 3, 1, 0), Color.WHITE, 2.0, 0.1)
	check("flash lights capped", count_of("OmniLight3D") == Fx.MAX_FLASH_LIGHTS, "lights=%d" % count_of("OmniLight3D"))
	await settle(0.4)
	check("flash lights freed", count_of("OmniLight3D") == 0)

	# --- fireball impact flash
	_fresh()
	var fb := Projectile.new()
	scene.add_child(fb)
	fb.blast_radius = 3.0
	fb.global_position = Vector3(4, 1, 0)
	fb._explosion_flash(fb.global_position)
	var fb_nodes: int = fx_nodes().size() - 1   # the projectile itself
	check("fireball flash: bounded, one light", fb_nodes <= 5 and count_of("OmniLight3D") == 1, "nodes=%d" % fb_nodes)
	check("fireball repeat claim suppressed", Fx.claim_impact("fireball", fb.global_position) and not Fx.claim_impact("fireball", fb.global_position))
	await settle(1.2)

	# --- reset clears dedup history
	Fx.claim_impact("x", Vector3.ZERO)
	Fx.reset_time()
	check("reset clears impact history", Fx.claim_impact("x", Vector3.ZERO))

	scene.free()
	print("RESULT  failures=%d" % failures)
