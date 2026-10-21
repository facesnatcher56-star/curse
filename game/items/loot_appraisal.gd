class_name LootAppraisal
extends RefCounted
## A first look at an item on the ground: can this hero wear it, and would it beat what they wear in that slot? The name plate and the
## item card show the answer, so a screen of drops can be read at a glance. It only reads: the pickup itself is unchanged (an empty slot
## is filled, anything else goes to the bag).

enum Verdict { LOCKED, EVEN, UPGRADE }

const UPGRADE_COLOR := Color(0.5, 0.9, 0.5)
const LOCKED_COLOR := Color(0.9, 0.45, 0.4)

## `LOCKED`: the hero does not meet its requirements yet. `UPGRADE`: wearable and either the slot is empty or the item card's own
## comparison (Items.compare) is better on balance. `EVEN`: wearable, but equal or worse.
static func of(item: Dictionary, stats: PlayerStats) -> int:
	var member_id: String = stats.p.member_id
	if not Items.hero_can_wear(item, member_id):
		return Verdict.LOCKED
	if stats.fits_empty_slot(item):
		return Verdict.UPGRADE   # walking over it wears it (map mode: it goes to the bag and the reward panel offers it)
	var places: Array[int] = Items.places(int(item["slot"]))   # a ring may replace either of its two
	for place in places:
		if not stats.equipment.has(place):
			return Verdict.EVEN   # free, but a two-handed weapon and a shield are fighting over the hand
	for place in places:
		var balance: int = 0
		for line in Items.compare(item, stats.equipment[place], member_id):
			balance += int(line["sign"])
		if balance > 0:
			return Verdict.UPGRADE
	return Verdict.EVEN

## How the item compares with what is worn in its place, by the item card's own comparison (Items.compare, the wear warning left out):
## +1 better (or the place is free), -1 worse, 0 the same. A ring takes the better of its two places. The loot summary's green and red arrows.
static func trend(item: Dictionary, stats: PlayerStats) -> int:
	var member_id: String = stats.p.member_id
	var best: int = -2
	for place in Items.places(int(item["slot"])):
		if not stats.equipment.has(place):
			return 1
		var balance: int = 0
		for line in Items.compare(item, stats.equipment[place], member_id):
			if String(line.get("key", "")) != Items.WARNING_KEY:
				balance += int(line["sign"])
		best = maxi(best, signi(balance))
	return best

## The words for the item card, or "" when there is nothing to add.
static func note(verdict: int, item: Dictionary, stats: PlayerStats) -> String:
	match verdict:
		Verdict.LOCKED:
			return "You cannot wear it yet"
		Verdict.UPGRADE:
			return "Better than what you wear" if _slot_full(item, stats) else "Nothing worn in this slot"
	return ""

static func _slot_full(item: Dictionary, stats: PlayerStats) -> bool:
	for place in Items.places(int(item["slot"])):
		if not stats.equipment.has(place):
			return false
	return true
