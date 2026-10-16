class_name HotbarLayout
extends RefCounted
## Which skill sits on which key. There are seven places (the six numbered slots and the right mouse button) and eight skills: pick a skill
## that is already on a key and the two trade places; pick one from the bench and it takes the place, the skill it replaces going to the bench. The dodge is not part of it (it has its own key). The live layout is `GameSettings.hotbar_slots` / `hotbar_alt`, saved with
## the settings; `SkillController.assign_slot` is what the hotbar's click-to-change popup calls.

## What can go on a slot, in the order the picker shows them.
const ASSIGNABLE: Array[String] = ["basic", "brutal_attack", "take_aim", "fireball",
	"whirling_strike", "staggering_blow", "war_cry", "provoke", "repulse", "silence", "flame_nexus", "detonation"]
# Start with the powers equipped on slots 1 and 2. Empty slots remain assignable through the picker.
const DEFAULT_SLOTS: Array[String] = ["brutal_attack", "take_aim", "", "", "", ""]
const DEFAULT_ALT := "basic"
## The slot number of the right mouse button.
const ALT := -1
## Returned by where() for a skill that is on no slot.
const NONE := -99

## Whether `slots` and `alt` together are a layout: the right places filled with known skills, none twice. (There are more skills than places
## now, so some are always on the bench.)
static func is_valid(slots: Array, alt: String) -> bool:
	if slots.size() != DEFAULT_SLOTS.size() or not ASSIGNABLE.has(alt):
		return false
	var seen: Dictionary = {alt: true}
	for id in slots:
		if String(id) == "":
			continue
		if not ASSIGNABLE.has(String(id)) or seen.has(String(id)):
			return false
		seen[String(id)] = true
	return true

## Whether the party can use `id` at all: the basic attack always, a power once any party member has a rank in it.
static func learned(id: String) -> bool:
	if id == "basic":
		return true
	if PowerDb.get_def(id) == null:
		return false
	for member_id in PartyManager.current().members:
		if PowerDb.hero_rank(id, String(member_id)) > 0:
			return true
	return false

## What the picker offers: the assignable skills the party has learned, in the picker's order.
static func learned_ids() -> Array[String]:
	var out: Array[String] = []
	for id in ASSIGNABLE:
		if learned(id):
			out.append(id)
	return out

## Takes anything the party has not learned (any more) off the keys; the right button falls back to the basic attack.
static func drop_unlearned(slots: Array, alt: String) -> String:
	for i in slots.size():
		if String(slots[i]) != "" and not learned(String(slots[i])):
			slots[i] = ""
	return alt if learned(alt) else DEFAULT_ALT

## The slot holding `id` (0.. for the numbered ones, ALT for the mouse button, NONE if none).
static func where(slots: Array, alt: String, id: String) -> int:
	if alt == id:
		return ALT
	var index: int = slots.find(id)
	return index if index >= 0 else NONE

static func skill_at(slots: Array, alt: String, slot: int) -> String:
	return alt if slot == ALT else String(slots[slot])

## Puts `id` on `slot`; whatever was there goes to where `id` came from (or to the bench, if `id` was not on any key). Edits `slots` in place and returns the new right-button skill.
static func assign(slots: Array, alt: String, slot: int, id: String) -> String:
	if not ASSIGNABLE.has(id) or (slot != ALT and (slot < 0 or slot >= slots.size())):
		return alt
	var current: String = skill_at(slots, alt, slot)
	if current == id:
		return alt
	var from: int = where(slots, alt, id)
	var new_alt: String = alt
	if slot == ALT:
		new_alt = id
	else:
		slots[slot] = id
	if from == ALT:
		new_alt = current
	elif from != NONE:
		slots[from] = current
	return new_alt
