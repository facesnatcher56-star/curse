class_name Champion
extends RefCounted
## A champion: one tougher, named enemy in a pack, with ONE affix from AFFIXES. Curse's own addition (not a Dungeon Siege II mechanic; see
## docs/COMBAT_REFERENCE.md, "Champions"). An enemy with a champion keeps `Enemy.champion` pointing here; the Enemy calls `filter_incoming`,
## `tick` and `on_death` at the right moments, so an affix never needs its own code path in combat.
##
## Hooks for other spawners (Lane J's dungeon): `roll_pack(members)` gives a pack its chance of a champion; `attach(enemy, affix_id)` makes
## one champion directly; `loot(level, tier, magic_find)` is its guaranteed drop. Every number here is a tunable, not a verified DS2 value.

## Each affix is one entry; add more here. Keys read by the affix code: speed (move speed multiplier); shield (fraction of its life it
## soaks before taking damage); summon_interval, summon_count, summon_max (adds per cast, seconds between casts, adds alive at once);
## blast_delay, blast_radius, blast_mult (telegraph seconds, metres, and a multiple of its average blow for the hero). `effect` is the one plain
## line the target banner, the map-mode tooltip and the world marker show for the affix (ONE source; keep it true to the numbers above).
const AFFIXES := {
	"fast": {"title": "Swift", "color": Color(0.45, 0.85, 1.0), "speed": 1.5,
		"effect": "Moves 50% faster"},
	"shielded": {"title": "Warded", "color": Color(0.6, 0.75, 1.0), "shield": 0.35,
		"effect": "Shield absorbs damage. Break it with powers"},
	"summoner": {"title": "Summoning", "color": Color(0.7, 0.95, 0.35), "summon_interval": 10.0, "summon_count": 2, "summon_max": 4,
		"effect": "Calls zombies when the fight starts"},
	"explodes": {"title": "Volatile", "color": Color(1.0, 0.55, 0.15), "blast_delay": 1.3, "blast_radius": 3.0, "blast_mult": 1.8,
		"effect": "Explodes when it dies. Step away"},
}

## Every champion is tougher than its kind: life and average blow multiplied by these.
const LIFE_MULT := 2.5
const DAMAGE_MULT := 1.25
## A pack gets a champion this often (each pack rolls once), and only from members at or above MIN_LEVEL that are not trivial. Trivial
## openers therefore never carry one. Tests may set `chance_override`.
const PACK_CHANCE := 0.12
const MIN_LEVEL := 2
static var chance_override: float = -1.0
## The guaranteed drop: a rare with this chance, otherwise a magic item (one or two modifiers, evenly).
const RARE_CHANCE := 0.3
## Adds a summoner makes are renewable, so they pay no XP (the same rule as a Plague Priest's zombies).
const SUMMON_KIND := "zombie"

var affix_id: String = ""
var affix: Dictionary = {}
## Further affixes beyond `affix_id` (a later Curse level may roll 2-3). Display only for now: the banner shows one chip per id in `affix_ids()`.
var extra_ids: Array = []
var shield: float = 0.0
var shield_max: float = 0.0
var summon_cd: float = 0.0
var adds: Array = []
## A summoner calls its adds ONCE per fight; cleared only when the fight is over (the hero has left), so killing adds never brings more.
## The enemy's name before the affix title was put in front of it; the target banner shows the title as a tag instead.
var base_name: String = ""
var has_summoned: bool = false
var _bubble: MeshInstance3D = null
## Map mode only (MapModeRules): when a power last hit this champion, in MapMode.now() seconds.
var last_power_hit: float = -1000.0

## Every affix this champion shows, first the one it acts on.
func affix_ids() -> Array:
	return [affix_id] + extra_ids

## The effect lines of `ids` as "Title: effect" text, one per line (map-mode tooltip).
static func effect_text(ids: Array) -> String:
	var lines: PackedStringArray = []
	for id in ids:
		if AFFIXES.has(id):
			lines.append("%s: %s" % [AFFIXES[id].title, AFFIXES[id].effect])
	return "
".join(lines)

## Rolls one champion for a freshly spawned pack. Returns the champion's enemy, or null when this pack gets none.
static func roll_pack(members: Array) -> Enemy:
	var chance: float = PACK_CHANCE if chance_override < 0.0 else chance_override
	var eligible: Array[Enemy] = []
	for node in members:
		var e := node as Enemy
		if e != null and not e.dead and e.level >= MIN_LEVEL and e.def != null and e.def.tier != "trivial" and not e.tutorial_fighter:
			eligible.append(e)
	# No random draw at all when nothing can happen: a pack that gets no champion must not shift the random stream other spawns use.
	if chance <= 0.0 or eligible.is_empty() or randf() >= chance:
		return null
	var chosen: Enemy = eligible[randi() % eligible.size()]
	attach(chosen, AFFIXES.keys()[randi() % AFFIXES.size()])
	return chosen

