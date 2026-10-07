class_name TownScene
extends Node3D
## The whole world: a small walled plaza (the north gate, the healing stone, the trader's stall, the job board, a stash and a handful of
## townspeople who live their own lives, see TownSim) with the Crypt Road laid end to end beyond its gate, all loaded at once, monsters
## included. Walk out of the gate whenever you like; nothing loads and nothing has to be accepted. The board's quests are always active;
## when one is met out there, Warden Hale has a reward for you when you come back. Walk up to someone or something and click it, or press
## the interact button, to open its panel.

const HALF := 22.0
const LAYOUT_PATH := "res://game/town/town_layout.tscn"
const SPOT_LABELS := {"stone": "Rest at the healing stone", "board": "Read the job board",
	"stash": "Open the stash"}
const GATE_HALF_WIDTH := 4.5   # half the opening in the north palisade (the palisade halves start at 4.5 m)
const INTERACT_RANGE := 3.4
const TAG_RANGE := 8.0
const BARK_RANGE := 16.0

var town_gate: Node3D
var arena: Arena
var layout: Node3D                        # the town_layout.tscn instance (its Props are gone once placed)
var stations: Dictionary = {}             # name -> position, from the layout's Stations markers: where people go (see TownStage)
var player: Player
var rig: CameraRig
var sim: TownSim
var stage: TownStage
var hud: TownHud
var panel: TownPanel
var pause_menu: PauseMenu
var npcs: Dictionary = {}                 # id -> TownNpc
var spots: Array[Dictionary] = []         # {key, kind, id, pos, label}: everything you can walk up to and use
var world_environment: Environment
var pending: String = ""                  # key of the spot the hero was sent to by a click
var near: Dictionary = {}                 # the spot the hero is standing at (empty when none)
## The far end of the world. Tests that only need the plaza turn the road off before adding the scene (it takes a few seconds to build).
var with_road: bool = true
var crypt: CryptRoad
var director: RunDirector
var combat_hud: Hud
var outside: bool = false                 # the hero is out beyond the town (an expedition: the clan has eaten, the loot is not yet stashed)
var _world_nav: NavigationRegion3D        # one navigation mesh for the plaza and the road
var _base_ambient: float = 0.7
var _base_fog: float = 0.012
var _announced_road: bool = false
var _monster_clock: float = 0.0
var _gossip_clock: float = 4.0

func _exit_tree() -> void:
	TownState.flush_progression(true)   # leaving the world: nothing earned is left waiting for the disk

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		TownState.flush_progression(true)

func _ready() -> void:
	var built_at: int = Time.get_ticks_msec()
	get_tree().paused = false
	GameSettings.boot()
	if TownState.npcs.is_empty():
		TownState.load_or_start()
	sim = TownSim.new()
	stage = TownStage.new(self)
	_build_world()
	_build_town()
	if with_road:
		_build_road()
	arena.bake_navigation()   # once, for the plaza and the road together
	player = Player.new()
	add_child(player)
	player.position = Vector3(0, 0, 10.0)
	player.visual.rotation.y = PI   # facing north, toward the gate
	_apply_run_gear(player)
	rig = CameraRig.new()
	rig.fog_env = world_environment
	rig.offset = Vector3(0.0, 9.0, 6.5)
	add_child(rig)
	rig.target = player
	rig.global_position = player.global_position
	rig.set_zoom_now(2.6)   # the plaza is small: closer than a run's opening view
	_build_ui()
	if with_road:
		_start_director()
	_welcome_back()
	_refresh_reward_marker()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	HeroProgression.logging = args.has("--xplog")   # developer only: print why XP is paid
	TownState.apply_dev_progression.call_deferred(args)   # --level=N / --xp=N (developer only), once the HUD is listening
	if args.has("--timing"):
		print("[world] plaza and road built in %d ms" % (Time.get_ticks_msec() - built_at))
	if args.has("--townshot"):
		_screenshot(args)

## The gear the hero wears this run: whatever the town holds, over the starting kit.
static func _apply_run_gear(hero: Player) -> void:
	for item in TownState.gear.values():
		hero.stats.equip(item, false)
	hero.stats.potions = TownState.potions

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.045, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.45, 0.55)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.09, 0.09, 0.11)
	environment.fog_density = 0.012
	_base_ambient = environment.ambient_light_energy
	_base_fog = environment.fog_density
	SceneLook.give_reflections(environment)
	env.environment = environment
	world_environment = environment
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-52, -30, 0)
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 0.8
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 42.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(moon)

## The static town (buildings, walls, lamps, props, the spots you use and the places people go) is the scene town_layout.tscn, edited
## in Godot: TownProp markers under Props, Marker3Ds under Spots and Stations. This builds the ground, hands each prop to the arena
## (collision, light, navigation), then the glow, the people and the interactions. Metres, north is -z.
func _build_town() -> void:
	_world_nav = NavigationRegion3D.new()
	add_child(_world_nav)
	arena = Arena.new()
	arena.half = HALF
	arena.scatter = false
	arena.build_perimeter_walls = false
	arena.shared_region = _world_nav
	add_child(arena)
	arena.build(false)
	_build_boundary()
	_place_layout()
	# The healing stone glows like embers.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 2.4
	glow.omni_range = 8.0
	glow.position = Vector3(0, 1.3, -2.0)
	add_child(glow)
	glow.add_child(FlickerLight.new())

	for key in SPOT_LABELS:
		var marker: Marker3D = layout.get_node("Spots/" + key)
		_register(key, key, "", marker.position, SPOT_LABELS[key])
	for id in TownDb.sorted_ids(TownDb.npcs()):
		var def: NpcDef = TownDb.npc(id)
		var npc: TownNpc = TownNpc.create(def)
		add_child(npc)
		npc.position = Vector3(def.home.x, 0, def.home.y)
		npc.rotation.y = atan2(-def.home.x, -def.home.y - 1.0)   # toward the middle of the plaza
		npcs[id] = npc
		npc.home = npc.position
		_register("npc:" + id, "npc", id, npc.position, "Talk to %s" % def.display_name)

