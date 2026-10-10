class_name Ds2PartyFrame
extends Control
## Dungeon Siege II-style party cards panel.
## Manages Hero and Companion cards at top-left.

const Ds2PartyCardClass := preload("res://game/ui/ds2_party_card.gd")

var player: Player
var hero_card: Control
var companion_card: Control

const KNIGHT_PORTRAIT := preload("res://assets/ui/busts/knight.png")
const ARCHER_PORTRAIT := preload("res://assets/ui/busts/priest.png")
const BASIC_ICON := preload("res://assets/icons/basic.png")
const BRUTAL_ICON := preload("res://assets/icons/brutal_attack.png")
const TAKE_AIM_ICON := preload("res://assets/icons/take_aim.png")

func _init() -> void:
	custom_minimum_size = Vector2(300, 200)
	size = Vector2(300, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	# Position flush at top-left
	position = Vector2(2, 2)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	hero_card = Ds2PartyCardClass.new("Hero", false)
	box.add_child(hero_card)

	companion_card = Ds2PartyCardClass.new("Cutter (Archer)", true)
	companion_card.visible = false
	box.add_child(companion_card)

	hero_card.set_portrait(KNIGHT_PORTRAIT)
	hero_card.set_icons(BASIC_ICON, BRUTAL_ICON)

	companion_card.set_portrait(ARCHER_PORTRAIT)
	companion_card.set_icons(BASIC_ICON, TAKE_AIM_ICON)

func update_frame(p: Player) -> void:
	if p == null:
		return
	player = p

	# 1. Update Hero Card
	var hp_pct: float = p.health / maxf(p.max_health, 0.001)
	var mana_pct: float = p.stats.mana / maxf(p.stats.max_mana, 0.001)
	var xp_pct: float = HeroProgression.level_fraction(TownState.hero_xp)
	
	var brutal_charge: float = p.stats.ult_fraction("brutal_attack")
	hero_card.update_vitals(hp_pct, mana_pct, xp_pct, brutal_charge)

	# 2. Update Companion Card (Cutter)
	var cutter: Node = p.stats._cutter()
	if cutter != null and is_instance_valid(cutter) and not bool(cutter.get("dead")):
		companion_card.visible = true
		var c_hp_pct: float = float(cutter.get("health")) / maxf(float(cutter.get("max_health")), 0.001)
		var c_mana_pct: float = 1.0
		var c_xp_pct: float = xp_pct
		var take_aim_charge: float = 1.0
		var reload_req: float = float(cutter.get("take_aim_reload_required"))
		var reload_rem: float = float(cutter.get("take_aim_reload_remaining"))
		if reload_req > 0.0:
			take_aim_charge = clampf(1.0 - reload_rem / maxf(reload_req, 0.001), 0.0, 1.0)
		companion_card.update_vitals(c_hp_pct, c_mana_pct, c_xp_pct, take_aim_charge)
	else:
		companion_card.visible = false
