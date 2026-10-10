class_name Destructible
extends Node3D
## A prop in the arena that can be smashed: barrels and carts splinter, gravestones crack into slabs, braziers fall apart in a shower of
## embers. Anything that moves through one at speed (a Skewer charge, a Leap) sends the pieces flying along its path; ordinary swings,
## fireballs and explosions break them too. Some give something back when they go (a potion, a healing orb, now and then an item).
##
## The arena builds one of these for every prop named in STATS (see Arena._place); the shared `blast()` is how skills break them.

## prop -> hit points, what it is made of (decides the pieces), how many pieces, and what it may drop.
## "hero": the hero's own swings and skills break it (and clicking it sends them to swing at it), not only the big effects.
const STATS := {
	"barrel": {"hp": 10.0, "material": "wood", "chunks": 15, "orb": 0.2, "potion": 0.07, "item": 0.0, "hero": true},
	"wrecked_cart": {"hp": 45.0, "material": "wood", "chunks": 26, "orb": 0.0, "potion": 0.2, "item": 0.12},
	"gravestone": {"hp": 40.0, "material": "stone", "chunks": 13, "orb": 0.0, "potion": 0.0, "item": 0.14},
	"brazier": {"hp": 30.0, "material": "iron", "chunks": 12, "orb": 0.0, "potion": 0.0, "item": 0.0},
	# A corrupted nest (the Crypt Road's objective): tough, bursts into gore and a green cloud, and pays out well.
	"nest": {"hp": 140.0, "material": "flesh", "chunks": 24, "orb": 0.4, "potion": 0.25, "item": 0.4, "hero": true},
}
## Pass as `only_kind` to limit a blast or a search to the props the hero's own attacks break.
const HERO := "hero"

## Sent once when it is broken, with the prop (the Crypt Road counts its nests this way).
signal destroyed(prop: Destructible)

var prop_name: String = ""
var hp: float = 1.0
var max_hp: float = 1.0
var broken: bool = false
var radius: float = 0.5       # how far from the centre its footprint reaches (flat)
var height: float = 1.0
var arena: Arena
var obstacle: Dictionary = {}

var _visual: Node3D
var _body: StaticBody3D
var _light: Light3D
var _wobble_tween: Tween

func configure(owner_arena: Arena, name_of_prop: String, visual: Node3D, body: StaticBody3D, light: Light3D, obstacle_entry: Dictionary,
		footprint: float, prop_height: float) -> void:
	arena = owner_arena
	prop_name = name_of_prop
	_visual = visual
	_body = body
	_light = light
	obstacle = obstacle_entry
	radius = footprint
	height = prop_height
	max_hp = float(STATS[name_of_prop]["hp"])
	hp = max_hp
	add_to_group("destructibles")
	if name_of_prop == "nest":
		add_to_group("nests")

func _is_kind(only_kind: String) -> bool:
	if only_kind == "" or only_kind == prop_name:
		return true
	return only_kind == HERO and bool(STATS[prop_name].get("hero", false))

# --- Breaking things -----------------------------------------------------------------------------------------------------------

## Every unbroken prop within `radius` (measured from the edge of its footprint) takes `damage`. `dir` is the way things are moving
## (zero: outward from `center`) and `force` how hard they are thrown: about 1 for a swing, 2 or more for a charge or a leap.
## `only_kind` limits it to one kind of prop, or to `HERO` (what the hero's own swings break: barrels and nests). Returns how many were broken.
static func blast(tree: SceneTree, center: Vector3, blast_radius: float, damage: float, dir: Vector3 = Vector3.ZERO, force: float = 1.0,
		only_kind: String = "") -> int:
	var broken_count: int = 0
	for node in tree.get_nodes_in_group("destructibles"):
		var prop := node as Destructible
		if prop == null or prop.broken or not prop._is_kind(only_kind):
			continue
		var offset: Vector3 = prop.global_position - center
		offset.y = 0.0
		if offset.length() - prop.radius > blast_radius:
			continue
		var push: Vector3 = dir
		push.y = 0.0
		if push.length() < 0.05:
			push = offset.normalized() if offset.length() > 0.05 else Vector3.FORWARD
		if prop.hit(damage, push.normalized(), force):
			broken_count += 1
	return broken_count