## Solid walls on three sides and on the north side either side of a real opening (GATE_HALF_WIDTH wide on each side of the middle).
## Beyond the opening is the road (or, with the road off, a backstop that stops anything walking off the ground).
func _place_layout() -> void:
	layout = (load(LAYOUT_PATH) as PackedScene).instantiate()
	add_child(layout)
	var props: Node = layout.get_node("Props")
	for node in props.get_children():
		var prop := node as TownProp
		if prop != null and ResourceLoader.exists(Arena.PROP_DIR + prop.model_name + "/model.glb"):
			if prop.model_name == "town_gate":
				town_gate = preload("res://game/town/town_gate.gd").new()
				town_gate.position = prop.position
				add_child(town_gate)
			else:
				arena.place_prop(prop.model_name, prop.position, prop.rotation.y, prop.height, prop.collides, prop.lit)
	props.queue_free()   # the markers have done their job
	for marker in layout.get_node("Stations").get_children():
		stations[String(marker.name)] = (marker as Marker3D).position

func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	var rows: Array = [   # centre x, centre z, size x, size z
		[0.0, HALF + 0.5, HALF * 2.0, 1.0],
		[HALF + 0.5, 0.0, 1.0, HALF * 2.0],
		[-HALF - 0.5, 0.0, 1.0, HALF * 2.0],
	]
	var north_len: float = HALF - GATE_HALF_WIDTH
	for side in [-1.0, 1.0]:
		rows.append([side * (GATE_HALF_WIDTH + north_len * 0.5), -HALF - 0.5, north_len, 1.0])
	if not with_road:
		rows.append([0.0, -HALF - 3.0, GATE_HALF_WIDTH * 2.0 + 2.0, 1.0])   # backstop: nothing beyond the gate to walk onto
	for row in rows:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(row[2], 8.0, row[3])
		shape.shape = box
		shape.position = Vector3(row[0], 4.0, row[1])
		body.add_child(shape)
	arena.add_child(body)
	# Monsters never enter town (yet): a ward across the opening on the player's layer, which enemies collide with and the hero does not.
	var ward := StaticBody3D.new()
	ward.collision_layer = Actor.LAYER_PLAYER
	ward.collision_mask = 0
	var ward_shape := CollisionShape3D.new()
	var ward_box := BoxShape3D.new()
	ward_box.size = Vector3(GATE_HALF_WIDTH * 2.0, 8.0, 0.5)
	ward_shape.shape = ward_box
	ward_shape.position = Vector3(0, 4.0, -HALF - 0.25)
	ward.add_child(ward_shape)
	arena.add_child(ward)

func _register(key: String, kind: String, id: String, pos: Vector3, label: String) -> void:
	spots.append({"key": key, "kind": kind, "id": id, "pos": pos, "label": label})

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	combat_hud = Hud.new()   # bars, hotbar and map: the hero can fight anywhere now, the plaza included
	combat_hud.player = player
	combat_hud.arena = arena
	combat_hud.top_offset = 54.0   # the plaza's resource bar sits above its quest line
	combat_hud.force_window = with_road
	combat_hud.world_mode = true   # a fallen hero is dragged home: no restart prompt
	combat_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(combat_hud)
	hud = TownHud.new()
	layer.add_child(hud)
	panel = TownPanel.new()
	panel.town = self
	layer.add_child(panel)
	pause_menu = PauseMenu.new()
	pause_menu.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	pause_menu.main_menu_requested.connect(func() -> void: get_tree().change_scene_to_file("res://game/menu.tscn"))
	layer.add_child(pause_menu)

## Back from a run: say so, and let the keeper and the trader react.
func _welcome_back() -> void:
	var result: Dictionary = TownState.last_run
	if result.is_empty():
		hud.show_banner("The Last Hearth")
		return
	TownState.last_run = {}
	TownState.save()   # the result is told once: the save must not still hold it
	var died: bool = bool(result.get("died", false))
	var line: String = "You are back. +%dg" % int(result.get("gold", 0))
	if bool(result.get("completed", false)):
		line = "Job done. +%dg" % int(result.get("gold", 0))
	elif bool(result.get("abandoned", false)):
		line = "The last run was cut short. Nothing earned, nothing lost."
	elif died:
		line = "You were dragged back. +%dg" % int(result.get("gold", 0))
	hud.show_banner(line, 4.0)
	var key: String = "return_dead" if died else "return_ok"
	for id in ["hale", "marlow"]:
		if npcs.has(id):
			(npcs[id] as TownNpc).say(sim.line_for(id, key))

# --- Frame ---------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	TownState.potions = player.stats.potions
	sim.tick(delta)
	_tick_quests(delta)
	_show_barks()
	_update_near()
	_update_tags()
	var focus: Dictionary = near if Gamepad.active else pick_spot(get_viewport().get_mouse_position())
	if combat_hud.show_gear or player.mouse_over_ui(get_viewport().get_mouse_position()):
		focus = {}
	hud.prompt = ""
	if not panel.is_open() and not focus.is_empty():
		var anchor: Vector3 = focus["pos"] + Vector3(0, 2.6, 0)
		if focus["kind"] == "npc":
			var def: NpcDef = TownDb.npc(focus["id"])
			hud.prompt = "%s  -  %s" % [def.display_name, def.title]
		else:
			hud.prompt = focus["label"]
		hud.prompt_position = rig.get_viewport().get_camera_3d().unproject_position(anchor)
	if town_gate != null:
		town_gate.set_open(absf(player.position.x) < 8.0 and absf(player.position.z - town_gate.position.z) < 11.0)
	_update_feed()
	_update_world(delta)
	if not pending.is_empty() and not panel.is_open():
		var spot: Dictionary = _spot(pending)
		if spot.is_empty() or _flat_distance(spot) <= INTERACT_RANGE:
			pending = ""
			if not spot.is_empty():
				interact(spot)

func _flat_distance(spot: Dictionary) -> float:
	var offset: Vector3 = player.global_position - (spot["pos"] as Vector3)
	offset.y = 0.0
	return offset.length()

func _spot(key: String) -> Dictionary:
	for spot in spots:
		if spot["key"] == key:
			return spot
	return {}

func _update_near() -> void:
	near = {}
	var best: float = INTERACT_RANGE
	for spot in spots:
		var d: float = _flat_distance(spot)
		if d <= best:
			best = d
			near = spot

func _update_tags() -> void:
	for id in npcs:
		var npc: TownNpc = npcs[id]
		var d: float = player.global_position.distance_to(npc.global_position)
		npc.set_tag_visible(d <= TAG_RANGE and String(pick_spot(get_viewport().get_mouse_position()).get("id", "")) != id)

func _show_barks() -> void:
	while not sim.barks.is_empty():
		stage.handle(sim.barks.pop_front())
	stage.update(get_process_delta_time())
	for id in npcs:   # people who have walked off are found where they are now
		var spot: Dictionary = _spot("npc:" + id)
		if not spot.is_empty():
			spot["pos"] = (npcs[id] as TownNpc).position

