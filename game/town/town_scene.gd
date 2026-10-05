class_name TownScene
extends Node3D
## The hub between runs: a small walled plaza with the north gate, the healing stone, the trader's stall, the job board, a stash and
## a handful of townspeople who live their own lives (see TownSim). Walk up to someone or something and click it, or press the
## interact button, to open its panel. The gate starts the job you took, or a free run.

const HALF := 22.0
const MAIN_SCENE := "res://game/main.tscn"
const INTERACT_RANGE := 3.4
const TAG_RANGE := 8.0
const BARK_RANGE := 16.0

var arena: Arena
var player: Player
var rig: CameraRig
var sim: TownSim
var hud: TownHud
var panel: TownPanel
var pause_menu: PauseMenu
var npcs: Dictionary = {}                 # id -> TownNpc
var spots: Array[Dictionary] = []         # {key, kind, id, pos, label}: everything you can walk up to and use
var world_environment: Environment
var pending: String = ""                  # key of the spot the hero was sent to by a click
var leaving: bool = false
var near: Dictionary = {}                 # the spot the hero is standing at (empty when none)

func _ready() -> void:
	get_tree().paused = false
	GameSettings.boot()
	if TownState.npcs.is_empty():
		TownState.load_or_start()
	sim = TownSim.new()
	_build_world()
	_build_town()
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
	_welcome_back()
	var args: PackedStringArray = OS.get_cmdline_user_args()
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
	env.environment = environment
	world_environment = environment
	add_child(env)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-52, -30, 0)
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.light_energy = 0.8
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 60.0
	add_child(moon)

## Layout, in metres (north is -z): the gate in the north wall, the healing stone in the middle of the plaza, the trader's stall to
## the west and the job board to the east, the stash and the cottages south of the plaza, a palisade round the edge.
func _build_town() -> void:
	arena = Arena.new()
	arena.half = HALF
	arena.scatter = false
	add_child(arena)
	arena.build(false)
	# (name, x, z, yaw degrees, height m, collides, lit)
	var layout: Array = [
		["town_gate", 0.0, -20.0, 0.0, 6.0, true, false],
		["healthstone", 0.0, -2.0, 0.0, 2.3, true, false],
		["market_stall", -9.5, -5.5, 35.0, 2.7, true, false],
		["bulletin_board", 9.5, -8.0, -30.0, 2.8, true, false],
		["stash_chest", 6.0, 8.0, -20.0, 0.9, true, false],
		["cottage", -15.0, 5.0, 70.0, 5.0, true, false],
		["cottage", 15.5, 0.0, -80.0, 5.0, true, false],
		["cottage", -13.0, 15.5, 160.0, 5.0, true, false],
		["lamp_post", -4.5, 4.0, 0.0, 3.2, true, true],
		["lamp_post", 5.5, -2.5, 0.0, 3.2, true, true],
		["lamp_post", -5.0, -13.0, 0.0, 3.2, true, true],
		["lamp_post", 5.0, -14.0, 0.0, 3.2, true, true],
		["brazier", -3.5, -17.0, 0.0, 1.5, true, true],
		["brazier", 3.5, -17.0, 0.0, 1.5, true, true],
		["barrel", -12.0, -6.5, 30.0, 1.0, true, false],
		["barrel", -11.2, -7.4, 0.0, 1.0, true, false],
		["wrecked_cart", 16.0, -10.0, 40.0, 1.9, true, false],
		["dead_tree", 18.0, 14.0, 0.0, 5.5, true, false],
		["dead_tree", -19.0, -10.0, 0.0, 5.0, true, false],
		["rubble", 17.0, 18.0, 0.0, 1.1, true, false],
	]
	for entry in layout:
		if ResourceLoader.exists(Arena.PROP_DIR + String(entry[0]) + "/model.glb"):
			arena.place_prop(entry[0], Vector3(entry[1], 0, entry[2]), deg_to_rad(entry[3]), entry[4], entry[5], entry[6])
	# A palisade all the way round, entirely inside the ground (which runs from -HALF to HALF): sections about 6.75 m long are laid in
	# overlapping rows whose end sections stop exactly at the corners, so nothing sticks out past the edge. The north wall leaves the
	# gate arch (about 9 m wide) open between its two halves.
	if ResourceLoader.exists(Arena.PROP_DIR + "palisade/model.glb"):
		var wall: float = HALF - 1.0             # the line the fence stands on
		var end: float = HALF - 0.5 - 3.375      # the centre of the last section, so its far end is half a metre inside the edge
		for k in 7:
			var c: float = -end + 2.0 * end * float(k) / 6.0
			arena.place_prop("palisade", Vector3(c, 0, wall), 0.0, 2.4)                       # south
			arena.place_prop("palisade", Vector3(wall, 0, c), PI * 0.5, 2.4)                  # east
			arena.place_prop("palisade", Vector3(-wall, 0, c), PI * 0.5, 2.4)                 # west
		for side in [-1.0, 1.0]:                                                              # north, either side of the gate
			for x in [7.9, 13.0, end]:
				arena.place_prop("palisade", Vector3(side * x, 0, -wall), 0.0, 2.4)
	# The healing stone glows like embers.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.5, 0.2)
	glow.light_energy = 2.4
	glow.omni_range = 8.0
	glow.position = Vector3(0, 1.3, -2.0)
	add_child(glow)
	glow.add_child(FlickerLight.new())
	arena.bake_navigation()

	_register("gate", "gate", "", Vector3(0, 0, -17.5), "Go through the gate")
	_register("stone", "stone", "", Vector3(0, 0, 0.2), "Rest at the healing stone")
	_register("board", "board", "", Vector3(9.0, 0, -5.8), "Read the job board")
	_register("stash", "stash", "", Vector3(6.0, 0, 6.2), "Open the stash")
	for id in TownDb.sorted_ids(TownDb.npcs()):
		var def: NpcDef = TownDb.npc(id)
		var npc: TownNpc = TownNpc.create(def)
		add_child(npc)
		npc.position = Vector3(def.home.x, 0, def.home.y)
		npc.rotation.y = atan2(-def.home.x, -def.home.y - 1.0)   # toward the middle of the plaza
		npcs[id] = npc
		_register("npc:" + id, "npc", id, npc.position, "Talk to %s" % def.display_name)