## Makes `enemy` a champion with `affix_id`: tougher, marked, and its affix armed. Call it after the enemy is in the tree.
static func attach(enemy: Enemy, affix_id: String) -> Champion:
	if not AFFIXES.has(affix_id) or enemy.champion != null:
		return enemy.champion
	var c := Champion.new()
	c.affix_id = affix_id
	c.affix = AFFIXES[affix_id]
	enemy.champion = c
	enemy.max_health *= LIFE_MULT
	enemy.health = enemy.max_health
	enemy.damage_min *= DAMAGE_MULT
	enemy.damage_max *= DAMAGE_MULT
	c.base_name = enemy.display_name
	enemy.display_name = "%s %s" % [c.affix.title, enemy.display_name]
	enemy.move_speed *= float(c.affix.get("speed", 1.0))
	if c.affix.has("shield"):
		c.shield_max = enemy.max_health * float(c.affix.shield)
		c.shield = c.shield_max
		c._build_bubble(enemy)
	c.summon_cd = float(c.affix.get("summon_interval", 0.0)) * 0.5
	c._build_marks(enemy)
	return c

## What a champion always drops, on top of the pack's ordinary loot: a magic item or better, a rare one more often than an ordinary body.
static func loot(level: int, tier: String, magic_find: float = 0.0) -> Dictionary:
	var key: String = "weak" if tier == "trivial" else tier
	var table: Dictionary = Items.DROPS.get(key, Items.DROPS.normal)
	var kind: String = "rare" if randf() < RARE_CHANCE else ("magic2" if randf() < 0.5 else "magic1")
	return Items.item_of_kind(kind, level, table.window, Vector2i.ZERO, magic_find)

# --- combat hooks (called by Enemy) ---------------------------------------------------------------------------------------------

## The shield soaks damage before the body does. Returns the result to apply (a copy when anything was absorbed).
func filter_incoming(enemy: Enemy, result: Dictionary) -> Dictionary:
	var damage: float = float(result.get("damage", 0.0))
	if MapMode.active and MapModeRules.is_power_hit(result):
		last_power_hit = MapMode.now()   # a power hit pauses the shield's regeneration (map mode)
	if shield <= 0.0 or damage <= 0.0:
		return result
	var absorbed: float = minf(shield, damage)
	shield -= absorbed
	var out: Dictionary = result.duplicate()
	out["damage"] = damage - absorbed
	if shield <= 0.0:
		Fx.text_at(enemy, enemy.global_position + Vector3(0, 2.2, 0), "Shield broken", Color(0.7, 0.9, 1.0), 36)
		if _bubble != null:
			_bubble.visible = false
		Fx.burst(enemy, enemy.global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(0.7, 0.9, 1.0), 30, 6.0, 0.04, true)
	else:
		Fx.text_at(enemy, enemy.global_position + Vector3(0, 2.2, 0), "Shielded", Color(0.7, 0.9, 1.0), 30)
		_update_bubble()
	return out

## Per-frame affix work: a summoner calls its adds while it is awake.
func tick(enemy: Enemy, delta: float) -> void:
	if MapMode.active and shield_max > 0.0:
		MapModeRules.regen_step(self, delta, MapMode.now())
	if affix_id != "summoner" or not enemy._aggro or enemy.dead:
		return
	adds = adds.filter(func(a) -> bool: return is_instance_valid(a) and not a.dead)
	if has_summoned:
		if enemy.fight_over(delta):
			has_summoned = false
			summon_cd = float(affix.get("summon_interval", 10.0)) * 0.5
		return
	summon_cd -= delta
	if summon_cd > 0.0:
		return
	has_summoned = true
	var director: Node = enemy.get_tree().get_first_node_in_group("director")
	if director == null:
		return
	for i in int(affix.get("summon_count", 2)):
		var angle: float = randf() * TAU
		var spot: Vector3 = Nav.snap(enemy, enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.2, 3.0))
		var add: Enemy = director.spawn_enemy(spot, SUMMON_KIND, enemy.level_scale, "trivial")
		add.xp_eligible = false
		add.stun_time = 0.9   # clawing out of the ground
		add.wake()
		var tween: Tween = add.create_tween()
		add.visual.position.y = -1.2
		tween.tween_property(add.visual, "position:y", 0.0, 0.9)
		adds.append(add)