func _update_feed() -> void:
	var count: int = sim.history.size()
	var feed: Array[String] = []
	for i in range(maxi(count - 3, 0), count):
		feed.append(sim.history[i])
	hud.feed = feed

# --- Interaction ---------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if panel.is_open() or combat_hud.show_gear:
		return
	if event.is_action_pressed("pause") and not pause_menu.is_open():
		pause_menu.open()
		return
	if pause_menu.is_open():
		return
	if event.is_action_pressed("chronicle"):
		panel.open_chronicle()
		return
	if event.is_action_pressed("interact") and not near.is_empty():
		interact(near)
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		var picked: Dictionary = pick_spot(click.position)
		pending = String(picked["key"]) if not picked.is_empty() else ""

## The spot under a screen point (a head, a board, a chest), by its position on screen.
func pick_spot(screen_point: Vector2) -> Dictionary:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var best: Dictionary = {}
	var best_d: float = 70.0
	for spot in spots:
		var anchor: Vector3 = (spot["pos"] as Vector3) + Vector3(0, 1.1, 0)
		if camera.is_position_behind(anchor):
			continue
		var d: float = camera.unproject_position(anchor).distance_to(screen_point)
		if d < best_d:
			best_d = d
			best = spot
	return best

func interact(spot: Dictionary) -> void:
	match spot["kind"]:
		"npc":
			var npc: TownNpc = npcs[spot["id"]]
			npc.face_toward(player.global_position)
			panel.open_npc(spot["id"])
		"board":
			panel.open_board()
		"stash":
			panel.open_stash()
		"stone":
			player.health = player.max_health
			hud.show_banner("The stone is warm. You feel whole.", 2.5)
		"waystone":
			_use_return_waystone()

func _use_return_waystone() -> void:
	if not outside or player == null or player.dead:
		return
	if crypt != null and crypt.return_waystone != null:
		if not crypt.return_waystone.can_interact():
			return
		crypt.return_waystone.mark_used()
	hud.show_banner("The waystone hums with warmth. Returning to Last Hearth...", 2.5)
	player.global_position = Vector3(0.0, 0.0, 8.0)
	player.visual.rotation.y = PI
	player.reset_physics_interpolation()
	player.velocity = Vector3.ZERO
	player.attack_target = null
	player.attack_prop = null
	player.movement.has_goal = false
	rig.global_position = player.global_position
	rig.set_zoom_now(2.6)
	outside = false
	_arrive_in_town()
	if TownState.has_reward():
		hud.show_banner("Forecourt secured — the road is cleansed.\nWarden Hale has your reward", 4.0)
	else:
		hud.show_banner("Returned safely to Last Hearth", 3.0)
	if crypt != null and crypt.return_waystone != null:
		crypt.return_waystone.reset_used()

## The one way gear changes in town: what is worn is recorded in TownState and put on the hero standing here, so the weapon in his
## hand (and his armour) is what the shop or stash just gave him. Returns what was worn in that slot before, or null.
func equip_town_item(item: Dictionary) -> Variant:
	if player.stats.weapon_locked and int(item["slot"]) == Items.Slot.WEAPON:
		player._say("Recall your weapon first")
		return item   # nothing changed: what was asked for is handed straight back
	var old: Variant = TownState.gear.get(int(item["slot"]))
	TownState.gear[int(item["slot"])] = item
	player.stats.equip(item, false)
	return old

## The one way the potion count changes in town. The hero's own count is the live one (he can drink in town), TownState mirrors it
## every frame; buying changes the hero's and records it at once.
func change_potions(delta: int) -> void:
	player.stats.potions = clampi(player.stats.potions + delta, 0, 99)
	TownState.potions = player.stats.potions

# --- The world beyond the gate ------------------------------------------------------------------------------------------------

## The road, laid end to end with the plaza (its south end flush with the plaza's north edge) on the one shared navigation mesh.
func _build_road() -> void:
	var road_arena: Arena = CryptRoad.make_world_arena(HALF, _world_nav)
	add_child(road_arena)
	road_arena.build(false)
	crypt = CryptRoad.new()
	add_child(crypt)
	crypt.build(road_arena)
	crypt.nest_destroyed.connect(_on_nest_destroyed)
	if crypt.return_waystone != null:
		crypt.return_waystone.revealed.connect(_on_return_waystone_revealed)

func _on_return_waystone_revealed() -> void:
	if crypt != null and crypt.return_waystone != null:
		_register("return_waystone", "waystone", "return_waystone", crypt.return_waystone.global_position, CryptReturnWaystone.INTERACT_LABEL)

## The director spawns and tracks the monsters, drops the loot and pays the gold for kills; the road's monsters are placed as soon as the
## navigation map really holds the road, a moment after the scene appears.
func _start_director() -> void:
	director = RunDirector.new()
	director.player = player
	director.hud = combat_hud
	director.world_mode = true
	director.gold_per_kill = 2
	director.hero_fell.connect(_hero_fell)
	director.quest_news.connect(_on_quest_news)
	director.quest_item_dropped.connect(_on_quest_item)
	add_child(director)
	director.set_job(TownState.job)
	await crypt.wait_for_navigation()
	director.attach_world(crypt)
	populate_quests()

## How far the quest has got, in its own terms (nests destroyed); a finished quest stays finished until it is handed in.
func quest_stage() -> int:
	if TownState.has_reward():
		return int(JobObjective.stages(TownState.job))
	return crypt.nests_destroyed if crypt != null else 0

func _on_nest_destroyed(count: int, total: int) -> void:
	if TownState.report_progress(CryptRoad.SITE_ID, count):
		hud.show_banner("The last nest is gone\nWarden Hale will want to hear it", 5.0)
		_refresh_reward_marker()
	else:
		hud.show_banner("Nest destroyed  %d / %d" % [count, total], 3.0)

# --- Quests and events -----------------------------------------------------------------------------------------------------------

## New quests and matters turn up as time passes (see Quests.tick); what turns up is told once and, if it lives on the road, put there.
func _tick_quests(delta: float) -> void:
	var posted: Array[Dictionary] = Quests.tick(delta)
	if not posted.is_empty():
		populate_quests()
		_refresh_reward_marker()
		TownState.save()
	_flush_quest_news()
	hud.side_lines = Quests.tracker_lines()
	hud.cards = Monsters.cards()
	hud.on_road = outside
	hud.pointers = _pointers()
	_tick_monsters(delta)

