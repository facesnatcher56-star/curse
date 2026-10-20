class_name MapMode
extends Node
## Map mode (`-- --mapmode`, issue #79): pick a group on a full-screen map, the party dashes there, the hero and Cutter fight it
## automatically (nearest first, or the focus target the player clicked), and when it is cleared the loot is collected and the map opens again.
## Nothing here runs unless the flag is on: `MapMode.active` is false and every hook in Player and PartyCharacterAI is skipped.
##
## One state machine: WAITING (the world is still filling) -> MAP -> DASH -> FIGHT -> (clear, collect) -> MAP ... Groups are isolated: only the
## chosen group is woken. The map cannot be opened mid-fight. Click-to-move and the walking stick do nothing in this mode.
##
## Two maps. With a `graph` (MapGraph: the node map of a MapModeDungeon, or one handed to use_graph) the map is a graph of nodes joined by paths:
## only reachable nodes can be picked, a dash follows the corridors through CLEARED nodes (never past an uncleared one) and any cleared node can
## be dashed back to. Clearing the boss node ends the run. Without a graph (`graph == null`, the hand-built Crypt) the old flat map of live
## groups, chests and loot is used.

## Tuning, all in one place.
const DASH_TIME := 1.0            # seconds from the map click to the party standing at the group (one hop on the node map)
const DASH_HOP_EXTRA := 0.35      # s added per further hop of a long route
const DASH_MAX := 2.5             # s, the longest dash
const DASH_REVISIT_MIN := 0.4     # s, dashing to the node the party already stands at
const ARRIVE_DISTANCE := 6.0      # m from the group's centre, on the side the party came from
const ARRIVE_AT_POINT := 1.2      # m short of a chest or shrine
const COMPANION_SIDE := 2.0       # m the companion stands beside the hero on arrival
const COLLECT_DELAY := 1.4        # s after the last kill before drops are collected (they have to land)
const TRAIL_STEP := 0.04          # s between afterimages during the dash
const TRAIL_LIFE := 0.35
const SUMMON_REACH := 25.0        # m: summoned adds this close and awake belong to the fight
const FROZEN_SAMPLE := 6.0        # s between checks for an awake enemy that is not moving or fighting (a diagnostic, printed)
const STALL_WARNING := 90.0       # s: a fight this long prints one warning with what the party is hitting

const ID_LOOT := 100000           # flat map marker ids: groups use their group_id, loot ID_LOOT + n, chests ID_CHEST + n
const ID_CHEST := 200000

enum State { WAITING, MAP, DASH, FIGHT, COLLECT, DEAD, DONE }

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

# The node map. `graph == null` is the flat Crypt map.
var graph: MapGraph
var current_node: int = 0         # the node the party stands at (the last one it reached)
var node_groups: Dictionary = {}  # node id -> Enemy.group_id
var node_chests: Dictionary = {}  # node id -> Chest
var node_shrines: Dictionary = {} # node id -> object with use_shrine()
var dungeon: Node                 # the MapModeDungeon (anything exposing node_groups / node_chests / node_shrines); found by itself when unset
var run_complete: bool = false
var loot_tally: Dictionary = {"gold": 0, "health": 0, "mana": 0, "items": []}   # what this clear paid (MapDrops): the loot summary card shows it

var _visit_pos: Vector3
var _visit_kind: String = "group"   # group, chest, shrine, revisit (a cleared node), loot
var _visit_ref: Variant
var _visit_node: int = -1
var _kept_target: Dictionary = {}   # member id -> the enemy it keeps attacking
var _stall_warned: bool = false
var _fight_started: float = 0.0
var _last_sample: float = 0.0
var _good_pos: Dictionary = {}      # enemy instance id -> its last position that was on the floor and reachable
var _good_at: float = 0.0
var _sample_pos: Dictionary = {}   # enemy instance id -> where it stood at the last sample
var _route: Array[Vector2] = []     # world (x, z) corridor polyline of the dash
var _dash_time: float = DASH_TIME
var _dash_t: float = 0.0
var _dash_paths: Array = []       # per member: {body, points, lengths, total, offset}
var _trail_clock: float = 0.0
var _collect_clock: float = 0.0
var _labels: Dictionary = {}      # group_id -> label, captured while the group was whole
var _chests: Array = []
var _loot_refs: Array = []
var _hit_logged: bool = false
var _rewards_collected: bool = false   # COLLECT: the drops are in the bag and the summary card is showing
var _summary_up: bool = false
var _fight_level: int = 1              # the level of the group being fought: what its chest and top-up are worth
var _auto_dir: String = ""        # `--mapmode-auto=<dir>`: a developer tool that plays the whole run itself and saves screenshots there
var _shot_n: int = 0
var _auto_started_ms: int = 0

