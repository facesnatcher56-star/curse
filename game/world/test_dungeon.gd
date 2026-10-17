class_name TestDungeon
extends CryptRoad
## The dungeon test level (`-- --dungeon`, issue #25; grown for issue #34, Lane J): a chain of halls and corridors that zig-zags north
## from the entry (the critical path, about 330 m to the final hall), with side spaces (alcoves, treasure rooms, cave pockets) off it:
## 36 spaces, 85 enemies in groups, 5 chests, and about 160 barrels, crates and urns.
##
## THE LEVEL IS A SCENE: `game/world/dungeon_level.tscn`. Open it in the editor to see it and change it (floors, walls, pillars, props, torches,
## chests, the rock round the rooms, the enemy groups as DungeonEnemyGroup markers, and PlayerStart); this class only loads it and wires it
## up (props become breakable, obstacles are registered, the one navigation bake is done). The scene was first written from a plan by
## the developer tool DungeonBaker (game/dev/dungeon_baker.gd); hand edits in the editor are what the game uses.
## It reuses CryptRoad's location plumbing (groups spawned by the director). The `--atmosphere` look is the shared AtmosphereProfile, which
## main applies to every location; this file only adds a brighter tune for the rooms.
##
## Enemy levels follow the hero, never higher (see project()): each area's enemies are the level the hero is projected to be when the
## hero reaches that area, counting the XP the dungeon yields along the critical path with HeroProgression's real tables.

const SITE := "test_dungeon"
const LEVEL_SCENE := "res://game/world/dungeon_level.tscn"
const ARENA_HALF_X := 50.0
const ARENA_HALF_Z := 124.0
const START_POINT := Vector3(0.0, 0.0, 104.0)
## The camera for this level only: fully zoomed-in is 2.0, and a new run starts at 1.5 (main sets these on the rig).
const ZOOM_MAX := 2.0
const ZOOM_START := 1.5
## Cutter is in the party: his share of every kill (DS2's party bonus, HeroProgression.party_share) is part of the hero's XP.
const PARTY_SIZE := 2
## How far the enemies of one group spread from its home, and how far they may roam from it (see CryptRoad._group).
const GROUP_SPREAD := 1.6
const GROUP_ROAM := 4.0

## The critical path, in order. Area i is AREAS[i]: its enemies are met after the areas before it.
const AREAS: Array[String] = ["entry", "corridor_1", "hall_1", "corridor_2", "hall_2", "corridor_3", "hall_3", "corridor_4", "hall_4",
		"corridor_5", "hall_5"]

## The way through the dungeon, door to door, as the hero walks it (x, z): the pack generator spaces packs along it and the pacing tests walk it.
const CRITICAL_PATH: Array[Vector2] = [Vector2(0, 104), Vector2(9, 96), Vector2(9, 64), Vector2(-25, 64), Vector2(-25, 31), Vector2(25, 31),
		Vector2(25, -6), Vector2(-29, -6), Vector2(-29, -52), Vector2(21, -52), Vector2(21, -99), Vector2(0, -99)]
## Curse pacing: the longest walk (m) along CRITICAL_PATH with no pack in view, from the shared walking-gap budget and the hero's run speed.
## A pack counts as "in view" within PACK_VIEW_RANGE metres of the hero.
const PACK_VIEW_RANGE := 14.0
const MAX_WALK_GAP := RoadEncounterRoster.MAX_WALK_SECONDS_BETWEEN_PACKS * RoadEncounterRoster.HERO_RUN_SPEED

## DS2 tier of each kind as spawned here (the same tier its XP and life use: see Enemy.tier_override).
const KIND_TIER := {"zombie": "trivial", "ghoul": "weak", "rock_thrower": "weak", "brute": "strong", "warden": "miniboss"}

var _enemy_group_id: int = 300
var level: Node3D    # the loaded scene's root
var groups: Array = []   # the enemy groups read from the scene: {area, mode, home (Vector2), kinds}


## The arena for this location: the dungeon's rectangle, no random scatter, and no navigation mesh yet (build() adds props first).
static func make_arena() -> Arena:
	var a := Arena.new()
	a.half_x = ARENA_HALF_X
	a.half_z = ARENA_HALF_Z
	a.scatter = false
	return a



## Where the hero begins: the scene's PlayerStart (the entry hall's south end).
func start_position() -> Vector3:
	if level != null and level.has_node("PlayerStart"):
		return (level.get_node("PlayerStart") as Node3D).global_position
	return START_POINT


