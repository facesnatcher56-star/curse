extends SceneTree
## Display-independent check of the camera's impact response: drives CameraRig by hand at fixed time steps with the same amounts the
## game's hits and skills send through Fx, and reports camera offsets and positions. No window, mouse or focus needed.
## Run: tools/run_godot.sh LOG 60 -- --script res://tools/camera_impact_check.gd -- --camcheck
## (user arguments make it a developer session: the production save is never touched). Exit code 1 if any check fails.

var failures: int = 0
var rig: CameraRig
var hero: Node3D

func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS  " if ok else "FAIL  "), label, "  ", detail)
	if not ok:
		failures += 1

func _initialize() -> void:
	await process_frame
	await _run()
	quit(1 if failures > 0 else 0)

func _fresh() -> void:
	if rig != null:
		rig.free()
		hero.free()
	hero = Node3D.new()
	hero.set("name", "Hero")
	root.add_child(hero)
	rig = CameraRig.new()
	root.add_child(rig)
	rig.target = hero
	rig.global_position = Vector3.ZERO
	step(0.0166, 3)

func step(dt: float, n: int) -> void:
	for i in n:
		rig._process(dt)

## Runs `seconds` of frames and returns {peak shake offset, seconds until the view is still, peak displacement of the rig}.
func run_for(seconds: float, dt: float) -> Dictionary:
	var peak: float = 0.0
	var peak_disp: float = 0.0
	var settled_at: float = -1.0
	var t: float = 0.0
	while t < seconds:
		rig._process(dt)
		t += dt
		var off: float = maxf(absf(rig.camera.h_offset), absf(rig.camera.v_offset))
		peak = maxf(peak, off)
		peak_disp = maxf(peak_disp, rig.global_position.distance_to(hero.global_position))
		if off > 0.004 or rig.global_position.distance_to(hero.global_position) > 0.02 or absf(rig.camera.fov - rig.fov) > 0.05:
			settled_at = -1.0
		elif settled_at < 0.0:
			settled_at = t
	return {"peak": peak, "disp": peak_disp, "settled": settled_at}

func hit(shake: float, kick: float, punch: float = 0.0) -> void:
	Fx.shake(rig, shake)
	if kick > 0.0:
		Fx.kick(rig, Vector3(1, 0, 0.3), kick)
	if punch > 0.0:
		Fx.punch(rig, punch)