func _register(key: String, kind: String, id: String, pos: Vector3, label: String) -> void:
	spots.append({"key": key, "kind": kind, "id": id, "pos": pos, "label": label})

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	hud = TownHud.new()
	layer.add_child(hud)
	panel = TownPanel.new()
	panel.town = self
	panel.leave_requested.connect(leave_through_gate)
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
	var died: bool = bool(result.get("died", false))
	var line: String = "You are back. +%dg" % int(result.get("gold", 0))
	if bool(result.get("completed", false)):
		line = "Job done. +%dg" % int(result.get("gold", 0))
	elif died:
		line = "You were dragged back. +%dg" % int(result.get("gold", 0))
	hud.show_banner(line, 4.0)
	var key: String = "return_dead" if died else "return_ok"
	for id in ["hale", "marlow"]:
		if npcs.has(id):
			(npcs[id] as TownNpc).say(sim.line_for(id, key))

# --- Frame ---------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if leaving:
		return
	sim.tick(delta)
	_show_barks()
	_update_near()
	_update_tags()
	hud.prompt = "" if panel.is_open() or near.is_empty() else "%s   %s" % [_interact_key(), near["label"]]
	_update_feed()
	if not pending.is_empty() and not panel.is_open():
		var spot: Dictionary = _spot(pending)
		if spot.is_empty() or _flat_distance(spot) <= INTERACT_RANGE:
			pending = ""
			if not spot.is_empty():
				interact(spot)

func _interact_key() -> String:
	return "[A]" if Gamepad.active else "[E]"

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
		npc.set_tag_visible(d <= TAG_RANGE)

func _show_barks() -> void:
	while not sim.barks.is_empty():
		var bark: Dictionary = sim.barks.pop_front()
		var npc: TownNpc = npcs.get(bark["id"])
		if npc == null or player.global_position.distance_to(npc.global_position) > BARK_RANGE:
			continue
		npc.say(String(bark["text"]))
		var partner: TownNpc = npcs.get(bark["partner"]) if bark["partner"] != "" else null
		if partner != null:
			npc.face_toward(partner.global_position)
			partner.face_toward(npc.global_position)

func _update_feed() -> void:
	var count: int = sim.history.size()
	var feed: Array[String] = []
	for i in range(maxi(count - 3, 0), count):
		feed.append(sim.history[i])
	hud.feed = feed

# --- Interaction ---------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if leaving or panel.is_open():
		return
	if event.is_action_pressed("pause") and not pause_menu.is_open():
		pause_menu.open()
		return
	if pause_menu.is_open():
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
		"gate":
			panel.open_gate()
		"stone":
			player.health = player.max_health
			hud.show_banner("The stone is warm. You feel whole.", 2.5)

## Out of the gate and into a run: the job (if any) is set, the clan eats, the town is saved.
func leave_through_gate() -> void:
	if leaving:
		return
	leaving = true
	TownState.begin_job(TownState.job)
	TownState.potions = player.stats.potions
	LoadingScreen.go(get_tree(), MAIN_SCENE)

func _screenshot(args: PackedStringArray) -> void:
	await get_tree().create_timer(3.0).timeout
	for arg in args:
		if arg.begins_with("--at="):   # --at=x,z: move the hero first
			var parts: PackedStringArray = arg.substr(5).split(",")
			player.global_position = Vector3(float(parts[0]), 0, float(parts[1]))
			await get_tree().create_timer(1.0).timeout
		if arg.begins_with("--panel="):   # --panel=marlow | board | stash | gate: open that panel first
			var what: String = arg.substr(8)
			match what:
				"board":
					panel.open_board()
				"stash":
					panel.open_stash()
				"gate":
					panel.open_gate()
				_:
					panel.open_npc(what)
			await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/curse_town.png")
	get_tree().quit()