## Loads the level scene and wires it up, then the one navigation bake. Called once the arena is built without navigation.
func build(for_arena: Arena) -> void:
	arena = for_arena
	in_world = false
	add_to_group("test_dungeon")   # the HUD names the zone from it
	_rng.seed = 2525
	_black_out_ground()
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as Node3D
	var nav: NavigationRegion3D = arena.get("_nav_region")
	nav.add_child(level)   # under the navigation region, so the one bake sees the walls, props and rock
	for group in level.get_children():
		match String(group.name):
			"Floor", "Walls", "Pillars", "Props", "Torches":
				for holder in group.get_children():
					_adopt(holder)
			"Chests":
				for chest in group.get_children():   # chests stand outside the navigation region, as they always did
					group.remove_child(chest)
					add_child(chest)
	groups = read_groups(level)
	level.get_node("EnemyGroups").queue_free()   # only read: the groups are spawned by spawn_encounters
	arena.bake_navigation()


## A prop of the scene: a breakable one comes alive (Destructible.adopt), and anything solid is registered as an obstacle.
func _adopt(holder: Node) -> void:
	if holder is Destructible:
		(holder as Destructible).adopt(arena)
	elif holder.has_meta("obstacle_radius"):
		arena.obstacles.append({"position": (holder as Node3D).global_position, "radius": float(holder.get_meta("obstacle_radius"))})


## Where a node stands in the world, worked out from its parents' transforms, so it works on a scene that is not in the tree (a global
## position asked of such a node is an engine error).
static func _world_origin(node: Node3D) -> Vector3:
	var transform := Transform3D.IDENTITY
	var walker: Node = node
	while walker is Node3D:
		transform = (walker as Node3D).transform * transform
		walker = walker.get_parent()
	return transform.origin


## The enemy groups a level scene holds, as rows: {area, level_offset, fixed_level, mode, home (the marker's position on the ground), kinds,
## spread, roam, spawns (Vector2s), patrol (Vector2s), feed (Vector2, or INF for none)}. See DungeonEnemyGroup.
static func read_groups(level_root: Node) -> Array:
	var rows: Array = []
	for marker in level_root.get_node("EnemyGroups").get_children():
		var group := marker as DungeonEnemyGroup
		if group == null:
			continue
		var feeds: Array[Vector2] = group.marker_points("FeedPoint")
		rows.append({"area": group.area, "level_offset": group.level_offset, "fixed_level": group.fixed_level, "mode": group.idle_mode(),
			"home": Vector2(_world_origin(group).x, _world_origin(group).z), "kinds": group.kinds.duplicate(true),
			"spread": group.spread, "roam": group.roam_radius, "spawns": group.marker_points("Spawn"), "patrol": group.marker_points("Patrol"),
			"feed": feeds[0] if not feeds.is_empty() else Vector2.INF})
	return rows


## The rooms are lit and the rest is dark: the arena's grey ground plane becomes black, so anything outside the walls reads as void.
func _black_out_ground() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.01, 0.01, 0.012)
	black.roughness = 1.0
	var nav: NavigationRegion3D = arena.get("_nav_region")
	for child in nav.get_children():
		if child is StaticBody3D:
			for mesh in child.get_children():
				if mesh is MeshInstance3D:
					(mesh as MeshInstance3D).material_override = black



## The enemies: every group stands where the scene's markers put it, at the level its area is projected to meet (see project()). Called by
## the director once the navigation map is ready. The levels are read from the hero's XP at this moment, so they follow the hero who loads.
func spawn_encounters(for_director: RunDirector) -> void:
	director = for_director
	var levels: PackedInt32Array = area_levels(TownState.hero_xp, groups)
	for group in groups:
		var home: Vector2 = group["home"]
		var level_here: int = int(group["fixed_level"])
		if level_here <= 0:
			level_here = maxi(levels[clampi(int(group["area"]), 0, levels.size() - 1)] + int(group["level_offset"]), 0)
		var spawns: Array = group["spawns"]
		var spread: float = float(group["spread"])
		var members: Array = []
		for pair in group["kinds"]:
			var kind: String = String(pair[0])
			for i in int(pair[1]):
				var spot: Vector2 = home + Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread))
				if members.size() < spawns.size():   # a Spawn marker for this member: it stands exactly there
					spot = spawns[members.size()]
				members.append([kind, spot.x, spot.y, level_here, String(KIND_TIER[kind])])
		var patrol: Array[Vector2] = []
		patrol.assign(group["patrol"])
		var feed: Vector2 = group["feed"]
		_enemy_group_id += 1
		_group(_enemy_group_id, String(group["mode"]), members, home, float(group["roam"]), feed if feed != Vector2.INF else Vector2.ZERO, patrol)


# --- The critical path -------------------------------------------------------------------------------------------------------------