func _run() -> void:
	await process_frame
	GameSettings.screen_shake = 1.0
	var dt: float = 1.0 / 60.0

	_fresh()
	hit(0.03 + 20.0 * 0.004, 0.5)   # an ordinary hit on the hero (actor.gd: shake 0.03..0.12, kick 0.5 x weight)
	var ordinary: Dictionary = run_for(1.5, dt)
	print("ordinary hit  ", ordinary)
	check("ordinary hit is subtle", ordinary.peak <= 0.12 and ordinary.peak > 0.0)
	check("ordinary hit settles quickly", ordinary.settled > 0.0 and ordinary.settled < 0.7, str(ordinary.settled))

	_fresh()
	hit(0.12 + 0.12, 0.5 * 2.0, 1.4)   # heavy hit with knockdown: actor shake x weight, ragdoll 0.12, kick, FOV punch (player.gd)
	var heavy: Dictionary = run_for(2.0, dt)
	print("heavy hit     ", heavy)
	check("heavy hit stronger than ordinary", heavy.peak > ordinary.peak)
	check("heavy hit within the ceiling", heavy.peak <= CameraRig.MAX_SHAKE + 0.0001)
	check("heavy hit settles", heavy.settled > 0.0 and heavy.settled < 1.2, str(heavy.settled))

	_fresh()
	hit(0.4, 0.7, 3.0)   # Earthshatter / large landing (skill_fx.gd)
	var big: Dictionary = run_for(2.5, dt)
	print("large landing ", big)
	check("landing capped at the ceiling", big.peak <= CameraRig.MAX_SHAKE + 0.0001 and big.peak > 0.25)
	check("landing displacement bounded", big.disp <= 0.7, str(big.disp))
	check("landing recovers to a stable camera", big.settled > 0.0 and big.settled < 1.6, str(big.settled))
	check("camera rests exactly at the hero's frame", rig.camera.h_offset == 0.0 and rig.camera.v_offset == 0.0 and is_equal_approx(rig.camera.fov, rig.fov))

	# no stacking: one logical blow reported by several systems in the same frame, and a crowd landing blows together
	_fresh()
	hit(0.2, 0.5)
	var single: Dictionary = run_for(1.0, dt)
	_fresh()
	for i in 6:
		hit(0.2, 0.5)
	var many: Dictionary = run_for(1.0, dt)
	print("single ", single, " six-at-once ", many)
	check("six identical impulses in one frame equal one", is_equal_approx(single.peak, many.peak) and is_equal_approx(single.disp, many.disp))
	_fresh()
	for i in 6:
		Fx.kick(rig, Vector3(0.2 * i, 0, 1), 0.5)
		step(dt, 1)
	check("rapid kicks across frames stay under the cap", rig._kick.length() <= CameraRig.MAX_KICK + 0.0001, str(rig._kick.length()))
	_fresh()
	hit(9.0, 9.0, 9.0)
	check("absurd inputs are clamped", rig._shake <= CameraRig.MAX_SHAKE and rig._kick.length() <= CameraRig.MAX_KICK and rig._fov_kick <= CameraRig.MAX_PUNCH)

	# no oscillation beyond a short sway: count sign changes of the horizontal offset for a heavy blow
	_fresh()
	hit(0.3, 0.0)
	var flips: int = 0
	var last: float = 0.0
	for i in 120:
		rig._process(dt)
		var h: float = rig.camera.h_offset
		if absf(h) > 0.003 and last != 0.0 and signf(h) != signf(last):
			flips += 1
		if absf(h) > 0.003:
			last = h
	print("sway sign changes ", flips)
	check("sway is a short thud, not a wobble", flips <= 5, str(flips))

	# frame-rate independence of the settle time
	var times: Array = []
	for fps in [30.0, 60.0, 144.0]:
		_fresh()
		hit(0.3, 0.7, 2.0)
		times.append(run_for(2.5, 1.0 / fps).settled)
	print("settle at 30/60/144 fps ", times)
	check("settle time is steady across frame rates", absf(times[0] - times[2]) < 0.4 and not times.has(-1.0), str(times))

	# death clears the shove and punch, revive/reset clears everything
	_fresh()
	hit(0.35, 0.8, 3.0)
	step(dt, 2)
	hero.set_meta("x", 1)
	var fake := FakeActor.new()
	root.add_child(fake)
	rig.target = fake
	step(dt, 1)   # a new target: a clean frame
	check("a new target starts from a still view", rig._shake == 0.0 and rig._kick == Vector3.ZERO and rig._fov_kick == 0.0)
	hit(0.35, 0.8, 3.0)
	fake.dead = true
	step(dt, 1)
	check("death drops shove and punch and caps the sway", rig._kick.length() < 0.001 and rig._fov_kick < 0.001 and rig._shake <= CameraRig.DEATH_SHAKE + 0.0001)
	hit(0.3, 0.5, 2.0)
	fake.dead = false
	step(dt, 1)
	check("revive clears every transient", rig._shake == 0.0 and rig._kick == Vector3.ZERO and rig._fov_kick == 0.0 and rig.camera.h_offset == 0.0 and rig.camera.v_offset == 0.0)
	fake.queue_free()

	# the shake setting scales it, and zero turns it off entirely
	_fresh()
	GameSettings.screen_shake = 0.0
	hit(0.3, 0.0)
	var off: Dictionary = run_for(0.5, dt)
	check("Screen shake 0 gives a dead-still view", off.peak == 0.0)
	GameSettings.screen_shake = 1.0

	print("camera impact check: ", "FAILED (%d)" % failures if failures > 0 else "all passed", "  display=", DisplayServer.get_name())

class FakeActor extends Node3D:
	var dead: bool = false
