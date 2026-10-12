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

	companion_card = Ds2PartyCardClass.new("Cutter", true)
	companion_card.visible = false
	box.add_child(companion_card)

	hero_card.set_portrait(KNIGHT_PORTRAIT)
	hero_card.set_icons(BASIC_ICON, BRUTAL_ICON)

	companion_card.set_portrait(ARCHER_PORTRAIT)
	companion_card.set_icons(BASIC_ICON, TAKE_AIM_ICON)

func update_frame(p: Player) -> void:
	if p == null: return
	player = p
	var party := PartyManager.current()
	_update_card(hero_card, party.bodies.get("hero") as Player)
	_update_card(companion_card, party.bodies.get("cutter") as Player)

func _update_card(card: Control, body: Player) -> void:
	card.visible = is_instance_valid(body)
	if not is_instance_valid(body): return
	var power_id := "take_aim" if body.stats.is_ranged() else "brutal_attack"
	card.set_icons(BASIC_ICON, TAKE_AIM_ICON if power_id == "take_aim" else BRUTAL_ICON)
	card.update_vitals(body.health / maxf(body.max_health, 0.001),
		body.stats.mana / maxf(body.stats.max_mana, 0.001), HeroProgression.level_fraction(body.character.xp),
		body.stats.ult_fraction(power_id), preload("res://game/ui/power_button_visual.gd").armed(body, power_id),
		not body.dead and body.stats.can_use(power_id))
	card.tooltip_text = "%s — Level %d\n%s\n%s\nSelect this party member" % [
		body.display_name, body.character.level, HeroProgression.progress_text(body.character.xp),
		"Fallen" if body.dead else ("Active" if body.is_controlled() else "Companion")]
	card.queue_redraw()