## Tells the player what the quests have done since last time, in one banner.
func _flush_quest_news() -> void:
	var lines: Array[String] = Quests.pop_news()
	if lines.is_empty():
		return
	_on_quest_news("\n".join(lines))

func _on_quest_news(line: String) -> void:
	hud.show_banner(line, 4.0)
	_refresh_reward_marker()

## A quest item dropped from a monster: it lies where it fell until the hero walks over it.
func _on_quest_item(inst: Dictionary, at: Vector3) -> void:
	var def: QuestDef = Quests.def_of(inst)
	var pickup: QuestPickup = QuestPickup.spawn(self, at, int(inst["uid"]), def.item_name)
	pickup.found.connect(_on_quest_item_found)
	hud.show_banner("It dropped: the %s" % def.item_name, 3.0)

func _on_quest_item_found(uid: int) -> void:
	if Quests.report_fetch_found(uid):
		_flush_quest_news()
		_refresh_reward_marker()
		TownState.save()

## What the quests want out on the road is put there: a named monster for each such quest that does not have one yet. Quest items that
## were dropped and then left behind (the hero was dragged home, the road was reset) can drop again.
func populate_quests() -> void:
	if director == null or crypt == null:
		return
	for inst in Quests.live():
		var def: QuestDef = Quests.def_of(inst)
		if String(inst["state"]) != "active":
			continue
		if def.kind == "world" and not bool(inst["data"].get("applied", true)):
			inst["data"]["applied"] = true
			_toughen_living(def.world_mod)
		if def.kind == "slay_unique" and not bool(inst["data"].get("spawned", false)):
			crypt.spawn_unique(inst)
		elif def.kind == "fetch" and bool(inst["data"].get("dropped", false)):
			var lying: bool = false
			for node in get_tree().get_nodes_in_group("quest_pickups"):
				lying = lying or (node as QuestPickup).uid == int(inst["uid"])
			if not lying:
				Quests.report_fetch_lost(int(inst["uid"]))
	populate_monsters()