## The flag: opt-in. With `--crypt01` it runs on the hand-built Crypt's flat map, otherwise on the node-map dungeon (main decides by location).
static func requested() -> bool:
	return OS.get_cmdline_user_args().has("--mapmode")

static func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func setup(for_hero: Player, for_companion: Player, for_hud: Hud) -> void:
	hero = for_hero
	companion = for_companion
	hud = for_hud

## Runs on a node map: `groups` node id -> group_id, `chests` node id -> Chest, `shrines` node id -> object with use_shrine(). The dungeon's own
## dictionaries are read automatically; this is for tests and tools that bring their own graph.
func use_graph(g: MapGraph, groups: Dictionary, chests: Dictionary = {}, shrines: Dictionary = {}) -> void:
	graph = g
	node_groups = groups
	node_chests = chests
	node_shrines = shrines
	current_node = g.start_id

func _enter_tree() -> void:
	current = self
	process_physics_priority = 100   # after the bodies have moved, so the dash wins over their own steering

func _exit_tree() -> void:
	if current == self:
		current = null
	if _auto_dir != "" and not run_complete:   # the scene changed under the autoplay (the party fell: the run ends in town): say so, then stop
		print("[mapmode] RUN ENDED EARLY: the scene changed (party dead: %s) after %d fights" % [hero != null and is_instance_valid(hero) and hero.dead, log.fights.size()])
		for line in log.summary_lines():
			print(line)
		if is_inside_tree():
			get_tree().quit()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mapmode-auto="):
			_auto_dir = arg.substr(15)
			DirAccess.make_dir_recursive_absolute(_auto_dir)
			_auto_started_ms = Time.get_ticks_msec()
			_force_1080p()
	for body in [hero, companion]:
		if body != null:
			body.power_activated.connect(func(_id: String, power_id: String) -> void: log.note_power(power_id))

# --- Flow -----------------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hero):
		return
	match state:
		State.WAITING:
			if hud != null and hud.minimap != null and Nav.ready(hero) and _world_ready():
				_open_map()
		State.DASH:
			_tick_dash(delta)
		State.FIGHT:
			_tick_fight()
		State.COLLECT:
			_collect_clock -= delta
			if _collect_clock <= 0.0:
				if not _rewards_collected and _visit_kind != "revisit":
					_rewards_collected = true
					var rows: Array[Dictionary] = HudLootCards.summary_rows(loot_tally, [hero, companion])   # compared before anything is worn
					_collect_rewards()
					_summary_up = _show_loot_summary(rows)
					if _summary_up and _auto_dir != "":
						_shot_later(0.4, "summary")
					if _summary_up:
						_collect_clock = float(MapDrops.T.summary_seconds)
						return
				_rewards_collected = false
				_summary_up = false
				if hud != null:
					hud.loot_cards.hide_summary()
				_open_map()
		State.DEAD:
			if not hero.dead:
				_open_map()

## The world has filled: the dungeon's node map is placed (it is adopted here), or, without one, there are live groups for the flat map.
func _world_ready() -> bool:
	if graph != null:
		return true
	if dungeon == null:
		for n in get_parent().get_children():
			if n != self and "node_groups" in n and "node_chests" in n:
				dungeon = n
	if dungeon != null:
		if (dungeon.node_groups as Dictionary).is_empty():
			return false
		var g: MapGraph = MapGraph.from_layout()
		if g != null:
			use_graph(g, dungeon.node_groups, dungeon.node_chests, dungeon.get("node_shrines") if "node_shrines" in dungeon else {})
			return true
	return not live_groups().is_empty()

