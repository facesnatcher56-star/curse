class_name TownScene
extends Node3D
## The hub between runs: a small walled plaza with the north gate, the healing stone, the trader's stall, the job board, a stash and
## a handful of townspeople who live their own lives (see TownSim). Walk up to someone or something and click it, or press the
## interact button, to open its panel. The gate starts the job you took, or a free run.

const HALF := 22.0
const MAIN_SCENE := "res://game/main.tscn"
const LAYOUT_PATH := "res://game/town/town_layout.tscn"
const SPOT_LABELS := {"gate": "Go through the gate", "stone": "Rest at the healing stone", "board": "Read the job board",
	"stash": "Open the stash"}
const GATE_HALF_WIDTH := 4.5   # half the opening in the north palisade (the palisade halves start at 4.5 m)
const INTERACT_RANGE := 3.4
const TAG_RANGE := 8.0
const BARK_RANGE := 16.0

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
var leaving: bool = false
var near: Dictionary = {}                 # the spot the hero is standing at (empty when none)

func _ready() -> void:
	get_tree().paused = false
	GameSettings.boot()
	if TownState.npcs.is_empty():
		TownState.load_or_start()
	sim = TownSim.new()
	stage = TownStage.new(self)
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

## The static town (buildings, walls, lamps, props, the spots you use and the places people go) is the scene town_layout.tscn, edited
## in Godot: TownProp markers under Props, Marker3Ds under Spots and Stations. This builds the ground, hands each prop to the arena
## (collision, light, navigation), then the glow, the people and the interactions. Metres, north is -z.
func _build_town() -> void:
	arena = Arena.new()
	arena.half = HALF
	arena.scatter = false
	arena.build_perimeter_walls = false
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
	arena.bake_navigation()

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
## Beyond the opening is a trigger: walking through it leaves town. A backstop behind it stops anything walking off the ground.
func _place_layout() -> void:
	layout = (load(LAYOUT_PATH) as PackedScene).instantiate()
	add_child(layout)
	var props: Node = layout.get_node("Props")
	for node in props.get_children():
		var prop := node as TownProp
		if prop != null and ResourceLoader.exists(Arena.PROP_DIR + prop.model_name + "/model.glb"):
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
	rows.append([0.0, -HALF - 3.0, GATE_HALF_WIDTH * 2.0 + 2.0, 1.0])   # backstop
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
	var trigger := Area3D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = Actor.LAYER_PLAYER
	trigger.monitoring = true
	var zone := CollisionShape3D.new()
	var zone_box := BoxShape3D.new()
	zone_box.size = Vector3(GATE_HALF_WIDTH * 2.0, 4.0, 2.0)
	zone.shape = zone_box
	trigger.add_child(zone)
	trigger.position = Vector3(0, 2.0, -HALF - 1.0)
	trigger.body_entered.connect(_on_gate_entered)
	add_child(trigger)

func _on_gate_entered(entered: Node3D) -> void:
	if entered == player and not leaving:
		leave_through_gate()

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
		if arg.begins_with("--zoom="):   # --zoom=n: pull the camera back (the plaza opens at 2.6)
			rig.set_zoom_now(float(arg.substr(7)))
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
