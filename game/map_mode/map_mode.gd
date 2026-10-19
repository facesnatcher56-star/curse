class_name MapMode
extends Node
## Map mode, Step 1 (`-- --crypt01 --mapmode`, issue #79): pick a group on a full-screen map, the party dashes there, the hero and Cutter fight it
## automatically (nearest first, or the focus target the player clicked), and when it is cleared the loot is collected and the map opens again.
## Nothing here runs unless the flag is on: `MapMode.active` is false and every hook in Player and PartyCharacterAI is skipped.
##
## One state machine: WAITING (the world is still filling) -> MAP -> DASH -> FIGHT -> (clear, collect) -> MAP ... Groups are isolated: only the
## chosen group is woken. The map cannot be opened mid-fight. Click-to-move and the walking stick do nothing in this mode.

## Tuning, all in one place.
const DASH_TIME := 1.0            # seconds from the map click to the party standing at the group
const ARRIVE_DISTANCE := 6.0      # m from the group's centre, on the side the party came from
const COMPANION_SIDE := 2.0       # m the companion stands beside the hero on arrival
const COLLECT_DELAY := 1.4        # s after the last kill before drops are collected (they have to land)
const TRAIL_STEP := 0.04          # s between afterimages during the dash
const TRAIL_LIFE := 0.35

const ID_LOOT := 100000           # marker ids: groups use their group_id, loot ID_LOOT + n, chests ID_CHEST + n
const ID_CHEST := 200000

enum State { WAITING, MAP, DASH, FIGHT, COLLECT, DEAD }

static var current: MapMode
## True while a MapMode node is running; the hooks in Player and PartyCharacterAI test this.
static var active: bool:
	get: return current != null

var state: State = State.WAITING
var hero: Player
var companion: Player
var hud: Hud
var overlay: MapModeOverlay
var log: MapFightLog = MapFightLog.new()
var focus: Actor
var group_id: int = -1            # the group being fought (-1 for a chest or loot visit)
var _visit_pos: Vector3
var _visit_kind: String = "group"
var _visit_ref: Variant
var _dash_t: float = 0.0
var _dash_paths: Array = []       # per member: {body, points, lengths, total, offset}
var _trail_clock: float = 0.0
var _collect_clock: float = 0.0
var _labels: Dictionary = {}      # group_id -> label, captured while the group was whole
var _chests: Array = []
var _loot_refs: Array = []
var _hit_logged: bool = false
var _auto_dir: String = ""        # `--mapmode-auto=<dir>`: a developer tool that plays the whole run itself and saves screenshots there
var _shot_n: int = 0
var _auto_started_ms: int = 0

## The flag: opt-in, and only in the hand-built Crypt.
static func requested() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	return args.has("--mapmode") and args.has("--crypt01")

static func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func setup(for_hero: Player, for_companion: Player, for_hud: Hud) -> void:
	hero = for_hero
	companion = for_companion
	hud = for_hud

func _enter_tree() -> void:
	current = self
	process_physics_priority = 100   # after the bodies have moved, so the dash wins over their own steering

func _exit_tree() -> void:
	if current == self:
		current = null

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mapmode-auto="):
			_auto_dir = arg.substr(15)
			DirAccess.make_dir_recursive_absolute(_auto_dir)
			_auto_started_ms = Time.get_ticks_msec()
	for body in [hero, companion]:
		if body != null:
			body.power_activated.connect(func(_id: String, power_id: String) -> void: log.note_power(power_id))

# --- Flow -----------------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hero):
		return
	match state:
		State.WAITING:
			if hud != null and hud.minimap != null and not live_groups().is_empty() and Nav.ready(hero):
				_open_map()
		State.DASH:
			_tick_dash(delta)
		State.FIGHT:
			_tick_fight()
		State.COLLECT:
			_collect_clock -= delta
			if _collect_clock <= 0.0:
				_collect_rewards()
				_open_map()
		State.DEAD:
			if not hero.dead:
				_open_map()

