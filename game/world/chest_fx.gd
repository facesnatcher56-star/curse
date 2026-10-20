class_name ChestFx
extends RefCounted
## The moment a map-mode chest gives up its loot (issue #87): every item flies out under a beam in its rarity colour with a short sound of its
## own (the sounds are the project's recordings, pitched per rarity); a legendary gets a taller, wider beam, a ground ring, a low boom and a
## brief slow-motion beat. The beams are brief (the owner wants no permanent beams on the ground: LootDrop.GROUND_HIGHLIGHTS stays off).

## How a rarity looks and sounds: {beam_height, beam_radius, seconds, sound, db, pitch}. Index = a tier: 0 normal, 1 magic, 2 rare, 3 unique/set, 4 legendary.
const TIERS: Array[Dictionary] = [
	{"height": 0.0, "radius": 0.0, "seconds": 0.0, "sound": "sword_miss_1", "db": -12.0, "pitch": 1.9},
	{"height": 3.2, "radius": 0.07, "seconds": 1.1, "sound": "fireball_cast_1", "db": -9.0, "pitch": 1.7},
	{"height": 4.4, "radius": 0.1, "seconds": 1.5, "sound": "sword_hit", "db": -5.0, "pitch": 1.35},
	{"height": 5.5, "radius": 0.13, "seconds": 1.8, "sound": "fireball_cast_2", "db": -3.0, "pitch": 1.0},
	{"height": 9.0, "radius": 0.24, "seconds": 2.6, "sound": "fireball_impact", "db": 1.0, "pitch": 0.7},
]
const STAGGER := 0.11   # s between one item's sound and the next
const SLOWMO_SCALE := 0.3
const SLOWMO_HOLD := 0.55

## An item's tier in TIERS.
static func tier_of(item: Dictionary) -> int:
	if MapModeLegendaries.id_of(item) != "":
		return 4
	return clampi(int(item["rarity"]), 0, 3)

static func beam_color(item: Dictionary) -> Color:
	return MapModeLegendaries.BEAM_COLOR if MapModeLegendaries.id_of(item) != "" else (Items.RARITY_COLORS[int(item["rarity"])] as Color).lightened(0.15)

## Starts the show for `drops` (the LootDrops a chest just threw out).
static func play(chest: Node3D, drops: Array) -> void:
	var order: int = 0
	var legendary: bool = false
	for drop in drops:
		var d := drop as LootDrop
		if d == null or not is_instance_valid(d):
			continue
		var tier: int = tier_of(d.item)
		attach_beam(d, tier, beam_color(d.item))
		_sound_later(chest, tier, float(order) * STAGGER)
		order += 1
		legendary = legendary or tier == 4
	if legendary:
		Fx.ring(chest, chest.global_position, 3.4, MapModeLegendaries.BEAM_COLOR)
		Fx.shake(chest, 0.25)
		Fx.slowmo(chest, SLOWMO_SCALE, SLOWMO_HOLD)

static func _sound_later(chest: Node3D, tier: int, delay: float) -> void:
	var def: Dictionary = TIERS[tier]
	if delay > 0.0:
		await chest.get_tree().create_timer(delay, true, false, true).timeout
	if is_instance_valid(chest):
		Sfx.sample(chest, String(def["sound"]), float(def["db"]), float(def["pitch"]))

## A beam over a drop that rides with it as it lands and fades out; none for a plain item.
static func attach_beam(drop: LootDrop, tier: int, colour: Color) -> MeshInstance3D:
	var def: Dictionary = TIERS[tier]
	if float(def["height"]) <= 0.0:
		return null
	var beam := MeshInstance3D.new()
	beam.name = "RewardBeam"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = float(def["radius"]) * 0.45
	cylinder.bottom_radius = float(def["radius"])
	cylinder.height = float(def["height"])
	cylinder.radial_segments = 10
	beam.mesh = cylinder
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.0)
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = float(cylinder.height) * 0.5
	drop.add_child(beam)
	var peak: float = 0.5 if tier == 4 else 0.38
	var tween := beam.create_tween()
	tween.tween_property(mat, "albedo_color:a", peak, 0.15)
	tween.tween_interval(maxf(float(def["seconds"]) - 0.65, 0.1))
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(beam.queue_free)
	return beam
