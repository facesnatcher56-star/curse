class_name XpShare
extends RefCounted
## Dungeon Siege II's experience, hit by hit (rules.skrit CalculateExperience / AwardExperience): a monster has a finite pool of XP, each
## hit pays `pool x damage / max life` (the damage clipped to the life it had left, at least 1 XP) and drains the pool. The party shares
## every hit: the group bonus for its leveling members, split evenly; each member's share is then cut or raised by the level gap to the
## monster. The member who struck gets the class skill of the blow; the others get the class of the weapon they have equipped.
## Fractions are kept (pending) and paid as whole points, as DS2's float XP would add up.

## member id -> class id -> XP not yet paid out as whole points.
static var pending: Dictionary = {}

## True when XP is being paid in this world (the connected world or an authored location, never the wave arena).
static func paying() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return false
	for node in tree.get_nodes_in_group("director"):
		var director := node as RunDirector
		if director != null and not director.is_queued_for_deletion() and director.connected():
			return true
	return false

static func pay_hit(enemy: Enemy, member_id: String, class_id: String, dealt: float) -> void:
	if enemy.def == null or not enemy.xp_eligible or dealt <= 0.0 or not paying():
		return
	if enemy.xp_left < 0.0:
		enemy.xp_left = HeroProgression.monster_xp_value(enemy.level, enemy.def.tier)
	var value: float = HeroProgression.monster_xp_value(enemy.level, enemy.def.tier)
	var earned: float = value * dealt / maxf(enemy.max_health, 1.0)
	earned = minf(earned, enemy.xp_left)
	enemy.xp_left -= earned
	if earned > 0.0 and earned < 1.0:
		earned = 1.0
	if earned <= 0.0:
		return
	var party := PartyManager.current()
	var members := party.living()
	if members.is_empty():
		return
	var each: float = earned * float(HeroProgression.PARTY_BONUS[clampi(members.size(), 1, HeroProgression.PARTY_BONUS.size() - 1)]) / float(members.size())
	for body in members:
		var gap := HeroProgression.level_gap_mult(body.character.level, enemy.level)
		var skill: String = class_id if body.member_id == member_id else weapon_class(body)
		add_pending(body.member_id, skill, each * gap)

## The class skill of the weapon a member has equipped (a bow is Ranged, anything else Melee).
static func weapon_class(body: Player) -> String:
	return "ranged" if body.stats.is_ranged() else "melee"

static func add_pending(member_id: String, class_id: String, amount: float) -> void:
	if not pending.has(member_id): pending[member_id] = {}
	pending[member_id][class_id] = float(pending[member_id].get(class_id, 0.0)) + amount

## Pays out every whole point that has built up. Called each frame by the director.
static func flush() -> void:
	for member_id in pending.keys():
		var by_class: Dictionary = pending[member_id]
		var total: float = 0.0
		for id in by_class:
			total += float(by_class[id])
		var whole: int = int(floor(total))
		if whole < 1:
			continue
		TownState.add_member_xp(String(member_id), whole, false, by_class.duplicate())
		var keep: float = (total - float(whole)) / total
		for id in by_class:
			by_class[id] = float(by_class[id]) * keep