func _input(event: InputEvent) -> void:
	if state == State.COLLECT and _summary_up and ((event is InputEventMouseButton and event.pressed) 			or ((event is InputEventKey or event is InputEventJoypadButton) and event.pressed and not event.is_echo())):
		_collect_clock = 0.0   # any click or key closes the loot summary at once
		return
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
	# Stick to one target until it dies (the nearest one changes as everybody moves, and the party would flap between them).
	var kept: Actor = _kept_target.get(body.member_id) as Actor if _kept_target.has(body.member_id) else null
	if is_instance_valid(kept) and not kept.dead and kept.is_in_group("enemies"):
		return kept
	var best: Actor = null
	var best_clear: bool = false
	for enemy in fight_enemies():
		var clear: bool = Nav.line_clear(body, enemy.global_position)   # a target behind a wall is the last choice
		if best == null or (clear and not best_clear) or (clear == best_clear and enemy.flat_distance_to(body) < best.flat_distance_to(body)):
			best = enemy
			best_clear = clear
	_kept_target[body.member_id] = best
	return best

## Everything that is part of the fight: the chosen group's living members, plus summoned adds (they have no group) that are awake close by.
func fight_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = group_members()
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and e.group_id < 0 and e.is_aggro() and e.flat_distance_to(hero) <= SUMMON_REACH:
			out.append(e)
	return out

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

## The markers the map shows now. Node map: every node that is not hidden, with its state. Flat map: live groups, unopened chests, loot on the ground.
func markers() -> Array:
	if graph != null:
		return _graph_markers()
	var out: Array = []
	var groups: Dictionary = live_groups()
	for id in groups:
		var members: Array = groups[id]
		if not _labels.has(id):
			_labels[id] = group_label(members)
		out.append({"id": int(id), "pos": centre_of(members), "kind": "group", "state": "reachable", "strength": members.size(), "label": String(_labels[id])})
	_chests.clear()
	for node in get_tree().get_nodes_in_group("chests"):
		var chest := node as Chest
		if chest != null and not chest.opened:
			_chests.append(chest)
			out.append({"id": ID_CHEST + _chests.size() - 1, "pos": chest.global_position, "kind": "chest", "state": "reachable", "strength": 1, "label": "Chest"})
	_loot_refs.clear()
	for node in get_tree().get_nodes_in_group("loot"):
		var drop := node as LootDrop
		if drop != null and not drop.is_queued_for_deletion():
			_loot_refs.append(drop)
			out.append({"id": ID_LOOT + _loot_refs.size() - 1, "pos": drop.global_position, "kind": "loot", "state": "reachable", "strength": 1, "label": "%s (inventory full)" % String(drop.item.get("name", "Item"))})
	return out

func _graph_markers() -> Array:
	var out: Array = []
	for id in graph.ids():
		var st: String = graph.state_of(int(id))
		if st == "hidden":
			continue
		var row: Dictionary = graph.row(int(id))
		var p: Vector2 = graph.pos_of(int(id))
		var kind: String = String(row.get("kind", "pack"))
		out.append({"id": int(id), "pos": Vector3(p.x, 0.0, p.y), "kind": kind, "state": st, "strength": _strength_of(row),
			"label": node_label(int(id)) if st != "beyond" else "", "guard": String(plan_of(int(id)).get("guard", "")) if st == "reachable" else ""})
	return out

static func _strength_of(row: Dictionary) -> int:
	var total: int = 0
	for g in row.get("groups", []):
		total += int(g[1])
	return maxi(total, 1)

