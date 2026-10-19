class_name MapAutoPowers
extends RefCounted
## Dev autoplay helper (`--mapmode-auto`): fires every ready power at a target the way a player would, through the hotbar's own input actions
## (`skill_N`, with the cursor on the target), so the real routing in SkillController.handle_hotkeys runs: the right member casts, the gates
## (rank, stance, charge, busy) apply, and the same effects happen. The caller invokes it about once a second during fights.

const HOLD := 0.2          # seconds a key is held; Thunderous Shot's aimed key needs a held press and a release
const RANGE_MELEE := 3.2   # m: Brutal Attack and Whirling Strike hit what is this close
const RANGE_BOW := 15.0    # m: Take Aim and Thunderous Shot
const RANGE_CAST := 12.0   # m: other powers

static var _held: Dictionary = {}   # action -> true while a press is under way (a second call must not stack another)

## Presses the key of every hotbar power that is ready and in reach of `target`. Returns how many were pressed.
static func fire(hero: Player, companion: Player, target: Actor) -> int:
	if not is_instance_valid(hero) or hero.dead or not is_instance_valid(target) or target.dead:
		return 0
	var fired: int = 0
	var pressed: Array[String] = []
	for slot in GameSettings.hotbar_slot_count():
		var id: String = GameSettings.hotbar_slots[slot] if slot < GameSettings.hotbar_slots.size() else ""
		var action: String = "skill_%d" % (slot + 1)
		if id == "" or _held.has(action) or not _wanted(id):
			continue
		var caster: Player = PartyManager.current().bodies.get(GameSettings.hotbar_caster(slot)) as Player
		if caster == null or not is_instance_valid(caster) or caster.dead or caster.skills.busy or caster.stun_time > 0.0:
			continue
		if caster.flat_distance_to(target) - target.body_radius > _reach(id) or not _ready(caster, id):
			continue
		_held[action] = true
		Input.action_press(action)
		pressed.append(action)
		fired += 1
	if fired > 0:
		hero.cursor_override = target.global_position
		var tree: SceneTree = hero.get_tree()
		tree.create_timer(HOLD).timeout.connect(_release.bind(hero, target, pressed))
	return fired

static func _wanted(id: String) -> bool:
	return id == "brutal_attack" or id == "take_aim" or PowerController.LIVE.has(id)

static func _reach(id: String) -> float:
	match id:
		"brutal_attack", "whirling_strike", "staggering_blow":
			return RANGE_MELEE
		"take_aim", "thunderous_shot", "repulse":
			return RANGE_BOW
	return RANGE_CAST

static func _ready(caster: Player, id: String) -> bool:
	if not caster.stats.can_use(id):
		return false
	if id == "brutal_attack" and caster.skills.brutal_armed:
		return false
	if id == "take_aim" and (caster.bow.armed or caster.skills.take_aim_targeting):
		return false
	if id == "staggering_blow" and caster.powers.staggering_armed:
		return false
	return true

static func _release(hero: Player, target: Actor, actions: Array[String]) -> void:
	for action in actions:
		Input.action_release(action)
		_held.erase(action)
	if not is_instance_valid(hero):
		return
	hero.cursor_override = Vector3.INF
	# Take Aim asks for a click on the target to arm the shot; the click is the one step the keys do not cover.
	for body in PartyManager.current().bodies.values():
		var member := body as Player
		if is_instance_valid(member) and member.skills.take_aim_targeting and is_instance_valid(target) and not target.dead:
			member.skills.confirm_take_aim(target as Enemy)