## The length of CRITICAL_PATH (m).
static func path_length() -> float:
	var length: float = 0.0
	for i in CRITICAL_PATH.size() - 1:
		length += CRITICAL_PATH[i].distance_to(CRITICAL_PATH[i + 1])
	return length


## The point `distance` metres along CRITICAL_PATH from the start (clamped to its ends).
static func path_point(distance: float) -> Vector2:
	var left: float = maxf(distance, 0.0)
	for i in CRITICAL_PATH.size() - 1:
		var leg: float = CRITICAL_PATH[i].distance_to(CRITICAL_PATH[i + 1])
		if left <= leg:
			return CRITICAL_PATH[i].lerp(CRITICAL_PATH[i + 1], left / maxf(leg, 0.001))
		left -= leg
	return CRITICAL_PATH[CRITICAL_PATH.size() - 1]


## The longest stretch (m) of CRITICAL_PATH walked with no pack home within PACK_VIEW_RANGE, for packs standing at `homes` (x, z), sampled
## every metre from the start. Zero when a pack is in view the whole way.
static func longest_gap(homes: Array) -> float:
	var worst: float = 0.0
	var run: float = 0.0
	var total: float = path_length()
	var s: float = 0.0
	while s <= total:
		var here: Vector2 = path_point(s)
		var seen: bool = false
		for home in homes:
			if here.distance_to(home) <= PACK_VIEW_RANGE:
				seen = true
				break
		run = 0.0 if seen else run + 1.0
		worst = maxf(worst, run)
		s += 1.0
	return worst


# --- What the hero is projected to meet ------------------------------------------------------------------------------------------------

## Walks the critical path with the hero's XP `entry_xp` and returns one row per area: {area, level (the enemies' level there: the
## hero's projected level on arrival), xp (what the area's kills pay), xp_total, hero_level (after the area)}. Each kill pays
## HeroProgression.monster_xp for its level and tier, times the level-gap multiplier, shared over the party as the game does
## (RunDirector._pay_kill_xp). Every enemy of an area is counted as killed, and side spaces are counted with their area.
## The enemies of an area are at the level the hero has on arriving there, so the gap is never a penalty here.
## `enemy_groups` are the level's groups (rows of {area, kinds}: see read_groups).
static func project(entry_xp: int, enemy_groups: Array) -> Array:
	var rows: Array = []
	var xp: int = HeroProgression.sanitize_xp(entry_xp)
	for area in AREAS.size():
		var level_here: int = HeroProgression.level_for_xp(xp)
		var gained: int = 0
		for group in enemy_groups:
			if int(group["area"]) != area:
				continue
			for pair in group["kinds"]:
				var tier: String = String(KIND_TIER[String(pair[0])])
				for i in int(pair[1]):
					var kill: int = HeroProgression.monster_xp(level_here, tier)
					var gap: float = HeroProgression.level_gap_mult(HeroProgression.gap_level(HeroProgression.level_for_xp(xp)), level_here)
					var share: int = HeroProgression.party_share(int(round(float(kill) * gap)), PARTY_SIZE)
					var before: int = xp
					xp = mini(xp + share, HeroProgression.max_xp())
					gained += xp - before
		rows.append({"area": AREAS[area], "level": level_here, "xp": gained, "xp_total": xp, "hero_level": HeroProgression.level_for_xp(xp)})
	return rows


## The enemy level of each area (index into AREAS) for a hero with `entry_xp` XP at the start: see project().
static func area_levels(entry_xp: int, enemy_groups: Array) -> PackedInt32Array:
	var levels := PackedInt32Array()
	for row in project(entry_xp, enemy_groups):
		levels.append(int(row["level"]))
	return levels


## Brighter than the shared profile alone, so the rooms stay readable: enemies, props and loot must be easy to see. Called by main
## after the profile is applied, and only under --atmosphere.
func tune_look(environment: Environment) -> void:
	# Neutral enough that the warm sconces read as warm: the room stays bright, and the warmth comes from the torch pools.
	environment.ambient_light_color = Color(0.5, 0.51, 0.54)
	environment.ambient_light_energy = 0.55
	environment.fog_density = 0.008
	environment.background_mode = Environment.BG_COLOR   # no sky: beyond the walls is void
	environment.background_color = Color(0.0, 0.0, 0.0)
	# The warm lights (sconces, hearth) get a stronger pool of warm light. Their flicker keeps its own base energy, so the base is
	# set too, or the flicker would hand the old value back every frame.
	for node in arena.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if light.light_color.r <= light.light_color.g:
			continue
		light.light_color = Color(1.0, 0.56, 0.24)
		light.light_energy *= 1.5
		for child in light.get_children():
			if child is FlickerLight:
				(child as FlickerLight)._base = light.light_energy