## The tooltip of a node: its name, then (for a node not yet cleared) the monster count and kinds, the champion and what it guards.
func node_label(id: int) -> String:
	var row: Dictionary = graph.row(id)
	var title: String = String(row.get("name", String(row.get("kind", "node")).capitalize()))
	if graph.is_cleared(id):
		return "%s\nCleared" % title
	var lines: PackedStringArray = [title]
	var parts: PackedStringArray = []
	for g in row.get("groups", []):
		parts.append("%d %s" % [int(g[1]), String(g[0]).replace("_", " ")])
	if not parts.is_empty():
		lines.append(", ".join(parts))
	var champion: String = String(row.get("champion", ""))
	if champion != "":
		lines.append("Champion: %s" % champion)
	var plan: Dictionary = plan_of(id)
	match String(row.get("kind", "")):
		"chest":
			lines.append(String(plan.get("title", "A chest")))
		"shrine":
			lines.append("A shrine")
		"boss":
			lines.append("Guards: %s" % String(plan.get("title", "the way out")))
			lines.append("The way out")
		_:
			lines.append("Guards: %s" % String(plan.get("title", "gold")))
	return "\n".join(lines)

## What a node guards: the dungeon's plan (decided when its groups spawned) or, for a graph without a dungeon, the same rule on the same seed.
func plan_of(id: int) -> Dictionary:
	if dungeon != null and "node_plans" in dungeon and (dungeon.node_plans as Dictionary).has(id):
		return dungeon.node_plans[id]
	return MapDrops.plan_for(graph.row(id)) if graph != null and graph.has_node(id) else {}

func _ensure_overlay() -> void:
	if overlay == null:
		overlay = MapModeOverlay.new()
		overlay.selected.connect(select_marker)
		hud.add_child(overlay)
		hud.minimap.map_data.ensure_built(get_tree())
		overlay.map_data = hud.minimap.map_data
	if graph != null:
		overlay.set_links(graph.link_rows())
		overlay.set_frame(graph.bounds())

func _open_map() -> void:
	focus = null
	if graph != null:
		if graph.boss_cleared() and not run_complete:
			_finish_run()
			return
		_ensure_overlay()
		state = State.MAP
		var at: Vector2 = graph.pos_of(current_node)
		overlay.open(markers(), Vector3(at.x, 0.0, at.y), false)
		if _auto_dir != "":
			_auto_pick()
		return
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

## The boss is down: the run is over. The fight log summary is printed and a banner says so.
func _finish_run() -> void:
	run_complete = true
	state = State.DONE
	for line in log.summary_lines():
		print(line)
	print("Run complete: %d of %d nodes cleared" % [graph.cleared.size(), graph.nodes.size()])
	hero.say_banner("Run complete")
	if _auto_dir != "":
		await get_tree().create_timer(1.5).timeout
		await _shot("run_complete")
		get_tree().quit()

## The developer autoplay: shoot the map, pick the nearest marker, shoot the dash and the fight, fire a power, repeat until nothing is left.
func _auto_pick() -> void:
	await get_tree().create_timer(0.8).timeout
	var best: Dictionary = {}
	var best_hops: int = 1 << 30
	var hops: Dictionary = _hops_to_boss()
	for m in markers():
		if String(m.get("state", "reachable")) != "reachable":
			continue
		var h: int = int(hops.get(int(m["id"]), 0))
		if String(m.get("kind", "")) == "shrine" and hero.health < hero.max_health * 0.6:
			h = -1   # hurt: take the shrine first
		elif String(m.get("kind", "")) == "chest":
			h = -2   # gear first: the chests are on dead-end spurs and worth the detour
		if best.is_empty() or h < best_hops or (h == best_hops and hero.global_position.distance_to(m["pos"]) < hero.global_position.distance_to(best["pos"])):
			best = m
			best_hops = h
	if best.is_empty():
		return
	overlay._focus = int(best["id"])   # the tooltip of the node about to be picked is in the map shot (what it guards)
	overlay._focus_shown = true
	overlay.queue_redraw()
	await _shot("map")
	select_marker(int(best["id"]))
	await get_tree().create_timer(0.45).timeout
	await _shot("dash")
	await _wait_fight()
	if state == State.FIGHT:
		await get_tree().create_timer(1.5).timeout
		await _shot("fight")
		while state == State.FIGHT:   # powers on whatever the hero is hitting, once a second
			for i in MapAutoPowers.fire(hero, companion, hero.attack_target):
				log.note_power("auto")
			if hero.health < hero.max_health * 0.5 and hero.stats.potions > 0:
				Input.action_press("use_potion")
				await get_tree().create_timer(0.1).timeout
				Input.action_release("use_potion")
			await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(1.0).timeout
	if Time.get_ticks_msec() - _auto_started_ms > 900000:
		for line in log.summary_lines():
			print(line)
		get_tree().quit()