func _input(event: InputEvent) -> void:
	if state != State.FIGHT:
		return
	if event is InputEventMouseButton and event.pressed:
		log.note_input(now(), "click")
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.pressed and not event.is_echo():
		log.note_input(now(), "key")

## Hero hooks -------------------------------------------------------------------------------------------------------------------------

## Player._read_input in this mode: a click on an enemy during a fight picks it as the focus; clicks on the ground do nothing.
static func read_input(p: Player, cursor: Vector3) -> void:
	if p.is_controlled() and Input.is_action_just_pressed("click") and not p.mouse_over_ui():
		if p._confirm_party_take_aim(cursor):
			return
		var picked: Actor = p._hover_pick(cursor)
		if picked != null and current != null:
			current.set_focus(picked)
	var pad: Actor = p.pad_facing_target() if Gamepad.active and Input.is_action_just_pressed("interact") else null
	if pad != null and current != null:
		current.set_focus(pad)

func set_focus(target: Actor) -> void:
	if state == State.FIGHT and is_instance_valid(target) and not target.dead and target.is_in_group("enemies"):
		focus = target
		for body in [hero, companion]:   # at once, even mid-swing: the Cutter's own loop only re-picks between shots
			if is_instance_valid(body) and not body.dead:
				body.attack_target = target
		log.note_input(now(), "focus")

## The enemy `body` should attack now (PartyCharacterAI and the hero's own loop both ask).
func target_for(body: Player) -> Actor:
	if state != State.FIGHT:
		return null
	if is_instance_valid(focus) and not focus.dead:
		return focus
	var best: Actor = null
	for enemy in group_members():
		if best == null or enemy.flat_distance_to(body) < best.flat_distance_to(body):
			best = enemy
	return best

static func note_hit() -> void:
	if current != null and current.state == State.FIGHT and not current._hit_logged:
		current._hit_logged = true
		current.log.note_first_hit(now())

static func note_damage(body: Player, amount: float) -> void:
	if current != null and current.state == State.FIGHT:
		current.log.note_damage_taken(amount, body.member_id)

# --- Groups and markers ------------------------------------------------------------------------------------------------------------------

## Living enemies of one group (or of the fight's group), asleep or not.
func group_members(id: int = -2) -> Array[Enemy]:
	var wanted: int = group_id if id == -2 else id
	var out: Array[Enemy] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and e.group_id == wanted:
			out.append(e)
	return out

## group_id -> its living members, for every placed group still alive.
func live_groups() -> Dictionary:
	var out: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and e.group_id >= 0:
			if not out.has(e.group_id):
				out[e.group_id] = []
			out[e.group_id].append(e)
	return out

## What a group is expected to leave: a champion's chest, an item for the big kinds, otherwise gold. (Step 1 label only; the real roll is
## MonsterLoot at the moment of the kill.)
static func guard_of(members: Array) -> String:
	var big: bool = false
	for e in members:
		if (e as Enemy).champion != null:
			return "champion chest"
		big = big or (e as Enemy).is_big()
	return "item" if big else "gold"

static func group_label(members: Array) -> String:
	var counts: Dictionary = {}
	for e in members:
		counts[(e as Enemy).variant] = int(counts.get((e as Enemy).variant, 0)) + 1
	var parts: PackedStringArray = []
	for kind in counts:
		parts.append("%d %s" % [counts[kind], String(kind).replace("_", " ")])
	return "%s - guards: %s" % [", ".join(parts), guard_of(members)]

func centre_of(members: Array) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	for e in members:
		sum += (e as Node3D).global_position
	return sum / maxf(float(members.size()), 1.0)

