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
var companion: ArcherCompanion
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
var _potions_on_disk: int = -1             # the potion count the save file holds, as far as this scene knows

func _exit_tree() -> void:
	_commit_road_inventory()
	_commit_town_potions()
	TownState.flush_progression(true)   # leaving the world: nothing earned is left waiting for the disk

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_commit_road_inventory()
		_commit_town_potions()
		TownState.flush_progression(true)

## Leaving the world mid-expedition (pause > Main menu / Quit game / window close) must not be worse than dying, which already stashes the bag.
## Only the inventory half of _arrive_in_town: worn gear is recorded and the bag goes to the stash. No end_expedition, quest day, prize,
## banner or run claim. Idempotent: the bag is empty after the first call, so a second call re-saves the same state.
func _commit_road_inventory() -> void:
	if not outside or player == null or not is_instance_valid(player) or player.stats == null:
		return
	if is_instance_valid(director):   # leaving the world is not a death: what lies on the road is recovered (owner policy)
		director.settle_ground_rewards(false)
	PartyManager.current().to_dict() # Snapshot each member; selected equipment is never Hero's global equipment.
	TownState.stash_carried(player.stats.bag)
	player.stats.bag.clear()
	TownState.save()

## Inside the walls the hero can drink a potion and nothing saves it, so leaving (Main menu / Quit / window close) handed it back. Saves only
## when the hero's count differs from what the file holds; on the road `_commit_road_inventory` already saves the live count.
func _commit_town_potions() -> void:
	if outside or player == null or not is_instance_valid(player) or player.stats == null:
		return
	var held: int = maxi(player.stats.potions, 0)
	if held == _potions_on_disk:
		return
	TownState.potions = held
	TownState.save()
	_potions_on_disk = held

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
	# Cutter is a real companion in the connected town/road world, not a second decorative copy at his old stall.
	if npcs.has("cutter"):
		(npcs["cutter"] as TownNpc).set_world_presence(false)
	companion = ArcherCompanion.new()
	add_child(companion)
	companion.setup(player)
	companion.testing_disabled = OS.get_cmdline_user_args().has("--selftest")
	_potions_on_disk = TownState.potions
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
	PartyManager.current().active_member_changed.connect(_party_selected)
	_party_selected("", PartyManager.current().active_id)
	_welcome_back()
	_refresh_reward_marker()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	HeroProgression.logging = args.has("--xplog")   # developer only: print why XP is paid
	TownState.apply_dev_progression.call_deferred(args)   # --level=N / --xp=N (developer only), once the HUD is listening
	if args.has("--timing"):
		print("[world] plaza and road built in %d ms" % (Time.get_ticks_msec() - built_at))
	if args.has("--townshot"):   # developer only: pictures and demos (game/dev/town_shots.gd)
		var shots := TownShots.new()
		shots.town = self
		add_child(shots)
		shots.run(args)

## The gear the hero wears this run: whatever the town holds, over the starting kit.
static func _apply_run_gear(hero: Player) -> void:
	hero.stats.potions = TownState.potions

func _party_selected(_previous: String, _id: String) -> void:
	var selected := PartyManager.current().active_body()
	if selected == null: return
	player = selected
	rig.target = selected
	combat_hud.select_member(selected)
	if director != null: director.player = selected
	pending = ""
	near = {}
	if panel.visible: panel._rebuild()

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
	combat_hud.top_offset = 100.0   # the place name and the resource strip sit above the kills panel
	combat_hud.force_window = with_road
	combat_hud.world_mode = true   # a fallen hero is dragged home: no restart prompt
	combat_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(combat_hud)
	hud = TownHud.new()
	hud.modal_source = combat_hud
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
		if not TownState.orientation_seen:
			TownState.orientation_seen = true
			TownState.save()
			hud.show_banner("The Last Hearth - North Gate leads to the Crypt Road.\nStanding contract: Destroy 3 Corrupted Nests to claim reward.\nClear the far forecourt to reveal the return waystone.", 6.0)
		else:
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
	if companion != null:
		for spot in spots:
			if spot["kind"] == "npc" and spot["id"] == "cutter":
				spot["pos"] = companion.global_position
				break
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
	if town_gate != null and town_gate.has_method("set_tag_visible"):
		var d_gate: float = player.global_position.distance_to(town_gate.global_position)
		town_gate.set_tag_visible(d_gate <= 16.0)

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
## hand (and his armour) is what the shop or stash just gave him. Returns what came off to make room (an Array), or null when he cannot
## wear it (the weapon is out, or the requirement is not met): nothing changed.
func equip_town_item(item: Dictionary) -> Variant:
	var off: Variant = player.stats.equip(item, true)
	if off == null:
		return null
	player.capture_state()
	return off