## Autoplay only: the dev harness sizes the window 1280x720; the screenshots must be 1920x1080 on the second monitor.
func _force_1080p() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.get_screen_count() > 1:
		DisplayServer.window_set_current_screen(1)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_position(DisplayServer.screen_get_position(DisplayServer.window_get_current_screen()) + Vector2i(0, 40))

## Autoplay only: the cost of the cheapest way from each node to the boss over the graph (one per hop, a swarm costs extra: a level-1 party
## routes around it, as a player would). Plain Bellman-Ford; the graph is small.
func _hops_to_boss() -> Dictionary:
	var out: Dictionary = {}
	if graph == null or graph.boss_id < 0:
		return out
	out[graph.boss_id] = 0
	var changed: bool = true
	while changed:
		changed = false
		for id in graph.ids():
			for n in graph.neighbours(int(id)):
				if out.has(int(n)):
					var cost: int = int(out[int(n)]) + 1 + (8 if graph.kind_of(int(id)) == "swarm" else 0)
					if not out.has(int(id)) or cost < int(out[int(id)]):
						out[int(id)] = cost
						changed = true
	return out

func _wait_fight() -> void:
	while state == State.DASH:
		await get_tree().physics_frame

func _shot_later(delay: float, label: String) -> void:
	await get_tree().create_timer(delay).timeout
	await _shot(label)

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot_n += 1
	var img: Image = get_viewport().get_texture().get_image()
	if _shot_n == 1:
		print("[mapmode] screenshot size ", img.get_size())
	img.save_png("%s/%02d_%s.png" % [_auto_dir, _shot_n, label])

func _leftover_markers() -> Array:
	return markers().filter(func(m: Dictionary) -> bool: return m["kind"] != "group")

## The map click.
func select_marker(id: int) -> void:
	if state != State.MAP:
		return
	if graph != null:
		_select_node(id)
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
	_visit_node = -1
	group_id = id if _visit_kind == "group" else -1
	_visit_ref = null
	if _visit_kind == "chest":
		_visit_ref = _chests[id - ID_CHEST]
	elif _visit_kind == "loot":
		_visit_ref = _loot_refs[id - ID_LOOT]
	overlay.close()
	_hit_logged = false
	_reset_tally()
	log.begin_fight(String(picked["label"]), now())
	_start_dash()

## A click on a node of the node map: nothing unless it is cleared or reachable and a legal route (through cleared nodes only) leads there.
func _select_node(id: int) -> void:
	if not graph.is_clickable(id):
		return
	var nodes_on_route: Array = graph.route_nodes(current_node, id)
	_route = graph.route(current_node, id)
	if nodes_on_route.is_empty() or _route.is_empty():
		return
	var row: Dictionary = graph.row(id)
	var p: Vector2 = graph.pos_of(id)
	_visit_node = id
	_visit_pos = Vector3(p.x, hero.global_position.y, p.y)
	_visit_ref = null
	group_id = -1
	var hops: int = nodes_on_route.size() - 1
	_dash_time = clampf(DASH_TIME + DASH_HOP_EXTRA * float(hops - 1), DASH_TIME, DASH_MAX) if hops > 0 else DASH_REVISIT_MIN
	if graph.is_cleared(id):
		_visit_kind = "revisit"
	else:
		match String(row.get("kind", "pack")):
			"chest":
				_visit_kind = "chest"
				_visit_ref = node_chests.get(id)
			"shrine":
				_visit_kind = "shrine"
				_visit_ref = node_shrines.get(id)
			_:
				_visit_kind = "group"
				group_id = int(node_groups.get(id, -1))
	overlay.close()
	_hit_logged = false
	_reset_tally()
	if _visit_kind != "revisit":
		log.begin_fight(String(row.get("name", "node")), now())
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