## What the monsters are doing is put on the road: each named monster has its body (strength by level, name, marks), the plot it is
## running has its sign, what a plot did when it ended happens (an altar's toughening, a horde climbing out), and what is gone is cleared.
func populate_monsters() -> void:
	if director == null or crypt == null:
		return
	var bodies: Dictionary = {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and not e.dead and not e.is_queued_for_deletion() and e.has_meta("monster_uid"):
			bodies[int(e.get_meta("monster_uid"))] = e
	var signs: Dictionary = {}
	for node in get_tree().get_nodes_in_group("plot_signs"):
		signs[int((node as PlotSign).monster_uid)] = node
	var wanted: Dictionary = {}
	for mon in Monsters.alive():
		var uid: int = int(mon["uid"])
		var body: Enemy = bodies.get(uid)
		var tag: String = Monsters.tag_of(mon) + ("!" if bool(mon["nemesis"]) else "")
		if body == null:
			body = crypt.spawn_named(mon)
		else:
			body.set_threat(float(mon["level"]))   # it has grown: its strength is its own level
			MonsterMark.apply_look(body, mon)
			if String(body.get_meta("mark_tag", "")) != tag:
				MonsterMark.attach(body, mon)
		match String(mon["fired"]):
			"altar":
				for mod in TownState.world_mods:
					if int(mod.get("monster", -1)) == uid and not bool(mod.get("applied", true)):
						mod["applied"] = true
						_toughen_living(mod)
			"uprising":
				crypt.spawn_horde(mon)
		mon["fired"] = ""
		var type: String = ""
		var progress: float = 1.0
		if not (mon["plot"] as Dictionary).is_empty():
			type = String(mon["plot"]["type"])
			progress = Monsters.plot_progress(mon)
		else:
			for mod in TownState.world_mods:
				if int(mod.get("monster", -1)) == uid and String(mod["id"]) == "altar":
					type = "altar"
		if type != "" and type != "scout":
			wanted[uid] = true
			var marker: PlotSign = signs.get(uid)
			if marker != null and marker.plot_type != type:
				marker.queue_free()
				marker = null
			if marker == null:
				marker = PlotSign.spawn(crypt, Nav.snap(crypt, crypt.monster_spot(mon) + Vector3(6.0, 0.0, 2.0)), type, uid)
			marker.set_progress(progress)
	for uid in signs:
		if not wanted.has(uid):
			(signs[uid] as Node).queue_free()

## A townsperson passes on what is being said (see Monsters.gossip): one at a time, only while the hero is inside the walls and nobody
## else is speaking.
func _say_gossip() -> void:
	if Monsters.gossip.is_empty() or outside or panel.is_open() or _gossip_clock > 0.0:
		return
	var entry: Dictionary = Monsters.gossip[0]
	for id in entry["who"]:
		if npcs.has(id) and TownState.npcs.has(id) and not bool(TownState.npcs[id]["left"]) and not (npcs[id] as TownNpc).is_speaking():
			(npcs[id] as TownNpc).say(String(entry["text"]))
			Monsters.gossip.pop_front()
			_gossip_clock = 7.0
			return
	Monsters.gossip.pop_front()

## Every half second: a named monster close to the hero speaks once a day.
func _tick_monsters(delta: float) -> void:
	_gossip_clock = maxf(_gossip_clock - delta, 0.0)
	if Monsters.gossip.size() > 6:
		Monsters.gossip = Monsters.gossip.slice(Monsters.gossip.size() - 6)
	_say_gossip()
	_monster_clock -= delta
	if _monster_clock > 0.0 or player == null or player.dead:
		return
	_monster_clock = 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead or not e.has_meta("monster_uid"):
			continue
		if e.flat_distance_to(player) < 22.0:
			var line: String = Monsters.spot(int(e.get_meta("monster_uid")))
			if line != "":
				hud.show_banner(line, 3.5)
			break

## Where the arrows at the edge of the screen point: the named monsters, the quest's monster and the plots' signs that are off screen.
func _pointers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return out
	var size_px: Vector2 = get_viewport().get_visible_rect().size
	var targets: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead:
			continue
		if e.has_meta("monster_uid"):
			var mon: Dictionary = Monsters.find(int(e.get_meta("monster_uid")))
			targets.append({"at": e.global_position, "tint": Color(0.9, 0.2, 0.14) if bool(mon.get("nemesis", false)) else Color(1.0, 0.5, 0.18)})
		elif e.has_meta("quest_uid"):
			targets.append({"at": e.global_position, "tint": Color(1.0, 0.75, 0.3)})
	for node in get_tree().get_nodes_in_group("plot_signs"):
		targets.append({"at": (node as Node3D).global_position, "tint": Color(0.75, 0.4, 0.9)})
	for target in targets:
		var point: Vector3 = target["at"]
		var screen: Vector2 = camera.unproject_position(point)
		var behind: bool = camera.is_position_behind(point)
		if behind:
			screen = size_px - screen
		if behind or screen.x < 30.0 or screen.y < 30.0 or screen.x > size_px.x - 30.0 or screen.y > size_px.y - 30.0:
			out.append({"screen": screen, "tint": target["tint"]})
	return out

## A world event that makes the dead tougher or quicker reaches the ones already out there too (the ones that come later are made so as
## they appear, see RunDirector.spawn_enemy); it does not wear off them when the event ends, only when the road is corrupted afresh.
func _toughen_living(mod: Dictionary) -> void:
	var health: float = float(mod.get("health_mult", 1.0))
	var speed: float = float(mod.get("speed_mult", 1.0))
	if is_equal_approx(health, 1.0) and is_equal_approx(speed, 1.0):
		return
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.dead:
			continue
		e.max_health *= health
		e.health *= health
		e.move_speed *= speed

## The road was corrupted afresh: every monster was cleared away, so the named ones are put out again.
func _repopulate_after_regrow() -> void:
	for inst in Quests.live():
		if Quests.def_of(inst).kind == "slay_unique":
			inst["data"]["spawned"] = false
	spots = spots.filter(func(s: Dictionary) -> bool: return String(s.get("key", "")) != "return_waystone")
	await crypt.regrow()
	populate_quests()

## The panel changed a quest (handed one in, decided a matter): what that started is put out, the coins are redone, the town is saved.
func quest_changed() -> void:
	populate_quests()
	_flush_quest_news()
	_refresh_reward_marker()
	TownState.save()

## The coin over a townsperson's head while they have something for the hero: a finished quest to hand in, or a matter waiting for a decision.
func _wants_hero(id: String) -> bool:
	if TownDb.npc(id).role == "keeper" and TownState.has_reward():
		return true
	if not Quests.ready_for(id).is_empty():
		return true
	for inst in Quests.live():
		if Quests.def_of(inst).kind == "matter" and Quests.def_of(inst).giver == id:
			return true
	return false

## The coin over Warden Hale's head while a finished quest waits for him to pay it.
func _refresh_reward_marker() -> void:
	for id in npcs:
		var npc: TownNpc = npcs[id]
		npc.set_reward_marker(_wants_hero(id))

## Handing in: the keeper pays every finished quest, the next one is posted, and the road is corrupted afresh behind the hero.
func claim_rewards() -> Dictionary:
	var paid: Dictionary = TownState.claim_ready()
	if int(paid["count"]) > 0:
		_refresh_reward_marker()
		hud.show_banner("Quest done. +%dg%s" % [int(paid["gold"]), (", +%d XP" % int(paid["xp"])) if int(paid["xp"]) > 0 else ""], 4.0)
		if director != null:
			director.set_job(TownState.job)
		if crypt != null:
			_repopulate_after_regrow()
	return paid

## Every frame: where the hero is decides the light (colder, thicker fog out on the road), whether the clan has eaten (once per
## expedition) and whether he has just come home (the bag goes to the stash, the gear is recorded).
func _update_world(delta: float) -> void:
	var z: float = player.global_position.z
	var depth: float = clampf(inverse_lerp(-HALF - 2.0, -HALF - 40.0, z), 0.0, 1.0)
	if with_road:
		var rule_light: float = (director.modifier_product("ambient_mult") if director != null else 1.0) * Quests.world_mult("ambient_mult")
		var rule_fog: float = (director.modifier_product("fog_mult") if director != null else 1.0) * Quests.world_mult("fog_mult")
		world_environment.ambient_light_energy = _base_ambient * lerpf(1.0, CryptRoad.AMBIENT_MULT * rule_light, depth)
		world_environment.fog_density = _base_fog * lerpf(1.0, CryptRoad.FOG_MULT * rule_fog, depth)
	if not outside and z < -HALF - 10.0:
		outside = true
		TownState.begin_expedition()
		if not _announced_road and not TownState.job.is_empty():
			_announced_road = true
			var rules: String = ""
			if director != null and not director.modifiers.is_empty():
				rules = "\n" + director.modifier_names()
			hud.show_banner("%s%s\n%s" % [String(TownState.job.get("location", "The road")).capitalize(), rules, JobObjective.describe(TownState.job)], 4.0)
	elif outside and z > -HALF + 1.5 and not player.dead:
		outside = false
		_arrive_in_town()
	hud.quest_line = _quest_line()
	hud.quest_ready = TownState.has_reward()
	combat_hud.wave = 0
	if director != null:
		combat_hud.kills = director.kills
		combat_hud.alive = get_tree().get_nodes_in_group("enemies").size()
		combat_hud.objective = ""   # the quest has its own line in the corner of the town HUD

func _quest_line() -> String:
	if TownState.job.is_empty():
		return ""
	if TownState.has_reward():
		return "%s: done" % String(TownState.job.get("name", "Quest"))
	return "%s: %s" % [String(TownState.job.get("name", "Quest")), JobObjective.progress_text(TownState.job, {"stage": quest_stage()}).replace("Destroy nests: ", "")]

## Back inside the walls: what the hero carries is recorded (gear worn, potions held) and the bag goes to the stash.
func _arrive_in_town() -> void:
	TownState.end_expedition()
	populate_quests()
	_flush_quest_news()
	_refresh_reward_marker()
	TownState.take_gear(player.stats.equipment)
	var carried: int = player.stats.bag.size()
	for item in player.stats.bag:
		TownState.stash_item(item)
	player.stats.bag.clear()
	TownState.potions = maxi(player.stats.potions, 0)
	TownState.save()
	if carried > 0:
		hud.show_banner("Back in town. %d item%s in the stash" % [carried, "" if carried == 1 else "s"], 3.0)
	elif TownState.has_reward():
		hud.show_banner("Warden Hale has your reward", 3.0)

## Whatever killed the hero is remembered: a named monster becomes a nemesis (stronger, with a title); one that was not named is, most of
## the time, given a name now. Returns what it says.
func _killer_takes_credit() -> String:
	var killer := player.last_hit_by as Enemy
	player.last_hit_by = null
	if killer == null or not is_instance_valid(killer) or crypt == null:
		return ""
	if killer.has_meta("monster_uid"):
		return Monsters.hero_fell(int(killer.get_meta("monster_uid")))
	if killer.has_meta("quest_uid") or killer.is_boss or Monsters.rng.randf() > 0.6:
		return ""
	var mon: Dictionary = Monsters.promote(killer.variant, crypt.distance_of(killer.global_position))
	mon["lane"] = 0.0
	killer.set_threat(float(mon["level"]))   # it is now a named monster: it is as strong as that level says
	MonsterMark.attach(killer, mon)
	MonsterMark.apply_look(killer, mon)
	killer.display_name = String(mon["name"])
	return "%s: \"%s\"" % [mon["name"], Monsters.taunt("kill")]

## The hero fell out on the road: after a moment he is dragged back to the plaza, whole, with the monsters where they were.
func _hero_fell() -> void:
	var taunt: String = _killer_takes_credit()
	hud.show_banner("You were dragged back" + ("\n" + taunt if taunt != "" else ""), 4.0)
	await get_tree().create_timer(3.2).timeout
	player.revive_at(Vector3(0, 0, 10.0))
	rig.global_position = player.global_position
	outside = false
	_arrive_in_town()
	director.hero_returned()

## `--xpdemo` (with --townshot): the hero's own blows kill a zombie and a Brute on the road, break a nest, hand in the quest and kill a named
## monster; every step prints the XP total it moved to. Not part of the game.
func _xp_demo() -> void:
	HeroProgression.logging = true
	var z: float = CryptRoad.EXIT_Z - 40.0
	player.global_position = crypt.at(crypt.road_centre_x(z), z)
	await get_tree().create_timer(0.5).timeout
	var hit_dead: Callable = func(e: Enemy) -> void:
		var tries: int = 0
		while is_instance_valid(e) and not e.dead and tries < 40:
			tries += 1
			e.receive(Combat.resolve(player, e, 9999.0, Combat.DamageType.PHYSICAL, false, 1.0), player.global_position)
		await get_tree().create_timer(0.2).timeout
	var step: Callable = func(label: String, before: int) -> void:
		print("[xpdemo] %-34s %+4d XP  -> total %d  (level %d)" % [label, TownState.hero_xp - before, TownState.hero_xp, TownState.hero_level])
	var before: int = TownState.hero_xp
	var zombie: Enemy = director.spawn_enemy(player.global_position + Vector3(2, 0, 0), "zombie", crypt.threat_at(player.global_position))
	await hit_dead.call(zombie)
	step.call("zombie killed by the hero", before)
	before = TownState.hero_xp
	var brute: Enemy = director.spawn_enemy(player.global_position + Vector3(2, 0, 0), "brute", crypt.threat_at(player.global_position))
	await hit_dead.call(brute)
	step.call("Brute killed by the hero", before)
	before = TownState.hero_xp
	var stray: Enemy = director.spawn_enemy(player.global_position + Vector3(2, 0, 0), "zombie", 1.25)
	stray._apply_damage(stray.max_health + 10.0)   # dies of nothing the hero did
	await get_tree().create_timer(0.2).timeout
	step.call("zombie that died on its own", before)
	before = TownState.hero_xp
	crypt.nests[0].hit(9999.0, Vector3.FORWARD)
	await get_tree().create_timer(0.2).timeout
	step.call("nest destroyed", before)
	before = TownState.hero_xp
	if is_instance_valid(crypt.nests[0]):
		crypt.nests[0].hit(9999.0, Vector3.FORWARD)   # a broken nest is gone: nothing more to pay
	step.call("same nest again", before)
	var mon: Dictionary = Monsters.rise()
	mon["kind"] = "ghoul"
	mon["dist"] = 40.0
	mon["level"] = 3.4
	mon["kills"] = 1
	populate_monsters()
	var named: Enemy = null
	for node in get_tree().get_nodes_in_group("enemies"):
		if node.has_meta("monster_uid") and int(node.get_meta("monster_uid")) == int(mon["uid"]):
			named = node
	before = TownState.hero_xp
	var expected: int = HeroProgression.kill_xp(2, 3.4) + HeroProgression.named_xp(3.4, 1, false)
	await hit_dead.call(named)
	step.call("named monster lvl 3.4, 1 hero kill (expect %d)" % expected, before)
	before = TownState.hero_xp
	TownState.board[0]["ready"] = true
	claim_rewards()
	step.call("standing quest handed in", before)
	await get_tree().create_timer(0.8).timeout

## `--builddemo=wallspike|reaping_recall|ricochet` (with --townshot): the hero is raised to level 12, spends points on a few passives and the
## named Weapon Throw evolution through the real API (a developer session never touches the production save), then throws in the real world:
## a stone wall and a few monsters are put on the road and the throw is run with a picture at each moment worth seeing
## (%TEMP%/curse_build_<name>_N.png). Prints the build state and what happened.
func _build_demo(which: String) -> void:
	TownState.dev_set_hero_level(12)
	for id in ["unbowed", "retaliation", "iron_recovery"]:
		TownState.buy_passive(id)
	if BuildDefs.is_evolution("throw", which):
		TownState.select_evolution("throw", which)
	print("[builddemo] level %d  passive points %d/%d free  evolution points %d/%d free  passives %s  evolutions %s" % [TownState.hero_level,
		TownState.passive_points_available(), HeroProgression.passive_points_for_level(TownState.hero_level), TownState.evolution_points_available(),
		HeroProgression.evolution_points_for_level(TownState.hero_level), str(TownState.purchased_passives), str(TownState.skill_evolutions)])
	var z: float = CryptRoad.EXIT_Z - 30.0
	var origin: Vector3 = crypt.at(crypt.road_centre_x(z), z)
	player.global_position = origin
	for node in get_tree().get_nodes_in_group("enemies"):
		if (node as Node3D).global_position.distance_to(origin) < 45.0:
			node.queue_free()
	await get_tree().create_timer(0.6).timeout
	var shot: Callable = func(label: String) -> void:
		await get_tree().create_timer(0.12).timeout
		var path: String = OS.get_environment("TEMP") + "/curse_build_%s_%s.png" % [which, label]
		get_viewport().get_texture().get_image().save_png(path)
		print("[builddemo] picture ", path)
	var dummy: Callable = func(at: Vector3, kind: String = "zombie") -> Enemy:
		var e: Enemy = director.spawn_enemy(at, kind, 1.25)
		e.aggro_range = 0.0
		e.max_health = 4000.0
		e.health = 4000.0
		return e
	var wall_at: Callable = func(centre: Vector3, wall_size: Vector3) -> StaticBody3D:
		var wall := StaticBody3D.new()
		wall.collision_layer = Actor.LAYER_WORLD
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = wall_size
		shape.shape = box
		wall.add_child(shape)
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = wall_size
		mesh.mesh = cube
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.27, 0.25, 0.23)
		stone.roughness = 0.95
		mesh.material_override = stone
		wall.add_child(mesh)
		add_child(wall)
		wall.global_position = centre
		return wall
	var wt: WeaponThrowSkill = player.weapon_throw
	var throw_now: Callable = func(aim: Vector3, hold: float) -> void:
		wt._profile = wt.profile()
		wt.evolution = player.evolution_of("throw")
		wt.state = WeaponThrowSkill.State.CHARGING
		wt._hold = hold
		wt.charge = wt.charge_fraction()
		wt.release(aim)
	player.stats.cooldowns.clear()
	var east: Vector3 = Vector3(1, 0, 0)
	player.visual.rotation.y = atan2(east.x, east.z)
	match which:
		"iron":   # Iron Recovery: a heavy blow knocks him down; when he is back on his feet he shoves the lesser enemies round him back
			var ring: Array[Enemy] = []
			for angle in [0.0, 2.1, 4.2]:
				ring.append(dummy.call(origin + Vector3(cos(angle), 0, sin(angle)) * 2.0))
			var heavy_brute: Enemy = dummy.call(origin + Vector3(cos(1.05), 0, sin(1.05)) * 2.3, "brute")
			await get_tree().create_timer(0.4).timeout
			await shot.call("0_surrounded")
			var attacker: Enemy = dummy.call(origin + Vector3(0, 0, 4.0), "brute")
			var blow: Dictionary = Combat.resolve(attacker, player, 20.0, Combat.DamageType.PHYSICAL, false, 2.7)
			blow["outcome"] = Combat.Outcome.CRUSHING
			blow["damage"] = 20.0
			blow["weight"] = 2.7
			player.receive(blow, attacker.global_position)
			player.knock = Vector3.ZERO
			var near: PackedStringArray = []
			for e in ring:
				near.append("%.1f m" % e.flat_distance_to(player))
			print("[builddemo] heavy blow taken: stun ", snappedf(player.stun_time, 0.01), " s; ring distances ", ", ".join(near), "; brute ", snappedf(heavy_brute.flat_distance_to(player), 0.1), " m")
			await get_tree().create_timer(0.2).timeout
			await shot.call("1_knockdown_impact")
			await get_tree().create_timer(0.4).timeout
			await shot.call("2_downed")
			await get_tree().create_timer(0.45).timeout
			await shot.call("3_getting_up")
			await get_tree().create_timer(0.5).timeout
			await shot.call("4_shoved")
			var far: PackedStringArray = []
			for e in ring:
				far.append("%.1f m" % e.flat_distance_to(player))
			print("[builddemo] after he shook it off (shoves ", player.iron_shoves, "): ring distances ", ", ".join(far), "; brute ", snappedf(heavy_brute.flat_distance_to(player), 0.1), " m")
		"wallspike":
			wall_at.call(origin + Vector3(14.0, 2.0, 0.0), Vector3(1.0, 4.0, 7.0))
			var victim: Enemy = dummy.call(origin + Vector3(6.0, 0, 0))
			dummy.call(origin + Vector3(8.5, 0, 0.4))
			await shot.call("0_before")
			throw_now.call(origin + east * 40.0, 10.0)
			await _wait_throw(wt, WeaponThrowSkill.State.EMBEDDED, 4.0)
			await shot.call("1_pinned")
			print("[builddemo] pinned=", wt.pinned == victim, " impaled=", victim.impaled, " victim x offset from hero=", snappedf(victim.global_position.x - origin.x, 0.1))
			await get_tree().create_timer(1.0).timeout
			wt.recall()
			await get_tree().create_timer(0.35).timeout
			await shot.call("2_released")
			print("[builddemo] after recall pinned=", wt.pinned == null, " victim released=", not victim.impaled, " ragdolled=", victim.is_ragdolled())
		"ricochet":
			wall_at.call(origin + Vector3(11.5, 2.0, 0.0), Vector3(1.0, 4.0, 22.0))
			var aim: Vector3 = Vector3(1.0, 0.0, 0.5).normalized()
			var hit: Vector3 = origin + aim * (11.0 / aim.x)
			var bounce_out: Vector3 = aim.bounce(Vector3(-1, 0, 0)).normalized()
			dummy.call(hit + bounce_out * 3.5)
			dummy.call(hit + bounce_out * 5.0 + Vector3(0, 0, 1.0))
			await get_tree().physics_frame   # the new wall must be in the physics space before the lane looks for it
			await get_tree().physics_frame
			wt._profile = wt.profile()
			wt.evolution = "ricochet"
			wt.state = WeaponThrowSkill.State.CHARGING
			wt._hold = 10.0
			wt.charge = 1.0
			wt.update_preview(origin + aim * 20.0)
			await shot.call("0_preview")
			print("[builddemo] preview bounce length ", snappedf(wt.preview.bounce_length, 0.1), " dir ", wt.preview.bounce_dir)
			wt.cancel_charge()
			throw_now.call(origin + aim * 40.0, 10.0)
			var frames: int = 0
			while wt.bounces == 0 and frames < 300:
				await get_tree().physics_frame
				frames += 1
			await shot.call("1_bounce")
			await _wait_throw(wt, WeaponThrowSkill.State.EMBEDDED, 4.0)
			await shot.call("2_embedded")
			print("[builddemo] bounces=", wt.bounces, " struck after the bounce=", wt.last_out_hits.size())
		_:
			var targets: Array[Enemy] = []
			throw_now.call(origin + east * 40.0, 10.0)
			await _wait_throw(wt, WeaponThrowSkill.State.EMBEDDED, 4.0)
			var rest: Vector3 = wt.thrown.center()
			var back_spot: Vector3 = Vector3(rest.x - 14.0, 0.0, rest.z + 7.0)
			player.global_position = back_spot
			for f in [0.35, 0.6]:
				targets.append(dummy.call(Vector3(rest.x, 0.0, rest.z).lerp(back_spot, f)))
			await get_tree().create_timer(0.3).timeout
			await shot.call("0_set")
			wt.recall()
			await get_tree().create_timer(1.2).timeout
			await shot.call("1_dragging")
			await get_tree().create_timer(1.4).timeout
			await shot.call("2_gathered")
			var gathered: PackedStringArray = []
			for e in targets:
				gathered.append("%.1f m" % e.flat_distance_to(player))
			print("[builddemo] pulled ", wt.pulled_ids.size(), " enemies; distances to hero now ", ", ".join(gathered))
	await get_tree().create_timer(0.5).timeout

