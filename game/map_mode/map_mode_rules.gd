class_name MapModeRules
extends RefCounted
## Map-mode-only rules for champions' shields, in one place. Nothing here runs unless `MapMode.active`; Champion calls these hooks behind that
## test, so the normal game is untouched.
##
## Owner decision (2026-10-19): champions must make the player act. Auto-attacks alone do not beat a champion's shield (it regenerates); a power
## hit pauses that regeneration for a few seconds so powers break through; and a fight that passes FIGHT_SAFETY_LIMIT seconds stops all
## regeneration so no fight can stall for ever.
##
## NOTE: the champion code had NO shield regeneration when this was written (the shield only ever shrinks), so SHIELD_REGEN_FRACTION is 0.0 and
## this is dormant until the owner confirms regeneration should exist in map mode (see the report). Set it to turn the rule on.

## Seconds a power hit pauses a shield's regeneration.
const SHIELD_REGEN_PAUSE_ON_POWER_HIT := 4.0
## Past this many seconds of one fight, regeneration stops entirely.
const FIGHT_SAFETY_LIMIT := 40.0
## Shield regenerated per second, as a fraction of its maximum (0 = no regeneration; see the note above). Tests change it.
static var SHIELD_REGEN_FRACTION: float = 0.0

static var _fight_start: float = -1.0

## MapMode calls these at the start of a fight (after the dash) and when it ends.
static func note_fight_start(now: float) -> void:
	_fight_start = now

static func note_fight_end() -> void:
	_fight_start = -1.0

## Seconds the current fight has lasted (0 when none is running).
static func fight_time(now: float) -> float:
	return maxf(now - _fight_start, 0.0) if _fight_start >= 0.0 else 0.0

## True for a hit from a power or skill (anything but the plain basic blow). Damage-over-time ticks (`quiet`) do not count.
static func is_power_hit(result: Dictionary) -> bool:
	if result.get("quiet", false) or float(result.get("damage", 0.0)) <= 0.0:
		return false
	return not String(result.get("skill_id", "")) in ["", "basic"]

## Whether `champion`'s shield may regenerate at time `now`.
static func shield_regen_allowed(champion: Champion, now: float) -> bool:
	if SHIELD_REGEN_FRACTION <= 0.0 or champion == null or champion.shield_max <= 0.0 or champion.shield <= 0.0:
		return false
	if fight_time(now) > FIGHT_SAFETY_LIMIT:
		return false
	return now - champion.last_power_hit >= SHIELD_REGEN_PAUSE_ON_POWER_HIT

## Regenerates the shield by `delta` seconds' worth when allowed. Returns the amount restored.
static func regen_step(champion: Champion, delta: float, now: float) -> float:
	if not shield_regen_allowed(champion, now):
		return 0.0
	var before: float = champion.shield
	champion.shield = minf(champion.shield_max, champion.shield + champion.shield_max * SHIELD_REGEN_FRACTION * delta)
	champion._update_bubble()
	return champion.shield - before