## The corridor of the route as world points, cut `short` metres before the end (the party stops short of a group, a chest, a shrine).
static func trim_route(route: Array[Vector2], short: float) -> Array[Vector2]:
	var out: Array[Vector2] = route.duplicate()
	var left: float = short
	while out.size() > 1 and left > 0.0:
		var seg: float = out[out.size() - 2].distance_to(out[out.size() - 1])
		if seg > left + 0.01:
			out[out.size() - 1] = out[out.size() - 1].move_toward(out[out.size() - 2], left)
			break
		left -= seg
		out.remove_at(out.size() - 1)
	return out

## Where the party's dash goes: through the corridor polyline (node map) or straight to the arrival spot (flat map).
func _goals_for(body_index: int) -> Array[Vector3]:
	var goals: Array[Vector3] = []
	if graph == null:
		var spot: Vector3 = arrival_spot()
		var side: Vector3 = (spot - hero.global_position).cross(Vector3.UP).normalized() * COMPANION_SIDE
		goals.append(spot if body_index == 0 else Nav.snap(companion, spot + side))
		return goals
	var short: float = ARRIVE_DISTANCE if _visit_kind == "group" else (ARRIVE_AT_POINT if _visit_kind in ["chest", "shrine"] else 0.0)
	var pts: Array[Vector2] = trim_route(_route, short)
	var y: float = hero.global_position.y
	for p in pts:
		goals.append(Nav.snap(hero, Vector3(p.x, y, p.y)))
	if body_index == 1 and goals.size() >= 1:
		var last: Vector3 = goals[goals.size() - 1]
		var before: Vector3 = goals[goals.size() - 2] if goals.size() >= 2 else hero.global_position
		var dir: Vector3 = (last - before)
		dir.y = 0.0
		var side: Vector3 = dir.normalized().cross(Vector3.UP) * COMPANION_SIDE if dir.length() > 0.05 else Vector3.RIGHT * COMPANION_SIDE
		goals[goals.size() - 1] = Nav.snap(companion, last + side)
	return goals

func _start_dash() -> void:
	state = State.DASH
	_dash_t = 0.0
	_trail_clock = 0.0
	_dash_paths.clear()
	if graph == null:
		_dash_time = DASH_TIME
	var bodies: Array = [hero, companion]
	for i in 2:
		var body: Player = bodies[i]
		if body == null or body.dead:
			continue
		body.movement.has_goal = false
		body.attack_target = null
		body.skills.clear_queue()
		var pts := PackedVector3Array()
		var from: Vector3 = body.global_position
		pts.append(from)
		for goal in _goals_for(i):
			var leg: PackedVector3Array = NavigationServer3D.map_get_path(Nav.map_of(body), from, goal, true)
			if leg.size() < 2:
				leg = PackedVector3Array([from, goal])
			for k in range(1, leg.size()):
				pts.append(leg[k])
			from = goal
		var total: float = 0.0
		var lengths: PackedFloat32Array = PackedFloat32Array([0.0])
		for k in range(1, pts.size()):
			total += pts[k - 1].distance_to(pts[k])
			lengths.append(total)
		_dash_paths.append({"body": body, "points": pts, "lengths": lengths, "total": total})

func _tick_dash(delta: float) -> void:
	_dash_t += delta
	var t: float = clampf(_dash_t / _dash_time, 0.0, 1.0)
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
			_fight_started = now()
			_stall_warned = false
			_last_sample = now()
			_sample_pos.clear()
			_kept_target.clear()
			MapModeRules.note_fight_start(now())
			_fight_level = 1
			for e in group_members():   # only this group: neighbouring groups stay asleep
				_fight_level = maxi(_fight_level, e.level)
				e.alert_delay = 0.0
				e.wake()
		"chest":
			if is_instance_valid(_visit_ref):
				(_visit_ref as Chest).open()
			_begin_collect()
		"shrine":
			if _visit_ref != null and is_instance_valid(_visit_ref) and _visit_ref.has_method("use_shrine"):
				_visit_ref.call("use_shrine")
			_begin_collect()
		_:
			_begin_collect()