## An exploding champion marks the ground round it and, after a delay, blows up. The hero (and anything else close) takes damage.
func on_death(enemy: Enemy) -> void:
	for add in adds:
		if is_instance_valid(add):
			add.dismiss_summon()
	adds.clear()
	if affix_id != "explodes":
		return
	var centre: Vector3 = enemy.global_position
	var radius: float = float(affix.get("blast_radius", 3.0))
	var delay: float = float(affix.get("blast_delay", 1.3))
	var damage: float = enemy.average_hit() * float(affix.get("blast_mult", 1.8))
	var scene: Node = enemy.get_tree().current_scene
	_telegraph_ring(scene, centre, radius, delay)
	enemy.get_tree().create_timer(delay).timeout.connect(Champion._detonate.bind(enemy, centre, radius, damage))

static func _detonate(enemy: Enemy, centre: Vector3, radius: float, damage: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	var tree: SceneTree = enemy.get_tree()
	var scene: Node = tree.current_scene
	Fx.light_flash(scene, centre + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 6.0, 0.35)
	Fx.ring(scene, centre, radius * 1.2, Color(1.0, 0.6, 0.25))
	Fx.burst(scene, centre + Vector3(0, 1.0, 0), Vector3.UP, Color(1.0, 0.6, 0.2), 50, 9.0, 0.045, true)
	Fx.shake(scene, 0.3)
	for node in tree.get_nodes_in_group("player"):
		_blast(enemy, node as Actor, centre, radius, damage)
	for node in tree.get_nodes_in_group("enemies"):
		var other := node as Actor
		if other != null and other != enemy and not other.dead:
			_blast(enemy, other, centre, radius, damage * 0.5)

static func _blast(source: Enemy, actor: Actor, centre: Vector3, radius: float, damage: float) -> void:
	if actor == null or actor.dead:
		return
	var gap: Vector3 = actor.global_position - centre
	gap.y = 0.0
	if gap.length() > radius + actor.body_radius * 0.5:
		return
	var falloff: float = 1.0 - clampf(gap.length() / (radius + 0.01), 0.0, 1.0) * 0.5
	var result: Dictionary = Combat.resolve(source, actor, damage * falloff, Combat.DamageType.PHYSICAL, false, 1.2)
	result["secondary"] = true
	result["aoe"] = true   # an explosion: never auto-blocked (ShieldGuard)
	actor.receive(result, centre)

# --- what it looks like ---------------------------------------------------------------------------------------------------------

## A soft light in its affix's colour at its chest: visible from across the road. Its name is shown in the target banner, not over its head.
func _build_marks(enemy: Enemy) -> void:
	var color: Color = affix.color
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 0.7
	glow.omni_range = 3.2
	glow.position = Vector3(0, enemy.def.height * 0.55, 0)
	glow.set_meta("champion_mark", true)
	enemy.add_child(glow)

## The shield is a faint sphere round the body; it fades as the shield wears down and is gone when it breaks.
func _build_bubble(enemy: Enemy) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = maxf(enemy.body_radius, 0.4) + 0.35
	sphere.height = sphere.radius * 2.0
	_bubble = MeshInstance3D.new()
	_bubble.mesh = sphere
	_bubble.material_override = StandardMaterial3D.new()
	var mat := _bubble.material_override as StandardMaterial3D
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.8, 1.0, 0.3)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.position = Vector3(0, enemy.def.height * 0.5, 0)
	enemy.add_child(_bubble)

func _update_bubble() -> void:
	if _bubble == null:
		return
	var mat := _bubble.material_override as StandardMaterial3D
	var left: float = clampf(shield / maxf(shield_max, 0.001), 0.0, 1.0)
	mat.albedo_color.a = 0.05 + 0.2 * left

## The ground marker for the blast: a flat disc at the blast radius with a crisp ring on its edge, both fading in until the blast, then freed.
func _telegraph_ring(scene: Node, centre: Vector3, radius: float, delay: float) -> void:
	var root := Node3D.new()
	scene.add_child(root)
	root.global_position = Vector3(centre.x, 0.08, centre.z)
	root.add_to_group("aoe_tells")   # a blast is coming here (ShieldGuard keeps its shield down)
	root.set_meta("aoe_radius", radius)
	var disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.02
	disc.mesh = cylinder
	var fill := StandardMaterial3D.new()
	fill.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill.albedo_color = Color(1.0, 0.5, 0.15, 0.1)
	fill.no_depth_test = true   # the floor's relief would otherwise hide parts of the marker; kept faint
	disc.material_override = fill
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	var edge := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.94
	torus.outer_radius = radius
	edge.mesh = torus
	var rim := StandardMaterial3D.new()
	rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim.albedo_color = Color(1.0, 0.6, 0.2, 0.75)
	rim.no_depth_test = true
	edge.material_override = rim
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(edge)
	var tween := root.create_tween()
	tween.tween_property(fill, "albedo_color:a", 0.26, delay)
	root.get_tree().create_timer(delay + 0.05).timeout.connect(root.queue_free)
