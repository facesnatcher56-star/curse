class_name MonsterMark
extends RefCounted
## What shows a named monster out on the road: the ember diamond over its head (red for a nemesis), its name and title in small letters
## above it, and for a nemesis a low red glow around its feet. It also grows with its level (see `apply`).

const GROW_PER_LEVEL := 0.05

## Puts (or redoes) the marks on a monster's body and records which named monster it is.
static func attach(enemy: Enemy, mon: Dictionary) -> void:
	enemy.set_meta("monster_uid", int(mon["uid"]))
	enemy.set_meta("mark_tag", Monsters.tag_of(mon) + ("!" if bool(mon.get("nemesis", false)) else ""))
	for child in enemy.get_children():
		if child.has_meta("monster_mark"):
			enemy.remove_child(child)
			child.queue_free()
	var nemesis: bool = bool(mon.get("nemesis", false))
	var tint: Color = Color(0.9, 0.18, 0.12) if nemesis else Color(1.0, 0.45, 0.15)
	var diamond: Sprite3D = QuestMarker.attach(enemy)
	diamond.modulate = tint
	diamond.set_meta("monster_mark", true)
	var label := Label3D.new()
	label.set_meta("monster_mark", true)
	label.text = Monsters.tag_of(mon)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.shaded = false
	label.pixel_size = 0.0007
	label.font_size = 44
	label.outline_size = 12
	label.modulate = Color(1.0, 0.85, 0.65) if not nemesis else Color(1.0, 0.6, 0.55)
	label.outline_modulate = Color(0.04, 0.03, 0.03)
	label.position = Vector3(0, 3.55, 0)
	label.visibility_range_end = 70.0
	enemy.add_child(label)
	if nemesis:
		var glow := OmniLight3D.new()
		glow.set_meta("monster_mark", true)
		glow.light_color = Color(1.0, 0.25, 0.12)
		glow.light_energy = 1.4
		glow.omni_range = 5.0
		glow.position = Vector3(0, 0.6, 0)
		enemy.add_child(glow)
		var flicker := FlickerLight.new()
		glow.add_child(flicker)

## Sets a named monster's strength from its level: tougher, harder-hitting and bigger the more it has grown. Measured from the body it
## was born with (kept in meta), so it can be redone every day without compounding.
static func apply(enemy: Enemy, mon: Dictionary) -> void:
	if not enemy.has_meta("base_health"):
		enemy.set_meta("base_health", enemy.max_health)
		enemy.set_meta("base_damage", Vector2(enemy.damage_min, enemy.damage_max))
		enemy.set_meta("base_scale", enemy.visual.scale if enemy.visual != null else Vector3.ONE)
	var grown: float = float(mon["level"]) - 1.0
	var fraction: float = enemy.health / maxf(enemy.max_health, 1.0)
	enemy.max_health = float(enemy.get_meta("base_health")) * (1.0 + 0.55 * grown)
	enemy.health = enemy.max_health * fraction
	var base_damage: Vector2 = enemy.get_meta("base_damage")
	enemy.damage_min = base_damage.x * (1.0 + 0.15 * grown)
	enemy.damage_max = base_damage.y * (1.0 + 0.15 * grown)
	if enemy.visual != null:
		enemy.visual.scale = (enemy.get_meta("base_scale") as Vector3) * minf(1.15 + GROW_PER_LEVEL * grown, 1.7)