# --- Fight ---------------------------------------------------------------------------------------------------------------------------

func _tick_fight() -> void:
	if hero.dead:
		log.end_fight(now())
		state = State.DEAD
		return
	if fight_enemies().is_empty():
		_begin_collect()
		return
	hero.attack_target = target_for(hero)
	_keep_enemies_inside()
	if now() - _last_sample >= FROZEN_SAMPLE:
		_sample_frozen()
	if not _stall_warned and now() - _fight_started > STALL_WARNING:
		_stall_warned = true
		var t: Actor = hero.attack_target
		print("[mapmode] STALL: fight over %.0f s; hero target %s (%s hp, %s)" % [STALL_WARNING, t, t.health if t != null else "-", "champion" if t is Enemy and (t as Enemy).champion != null else "plain"])

## A knockback (the area powers) can throw an enemy through a wall into rock or a neighbouring room, where nobody can reach it and the fight never
## ends. Every quarter second each enemy of the fight is checked: one that left the floor, or jumped a long way with a wall between, goes back to
## where it last stood properly.
func _keep_enemies_inside() -> void:
	if now() - _good_at < 0.25:
		return
	_good_at = now()
	for e in fight_enemies():
		var id: int = e.get_instance_id()
		var here: Vector3 = e.global_position
		var snapped: Vector3 = Nav.snap(e, here)
		var off_floor: bool = Vector2(snapped.x - here.x, snapped.z - here.z).length() > 0.9
		var jumped: bool = false
		if _good_pos.has(id):
			var prev: Vector3 = _good_pos[id]
			jumped = prev.distance_to(here) > 2.5 and not e.behavior.is_attacking() and not Nav.sight_clear(e, prev, here)
			if off_floor or jumped:
				e.global_position = prev
				e.velocity = Vector3.ZERO
				print("[mapmode] enemy knocked through a wall, put back: %s" % e.variant)
				continue
		if not off_floor:
			_good_pos[id] = here

## Diagnostic: an awake enemy of the fight that has not moved since the last sample and is not next to anyone to hit is printed with its state,
## so a "frozen" enemy can be told apart (dormant, still asleep, stunned, ranged and holding, or stuck behind something).
func _sample_frozen() -> void:
	_last_sample = now()
	for e in fight_enemies():
		var id: int = e.get_instance_id()
		var was: Vector3 = _sample_pos.get(id, Vector3(INF, 0, INF))
		_sample_pos[id] = e.global_position
		var near: float = minf(e.flat_distance_to(hero), e.flat_distance_to(companion) if is_instance_valid(companion) else INF)
		if was.x != INF and e.global_position.distance_to(was) < 0.3 and near > 3.0:
			print("[mapmode] FROZEN? %s group %d aggro=%s dormant=%s stun=%.1f dist=%.1f line=%s champion=%s busy=%s" % [e.variant, e.group_id, e.is_aggro(),
				e.dormant, e.stun_time, near, Nav.line_clear(e, hero.global_position), e.champion != null, e.behavior.is_attacking()]
				+ " | state=%s active=%s timer=%s cool=%s attacking=%s alert=%.1f fear=%.1f snare=%s" % [e.behavior.get("_state"), e.behavior.get("_active"), e.behavior.get("_timer"),
				e.behavior.get("_pounce_cool"), e._attacking, e.alert_delay, e.fear_time, e.get("snare_time")])

func _begin_collect() -> void:
	MapModeRules.note_fight_end()
	if _visit_kind == "group":
		_settle_guard()   # the chest opens (loot spray), the shrine blesses, the cache spills: before the log row closes, so its loot is counted
	if _visit_kind not in ["revisit", "loot"]:
		_top_up()
	var row: Dictionary = log.end_fight(now())
	if not row.is_empty():
		log.emit_line(row)
	focus = null
	hero.attack_target = null
	if graph != null and _visit_node >= 0:
		graph.mark_cleared(_visit_node)   # a group is cleared, a chest opened, a shrine used: the nodes behind it come into view
		current_node = _visit_node
	if _auto_dir != "":
		_shot("clear")
		_shot_later(0.8, "chest_open")
	state = State.COLLECT
	_collect_clock = COLLECT_DELAY if _visit_kind not in ["loot", "revisit"] else 0.1

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

