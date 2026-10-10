extends SceneTree
## Headless numeric check of WeaponTrail: godot --headless -s tools/weapon_trail_check.gd
var fails := 0

func _ok(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		fails += 1

func _swing(t: WeaponTrail, frames: int) -> void:
	for i in frames:
		var a := float(i) * 0.15
		t.step(1.0 / 60.0, Vector3(cos(a), 1, sin(a)) * 0.3, Vector3(cos(a), 1, sin(a)) * 1.3)

func _init() -> void:
	var t := WeaponTrail.new()
	root.add_child(t)
	t.active = false
	t.step(0.016, Vector3.ZERO, Vector3(0, 0, 1))
	_ok(t.point_count() == 0, "idle: no points")
	t.active = true
	_swing(t, 30)
	var n_light := t.point_count()
	_ok(n_light >= 2 and n_light <= 0.2 * 60 + 2, "light swing keeps a short ribbon (%d pts)" % n_light)
	t.active = false
	for i in 6:
		t.step(1.0 / 60.0, Vector3.ZERO, Vector3(0, 0, 1))
	_ok(t.point_count() == 0, "light: drained within 0.1s after swing ends")
	t.max_age = 0.34
	t.strength = 0.85
	t.active = true
	_swing(t, 40)
	_ok(t.is_heavy() and t.point_count() > n_light, "heavy ribbon is longer (%d pts)" % t.point_count())
	t.clear()
	_ok(t.point_count() == 0, "clear() empties (cancel/death/revive)")
	t.active = true
	_swing(t, 10)
	t.step(0.016, Vector3.ZERO, Vector3(50, 0, 0))
	_ok(t.point_count() == 1, "teleport drops old ribbon")
	_swing(t, 10)
	var a := Node3D.new()
	root.add_child(a)
	t.base_node = a
	_ok(t.point_count() == 0, "equipment/node swap clears ribbon")
	t.active = true
	t.step(0.016, Vector3.ZERO, Vector3(0, 0, 1))
	t.step(0.016, Vector3.ZERO, Vector3(0, 0, 1))
	_ok(t.point_count() == 1, "stationary blade adds no stacked samples")
	t.active = false
	t.step(1.0, Vector3.ZERO, Vector3(0, 0, 1))
	_ok(t.point_count() == 0, "no lingering trail at idle")
	print("RESULT ", "PASS" if fails == 0 else "FAIL")
	quit(fails)