## The markers the map shows now: live groups, unopened chests, loot left on the ground.
func markers() -> Array:
	var out: Array = []
	var groups: Dictionary = live_groups()
	for id in groups:
		var members: Array = groups[id]
		if not _labels.has(id):
			_labels[id] = group_label(members)
		out.append({"id": int(id), "pos": centre_of(members), "kind": "group", "label": String(_labels[id])})
	_chests.clear()
	for node in get_tree().get_nodes_in_group("chests"):
		var chest := node as Chest
		if chest != null and not chest.opened:
			_chests.append(chest)
			out.append({"id": ID_CHEST + _chests.size() - 1, "pos": chest.global_position, "kind": "chest", "label": "Chest"})
	_loot_refs.clear()
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop != null and not drop.is_queued_for_deletion():
			_loot_refs.append(drop)
			out.append({"id": ID_LOOT + _loot_refs.size() - 1, "pos": drop.global_position, "kind": "loot", "label": "%s (inventory full)" % String(drop.item.get("name", "Item"))})
	return out

func _ensure_overlay() -> void:
	if overlay != null:
		return
	overlay = MapModeOverlay.new()
	overlay.selected.connect(select_marker)
	hud.add_child(overlay)
	hud.minimap.map_data.ensure_built(get_tree())
	overlay.map_data = hud.minimap.map_data

func _open_map() -> void:
	focus = null
	if live_groups().is_empty() and _leftover_markers().is_empty():
		state = State.WAITING
		for line in log.summary_lines():
			print(line)
		if _auto_dir != "":
			get_tree().quit()
		return
	_ensure_overlay()
	state = State.MAP
	overlay.open(markers(), hero.global_position, false)
	if _auto_dir != "":
		_auto_pick()

## The developer autoplay: shoot the map, pick the nearest marker, shoot the dash and the fight, fire a power, repeat until nothing is left.
func _auto_pick() -> void:
	await get_tree().create_timer(0.8).timeout
	await _shot("map")
	var best: Dictionary = {}
	for m in markers():
		if best.is_empty() or hero.global_position.distance_to(m["pos"]) < hero.global_position.distance_to(best["pos"]):
			best = m
	select_marker(int(best["id"]))
	await get_tree().create_timer(0.45).timeout
	await _shot("dash")
	await _wait_fight()
	if state == State.FIGHT:
		await get_tree().create_timer(1.5).timeout
		await _shot("fight")
		Input.action_press("skill_1")
		await get_tree().create_timer(0.2).timeout
		Input.action_release("skill_1")
	await get_tree().create_timer(1.0).timeout
	if Time.get_ticks_msec() - _auto_started_ms > 900000:
		for line in log.summary_lines():
			print(line)
		get_tree().quit()

func _wait_fight() -> void:
	while state == State.DASH:
		await get_tree().physics_frame

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_n += 1
	get_viewport().get_texture().get_image().save_png("%s/%02d_%s.png" % [_auto_dir, _shot_n, label])

func _leftover_markers() -> Array:
	return markers().filter(func(m: Dictionary) -> bool: return m["kind"] != "group")

## The map click.
func select_marker(id: int) -> void:
	if state != State.MAP:
		return
	var list: Array = markers()
	var picked: Dictionary = {}
	for m in list:
		if int(m["id"]) == id:
			picked = m
	if picked.is_empty():
		return
	_visit_kind = String(picked["kind"])
	_visit_pos = picked["pos"]
	group_id = id if _visit_kind == "group" else -1
	_visit_ref = null
	if _visit_kind == "chest":
		_visit_ref = _chests[id - ID_CHEST]
	elif _visit_kind == "loot":
		_visit_ref = _loot_refs[id - ID_LOOT]
	overlay.close()
	_hit_logged = false
	log.begin_fight(String(picked["label"]), now())
	_start_dash()

# --- Dash ----------------------------------------------------------------------------------------------------------------------------

func arrival_spot() -> Vector3:
	var from: Vector3 = hero.global_position
	var away: Vector3 = from - _visit_pos
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	var reach: float = ARRIVE_DISTANCE if _visit_kind == "group" else 1.2
	return Nav.snap(hero, _visit_pos + away.normalized() * reach)