## The one way the potion count changes in town. The hero's own count is the live one (he can drink in town), TownState mirrors it
## every frame; buying changes the hero's and records it at once.
func change_potions(delta: int) -> void:
	player.stats.potions = clampi(player.stats.potions + delta, 0, 99)
	TownState.potions = player.stats.potions
	_potions_on_disk = TownState.potions   # the shop saves right after

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
	Quests.set_drop_spot(inst, at)
	_spawn_quest_pickup(int(inst["uid"]), def.item_name, at)
	hud.show_banner("It dropped: the %s" % def.item_name, 3.0)

func _spawn_quest_pickup(uid: int, item_name: String, at: Vector3) -> void:
	var pickup: QuestPickup = QuestPickup.spawn(self, at, uid, item_name)
	pickup.found.connect(_on_quest_item_found)

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
	for inst in Quests.live():   # a fetch whose target is gone from the road gets one back, if its quest allows it (QuestDef.respawn_target)
		var target: String = Quests.def_of(inst).target
		var alive: int = 0
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and not e.dead and not e.is_queued_for_deletion() and e.variant == target:
				alive += 1
		if Quests.wants_target_respawn(inst, alive):
			crypt.respawn_fetch_target(inst)
	var lying: Array = []
	for node in get_tree().get_nodes_in_group("quest_pickups"):
		lying.append((node as QuestPickup).uid)
	for spot in Quests.fetch_to_respawn(lying):   # a dropped item that is not on the road goes back to its stored spot
		_spawn_quest_pickup(int(spot["uid"]), String(spot["name"]), spot["at"])
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
			var climax_hint: String = "\nOptional climax: Crypt Forecourt & Warden beyond" if String(TownState.job.get("site", "")) == CryptRoad.SITE_ID else ""
			hud.show_banner("%s%s\n%s%s" % [String(TownState.job.get("location", "The road")).capitalize(), rules, JobObjective.describe(TownState.job), climax_hint], 4.5)
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
	var prog: String = JobObjective.progress_text(TownState.job, {"stage": quest_stage()})
	if prog.begins_with("Destroy nests: "):
		return "%s: %s nests" % [String(TownState.job.get("name", "Quest")), prog.trim_prefix("Destroy nests: ")]
	return "%s: %s" % [String(TownState.job.get("name", "Quest")), prog]

## Back inside the walls: what the hero carries is recorded (gear worn, potions held) and the bag goes to the stash.
func _arrive_in_town() -> void:
	var kept: String = director.settle_ground_rewards(false) if director != null else ""   # a return: what lies on the road is recovered
	if kept != "":
		hud.show_banner(kept, 3.0)
	TownState.end_expedition()
	populate_quests()
	_flush_quest_news()
	_refresh_reward_marker()
	PartyManager.current().to_dict()
	var carried: int = player.stats.bag.size()
	TownState.stash_carried(player.stats.bag)
	player.stats.bag.clear()
	TownState.potions = maxi(player.stats.potions, 0)
	TownState.save()
	_potions_on_disk = TownState.potions
	if carried > 0:
		hud.show_banner("Back in town. %d item%s in the stash" % [carried, "" if carried == 1 else "s"], 3.0)
	elif TownState.has_reward():
		hud.show_banner("Warden Hale has your reward", 3.0)

## Whatever killed the hero is remembered: a named monster becomes a nemesis (stronger, with a title); one that was not named is, most of
## the time, given a name now. Returns what it says.
func _killer_takes_credit() -> String:
	var killer := player.last_hit_by as Enemy
	player.last_hit_by = null
	if Monsters._off() or killer == null or not is_instance_valid(killer) or crypt == null:
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
	var lost: String = director.settle_ground_rewards(true)   # a death: what still lies on the road is lost (owner policy)
	hud.show_banner("You were dragged back" + ("\n" + lost if lost != "" else "") + ("\n" + taunt if taunt != "" else ""), 4.0)
	await get_tree().create_timer(3.2).timeout
	for body in PartyManager.current().bodies.values():
		if is_instance_valid(body): body.revive_at(Vector3(0 if body.member_id == "hero" else 2.4, 0, 10.0))
	rig.global_position = player.global_position
	outside = false
	_arrive_in_town()
	director.hero_returned()
