class_name ArcherCompanion
extends Player
## Compatibility name for Cutter's presentation/startup data. Combat and control are inherited unchanged.
const MOVE_SPEED := 4.5
const BOW_MODEL := "res://assets/models/archer/bow/model.glb"
const QUIVER_MODEL := "res://assets/models/archer/quiver/model.glb"
const ARROW_MODEL := "res://assets/models/archer/arrow/model.glb"
const RANGE := 17.0
const MIN_COMBAT_RANGE := 8.0
const PREFERRED_COMBAT_RANGE := 12.0
const DRAW_TIME := 0.62
const SHOT_COOLDOWN := 1.05
const TAKE_AIM_COMBAT_SECONDS: float = PowerDb.CHARGE_SECONDS["take_aim"]
const TAKE_AIM_DRAW_TIME := BowAttack.TAKE_AIM_DRAW
const FOLLOW_DISTANCE := 4.8
const LEASH_DISTANCE := 6.0
const LEASH_STOP_DISTANCE := 3.5
const HARD_TETHER_DISTANCE := 16.0
const TELEPORT_TETHER_DISTANCE := 30.0
var player: Player
var testing_disabled: bool = false
var last_hit_target: Enemy
var shots_fired: int = 0
var target: Enemy
var manual_target: Enemy
var take_aim_armed: bool:
	get: return bow != null and bow.armed
	set(value):
		if bow != null: bow.armed = value
var take_aim_reload_required: float:
	get: return bow.reload_required if bow != null else 0.0
	set(value):
		if bow != null: bow.reload_required = value
var take_aim_reload_remaining: float:
	get: return bow.reload_remaining if bow != null else 0.0
	set(value):
		if bow != null: bow.reload_remaining = value

func _init() -> void:
	super._init()
	member_id = "cutter"

func setup(hero: Player) -> void:
	player = hero
	global_position = hero.global_position + Vector3(1.8, 0, 1.6)

func _physics_process(delta: float) -> void:
	if testing_disabled and not is_controlled(): return
	super._physics_process(delta)

func refresh_level() -> void:
	stats.refresh()

func arrow_damage_range() -> Vector2:
	return stats.ranged_range()

func arrow_damage() -> float:
	var damage := arrow_damage_range()
	return randf_range(damage.x, damage.y)

static func take_aim_mult() -> float:
	return PowerDb.hero_value("take_aim", "damage_pct", "cutter") / 100.0

func set_manual_target(enemy: Enemy) -> void:
	attack_target = enemy
	manual_target = enemy

func arm_take_aim() -> void:
	if bow != null: bow.arm()

func activate_take_aim_now() -> void:
	arm_take_aim()

func gain_take_aim_charge(damage: float) -> void:
	if bow != null: bow.reload_remaining = maxf(bow.reload_remaining - maxf(damage, 0), 0)

func spend_take_aim() -> void:
	if bow == null: return
	bow.armed = false
	bow.reload_required = stats.power_recharge_damage(TAKE_AIM_COMBAT_SECONDS, "ranged")
	bow.reload_remaining = bow.reload_required

func _clear_take_aim_visual() -> void:
	if bow != null and is_instance_valid(bow.aura): bow.aura.queue_free()