func _start_dash() -> void:
	state = State.DASH
	_dash_t = 0.0
	_trail_clock = 0.0
	_dash_paths.clear()
	var spot: Vector3 = arrival_spot()
	var side: Vector3 = (spot - hero.global_position).cross(Vector3.UP).normalized() * COMPANION_SIDE
	var goals: Array = [spot, Nav.snap(companion, spot + side)]
	var bodies: Array = [hero, companion]
	for i in 2:
		var body: Player = bodies[i]
		if body == null or body.dead:
			continue
		body.movement.has_goal = false
		body.attack_target = null
		body.skills.clear_queue()
		var pts: PackedVector3Array = NavigationServer3D.map_get_path(Nav.map_of(body), body.global_position, goals[i], true)
		if pts.size() < 2:
			pts = PackedVector3Array([body.global_position, goals[i]])
		var total: float = 0.0
		var lengths: PackedFloat32Array = PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			total += pts[k - 1].distance_to(pts[k])
			lengths.append(total)
		_dash_paths.append({"body": body, "points": pts, "lengths": lengths, "total": total})

func _tick_dash(delta: float) -> void:
	_dash_t += delta
	var t: float = clampf(_dash_t / DASH_TIME, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	for row in _dash_paths:
		var body: Player = row["body"]
		if not is_instance_valid(body):
			continue
		var pts: PackedVector3Array = row["points"]
		var lengths: PackedFloat32Array = row["lengths"]
		var along: float = float(row["total"]) * eased
		var k: int = 1
		while k < pts.size() - 1 and lengths[k] < along:
			k += 1
		var span: float = maxf(lengths[k] - lengths[k - 1], 0.001)
		var at: Vector3 = pts[k - 1].lerp(pts[k], clampf((along - lengths[k - 1]) / span, 0.0, 1.0))
		body.global_position = at
		body.velocity = Vector3.ZERO
		body.face(pts[k], 1.0)
	_trail_clock -= delta
	if _trail_clock <= 0.0:
		_trail_clock = TRAIL_STEP
		for row in _dash_paths:
			_afterimage((row["body"] as Node3D).global_position)
	if t >= 1.0:
		_arrive()

func _afterimage(at: Vector3) -> void:
	var ghost := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.25
	mesh.height = 1.7
	ghost.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.75, 1.0, 0.3)
	ghost.material_override = mat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ghost)
	ghost.global_position = at + Vector3(0, 0.9, 0)
	var tween := ghost.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, TRAIL_LIFE)
	tween.tween_callback(ghost.queue_free)

func _arrive() -> void:
	log.note_dash_end(now())
	match _visit_kind:
		"group":
			state = State.FIGHT
			for e in group_members():
				e.alert_delay = 0.0
				e.wake()
		"chest":
			if is_instance_valid(_visit_ref):
				(_visit_ref as Chest).open()
			_begin_collect()
		_:
			_begin_collect()

# --- Fight ---------------------------------------------------------------------------------------------------------------------------

func _tick_fight() -> void:
	if hero.dead:
		log.end_fight(now())
		state = State.DEAD
		return
	if group_members().is_empty():
		_begin_collect()
		return
	hero.attack_target = target_for(hero)

func _begin_collect() -> void:
	var row: Dictionary = log.end_fight(now())
	if not row.is_empty():
		log.emit_line(row)
	focus = null
	hero.attack_target = null
	if _auto_dir != "":
		_shot("clear")
	state = State.COLLECT
	_collect_clock = COLLECT_DELAY if _visit_kind != "loot" else 0.1

## Drops go straight to the inventory; what does not fit stays on the ground (and shows on the map). Gold and potions fly to the hero.
func _collect_rewards() -> void:
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop == null or drop.is_queued_for_deletion():
			continue
		if hero.stats.pickup(drop.item) != "":
			drop.queue_free()
	for node in get_tree().get_nodes_in_group("orbs"):
		var orb := node as Node3D
		if orb != null and not orb.is_queued_for_deletion():
			orb.global_position = hero.global_position + Vector3(0, 0.6, 0)