func _wait_throw(wt: WeaponThrowSkill, state: int, seconds: float) -> void:
	var waited: float = 0.0
	while int(wt.state) != state and waited < seconds:
		await get_tree().physics_frame
		waited += 1.0 / 60.0

func _screenshot(args: PackedStringArray) -> void:
	TownState.persist = false   # a developer screenshot never writes the player's save
	await get_tree().create_timer(3.0).timeout
	for arg in args:
		if arg == "--ready":   # developer tool: pretend the quest is done, to see Hale's coin and the HUD
			TownState.board[0]["ready"] = true
			TownState.job = (TownState.board[0] as Dictionary).duplicate(true)
			_refresh_reward_marker()
		if arg == "--quests":   # developer tool: put some quests and matters up, to see the tracker and the panels
			TownState.jobs_done = 2
			for id in ["ghoul_cull", "brute_bounty", "lost_satchel", "fever", "light_fingers", "blood_moon"]:
				Quests.post(id)
			populate_quests()
			_refresh_reward_marker()
			_flush_quest_news()
		if arg == "--monsters":   # developer tool: two named monsters (one a nemesis) with plots under way, and the hero near the first
			TownState.jobs_done = 2
			for i in 2:
				var made: Dictionary = Monsters.rise()
				made["dist"] = 60.0 + 12.0 * i
				made["level"] = 3.4 + i
			var first: Dictionary = TownState.monsters[0]
			first["nemesis"] = true
			first["kills"] = 2
			first["plot"] = {"type": "altar", "days_left": 2, "total": 4}
			TownState.monsters[1]["plot"] = {"type": "raid", "days_left": 1, "total": 3}
			Quests.tell("The Hollow has been seen near the wood.", "monster")
			Quests.tell("Fog Bank: a fog bank has rolled in.", "event")
			populate_monsters()
			player.global_position = crypt.monster_spot(first) + Vector3(0, 0, 14)
			await get_tree().create_timer(1.5).timeout
		if arg.begins_with("--zoom="):   # --zoom=n: pull the camera back (the plaza opens at 2.6)
			rig.set_zoom_now(float(arg.substr(7)))
		if arg.begins_with("--at="):   # --at=x,z: move the hero first
			var parts: PackedStringArray = arg.substr(5).split(",")
			player.global_position = Vector3(float(parts[0]), 0, float(parts[1]))
			await get_tree().create_timer(1.0).timeout
		if arg.begins_with("--road="):   # --road=D: stand D metres out from the town gate, on the Crypt Road
			var z: float = CryptRoad.EXIT_Z - float(arg.substr(7))
			player.global_position = crypt.at(crypt.road_centre_x(z), z)
			await get_tree().create_timer(1.0).timeout
		if arg == "--xpdemo":   # developer tool: earn XP the real way (hits, a nest, a hand-in, a named monster) and print each change
			await _xp_demo()
		if arg.begins_with("--builddemo="):   # developer tool: buy a Weapon Throw evolution and use it on the road, with pictures
			await _build_demo(arg.substr(12))
		if arg.begins_with("--panel="):   # --panel=marlow | board | stash | character | progression | evolutions | evolution-confirm: open that panel first
			var what: String = arg.substr(8)
			match what:
				"progression", "evolutions", "evolution-confirm":
					TownState.dev_set_hero_level(maxi(TownState.hero_level, 12))
					TownState.buy_passive("unbowed")
					combat_hud.show_gear = true
					combat_hud._open_character()
					combat_hud.open_progression()
					if what != "progression":
						combat_hud.progression_panel.show_section("evolutions")
					if what == "evolution-confirm":
						combat_hud.progression_panel._request_evolution("throw", "wallspike")
				"character":
					combat_hud.show_gear = true
					combat_hud._open_character()
				"chronicle":
					panel.open_chronicle()
				"board":
					panel.open_board()
				"stash":
					panel.open_stash()
				_:
					panel.open_npc(what)
			await get_tree().create_timer(0.8).timeout
	for arg in args:
		if arg.begins_with("--hover="):
			var spot: Dictionary = _spot(arg.substr(8))
			if not spot.is_empty():
				get_viewport().warp_mouse(get_viewport().get_camera_3d().unproject_position(spot["pos"] + Vector3(0, 1.1, 0)))
				await get_tree().create_timer(0.7).timeout
	if args.has("--xpreport") and director != null:   # developer tool: what this road would pay if it were all cleared
		var report: Dictionary = director.xp_report()
		print("[xpreport] %d ordinary monsters %s = %d XP; %d nests = %d XP; standing quest = %d XP; TOTAL %d XP (a fresh hero needs %d for level 2, %d for level 5)"
			% [report["kills"], str(report["by_kind"]), report["kill_xp"], report["nests"], report["nest_xp"], report["quest_xp"], report["total"],
			HeroProgression.xp_for_level(2), HeroProgression.xp_for_level(5)])
		print("[xpreport] plus %d named monsters worth %d XP in bounties if killed" % [report["named"], report["named_xp"]])
	if args.has("--threats"):   # developer tool: how strong are the monsters round the hero (hero level, then kind / threat / health / damage)
		print("[threats] hero level %d" % TownState.hero_level)
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and not e.dead and e.global_position.distance_to(player.global_position) < 30.0:
				print("[threats]   %-8s %-22s threat %.2f  health %5.1f  damage %4.1f-%4.1f  %s" % [e.variant, e.display_name, e.level_scale, e.max_health,
					e.damage_min, e.damage_max, "NAMED" if e.has_meta("monster_uid") else ""])
	if args.has("--timing"):
		print("[world] %.0f fps with %d monsters, %d people" % [Performance.get_monitor(Performance.TIME_FPS), get_tree().get_nodes_in_group("enemies").size(), npcs.size()])
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_town.png")
	get_tree().quit()