# --- Drops (MapDrops): the guard of a cleared group, the top-up, the loot summary ------------------------------------------------------------

func _reset_tally() -> void:
	loot_tally = {"gold": 0, "health": 0, "mana": 0, "items": []}

## Called by the director and the chests for everything this clear drops.
func note_item(item: Dictionary) -> void:
	(loot_tally["items"] as Array).append(item)
	log.note_item(item)

func note_pickup(kind: String, amount: int = 0) -> void:
	match kind:
		"gold":
			loot_tally["gold"] = int(loot_tally["gold"]) + amount
			log.note_gold(amount)
		"health":
			loot_tally["health"] = int(loot_tally["health"]) + 1
		"mana":
			loot_tally["mana"] = int(loot_tally["mana"]) + 1

## A cleared group gives up what it guarded: a chest opens by itself (lid and spray, then the auto-collect takes it), a shrine blesses the party,
## gold and a potion cache spill. On the node map only (the plan is per node).
func _settle_guard() -> void:
	if graph == null or _visit_node < 0:
		return
	var plan: Dictionary = plan_of(_visit_node)
	match String(plan.get("guard", "")):
		"":
			return
		"shrine":
			MapDrops.bless([hero, companion])
			hero.say_banner(String(MapDrops.T.shrine_buff.title))
		"gold":
			_spawn_orb("gold", MapDrops.gold_for(_fight_level, MapDrops.T.gold_pile, _gold_find()))
		"potions":
			for i in int(MapDrops.T.potion_cache):
				_spawn_orb("health", 0)
		_:
			var chest: Chest = node_chests.get(_visit_node) as Chest
			if chest == null or not is_instance_valid(chest):
				chest = Chest.create(String(plan["guard"]), _fight_level)
				get_tree().current_scene.add_child(chest)
				chest.global_position = Vector3(graph.pos_of(_visit_node).x, 0.0, graph.pos_of(_visit_node).y)
				node_chests[_visit_node] = chest
			if _auto_dir != "":
				var cam: Camera3D = get_viewport().get_camera_3d()
				print("[mapmode] chest %s at %s hero %s screen %s" % [plan["guard"], chest.global_position, hero.global_position, cam.unproject_position(chest.global_position)])
			chest.open()

## Every cleared node pays at least gold, and an item or a potion: what the fight and the guard did not give is added.
func _top_up() -> void:
	if int(loot_tally["gold"]) <= 0:
		_spawn_orb("gold", MapDrops.gold_for(_fight_level, MapDrops.T.clear_gold, _gold_find()))
	if (loot_tally["items"] as Array).is_empty() and int(loot_tally["health"]) + int(loot_tally["mana"]) <= 0:
		for i in int(MapDrops.T.clear_potion):
			_spawn_orb("health", 0)

func _gold_find() -> float:
	return float(PartyManager.current().loot_bonuses().gold_find)

## A gold or potion pickup beside the hero; the auto-collect flies it in.
func _spawn_orb(kind: String, amount: int) -> void:
	var orb := HealthOrb.new()
	orb.is_potion = kind == "health"
	orb.gold_amount = amount if kind == "gold" else 0
	get_tree().current_scene.add_child(orb)
	orb.global_position = hero.global_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	note_pickup(kind, orb.gold_amount)

func _show_loot_summary(rows: Array[Dictionary]) -> bool:
	if hud == null or _visit_kind == "revisit":
		return false
	var title: String = String(graph.row(_visit_node).get("name", "Cleared")) if graph != null and _visit_node >= 0 else "Cleared"
	hud.loot_cards.show_summary(title, loot_tally, rows, float(MapDrops.T.summary_seconds))
	return true