## The unbroken prop whose footprint is closest to a ground point, within `margin` metres of it.
static func near(tree: SceneTree, point: Vector3, margin: float, only_kind: String = "") -> Destructible:
	var best: Destructible = null
	var best_gap: float = margin
	for node in tree.get_nodes_in_group("destructibles"):
		var prop := node as Destructible
		if prop == null or prop.broken or not prop._is_kind(only_kind):
			continue
		var offset: Vector3 = prop.global_position - point
		offset.y = 0.0
		var gap: float = offset.length() - prop.radius
		if gap < best_gap:
			best_gap = gap
			best = prop
	return best

## Damage it. Returns true if that broke it.
func hit(damage: float, dir: Vector3, force: float = 1.0) -> bool:
	if broken:
		return false
	hp -= damage
	if hp <= 0.0:
		shatter(dir, force)
		return true
	_chip(dir)
	return false

## A hit that does not finish it: it shudders and spits a few chips and a puff of dust.
func _chip(dir: Vector3) -> void:
	if _visual == null:
		return
	if _wobble_tween != null and _wobble_tween.is_valid():
		_wobble_tween.kill()
		_visual.rotation = Vector3.ZERO
	_wobble_tween = create_tween()
	var tilt := Vector3(dir.z, 0.0, -dir.x) * 0.1
	_wobble_tween.tween_property(_visual, "rotation", tilt, 0.05)
	_wobble_tween.tween_property(_visual, "rotation", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var palette: Color = _dust_color()
	Fx.burst(self, global_position + Vector3(0, height * 0.5, 0), dir + Vector3.UP * 0.6, palette, 5, 3.0, 0.025)
	for i in 3:
		_spawn_chunk(dir, 0.6, 0.7)

## It goes: pieces fly out (further and faster the harder it was hit), dust rises, the camera jolts, and it may leave something.
func shatter(dir: Vector3, force: float = 1.0) -> void:
	if broken:
		return
	broken = true
	remove_from_group("destructibles")
	var centre: Vector3 = global_position
	var stats: Dictionary = STATS[prop_name]
	for i in int(stats["chunks"]):
		_spawn_chunk(dir, force, 1.0)
	var palette: Color = _dust_color()
	Fx.burst(self, centre + Vector3(0, height * 0.4, 0), Vector3.UP + dir * force * 0.5, palette, int(12 + 6 * force), 4.0 + 2.0 * force, 0.032)
	if String(stats["material"]) == "iron":
		Fx.burst(self, centre + Vector3(0, height * 0.6, 0), Vector3.UP, Color(1.0, 0.55, 0.15), 22, 6.0, 0.03, true)
		Fx.light_flash(self, centre + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 2.5, 0.35)
	if String(stats["material"]) == "stone":
		Fx.ring(self, centre + Vector3(0, 0.05, 0), 0.9 + force * 0.25, Color(0.6, 0.58, 0.52))
	if String(stats["material"]) == "flesh":   # the sacs burst: a cloud of the sickly green the spitters use, and a dying glow
		Fx.burst(self, centre + Vector3(0, height * 0.7, 0), Vector3.UP, Color(0.4, 0.5, 0.15), 26, 4.5, 0.05)
		Fx.light_flash(self, centre + Vector3(0, 1.2, 0), Color(0.5, 0.75, 0.2), 2.2, 0.5)
		Fx.ring(self, centre + Vector3(0, 0.05, 0), 1.6 + force * 0.25, Color(0.3, 0.38, 0.12))
	Fx.shake(self, 0.03 + 0.03 * force)
	_drop_loot(stats)
	destroyed.emit(self)
	if arena != null:
		arena.obstacles.erase(obstacle)
		arena.request_nav_refresh()
	if _body != null:
		_body.queue_free()
	if _light != null:
		_light.queue_free()
	if _visual != null:
		_visual.queue_free()
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _dust_color() -> Color:
	match String(STATS[prop_name]["material"]):
		"stone":
			return Color(0.34, 0.33, 0.31)
		"iron":
			return Color(0.2, 0.19, 0.18)
		"flesh":
			return Color(0.22, 0.12, 0.09)
	return Color(0.28, 0.2, 0.12)

## One flying piece, made to look like what broke: splintered planks, jagged stone, scraps of iron (a few still glowing).
func _spawn_chunk(dir: Vector3, force: float, scale_factor: float) -> void:
	var chunk := DebrisChunk.new()
	var material: String = String(STATS[prop_name]["material"])
	var size: Vector3
	var color: Color
	var glow: bool = false
	match material:
		"stone":
			size = Vector3(randf_range(0.1, 0.26), randf_range(0.07, 0.2), randf_range(0.1, 0.24)) * scale_factor
			color = Color(0.33, 0.33, 0.35) * randf_range(0.7, 1.15)
		"iron":
			size = Vector3(randf_range(0.04, 0.16), randf_range(0.03, 0.1), randf_range(0.04, 0.14)) * scale_factor
			color = Color(0.17, 0.15, 0.14) * randf_range(0.7, 1.2)
			glow = randf() < 0.18
		"flesh":   # clots of gore, and now and then a splinter of bone
			if randf() < 0.25:
				size = Vector3(0.03, 0.03, randf_range(0.18, 0.4)) * scale_factor
				color = Color(0.55, 0.5, 0.4) * randf_range(0.7, 1.0)
			else:
				size = Vector3(randf_range(0.08, 0.2), randf_range(0.06, 0.14), randf_range(0.08, 0.2)) * scale_factor
				color = Color(0.24, 0.09, 0.08) * randf_range(0.6, 1.2)
		_:
			if prop_name == "barrel" and randf() < 0.2:
				size = Vector3(0.025, 0.02, randf_range(0.25, 0.4)) * scale_factor     # a bent iron hoop
				color = Color(0.2, 0.15, 0.12)
			else:
				size = Vector3(randf_range(0.04, 0.09), randf_range(0.025, 0.05), randf_range(0.22, 0.55)) * scale_factor
				color = Color(0.3, 0.2, 0.11) * randf_range(0.65, 1.1)
	chunk.setup(size, color, glow)
	if arena != null:
		chunk.limit = Vector2(arena.half_x, arena.half_z) - Vector2(0.6, 0.6)
		chunk.limit_centre = arena.origin_offset
	get_tree().current_scene.add_child(chunk)
	var start := global_position + Vector3(randf_range(-radius, radius) * 0.6, randf_range(0.1, maxf(height, 0.4)), randf_range(-radius, radius) * 0.6)
	chunk.global_position = start
	var scatter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	var out: Vector3 = dir * randf_range(3.0, 7.5) * force + scatter * randf_range(1.5, 4.0)
	chunk.velocity = out + Vector3.UP * randf_range(2.5, 6.0) * (0.7 + 0.4 * force)
	chunk.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)) * force

func _drop_loot(stats: Dictionary) -> void:
	var roll: float = randf()
	var scene: Node = get_tree().current_scene
	var at: Vector3 = global_position + Vector3(0, 0.1, 0)
	if roll < float(stats["potion"]) or roll < float(stats["orb"]) + float(stats["potion"]):
		var orb := HealthOrb.new()
		orb.is_potion = roll < float(stats["potion"])
		scene.add_child(orb)
		orb.global_position = at
		return
	roll = randf()
	if roll < float(stats["item"]):
		var director: Node = get_tree().get_first_node_in_group("director")
		if director != null and director.has_method("drop_item"):
			director.drop_item(at, Items.roll_drop(director.drop_tier_at(at), 0.0, director.owned_uniques()))
