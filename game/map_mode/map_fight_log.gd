class_name MapFightLog
extends RefCounted
## Per-fight log for map mode: one row per cleared group (click-to-first-hit, dash and fight length, inputs, powers, damage taken).
## Pure data: the caller supplies `now` (seconds, monotonic clock). Calls made while no fight is active are ignored.

## Completed rows, in order.
var fights: Array[Dictionary] = []

var _active: bool = false
var _group: String = ""
var _click_t: float = 0.0
var _dash_end_t: float = -1.0
var _first_hit_t: float = -1.0
var _inputs: int = 0
var _tally: Dictionary = {}
var _powers: Array[String] = []
var _damage: float = 0.0
var _by_member: Dictionary = {}

## The player clicked the group on the map. Resets the per-fight counters.
func begin_fight(group_label: String, now: float) -> void:
	_active = true
	_group = group_label
	_click_t = now
	_dash_end_t = -1.0
	_first_hit_t = -1.0
	_inputs = 0
	_tally = {}
	_powers = []
	_damage = 0.0
	_by_member = {}

func note_dash_end(now: float) -> void:
	if _active and _dash_end_t < 0.0:
		_dash_end_t = now

## Only the first call after begin_fight counts.
func note_first_hit(now: float) -> void:
	if _active and _first_hit_t < 0.0:
		_first_hit_t = now

## A player click or key/button press during the fight; `what` is the tally key ("click", "focus", "power_1", ...).
func note_input(_now: float, what: String) -> void:
	if not _active:
		return
	_inputs += 1
	_tally[what] = int(_tally.get(what, 0)) + 1

func note_power(power_id: String) -> void:
	if _active:
		_powers.append(power_id)

## `who` is the member id ("hero" or a companion).
func note_damage_taken(amount: float, who: String) -> void:
	if not _active:
		return
	_damage += amount
	_by_member[who] = float(_by_member.get(who, 0.0)) + amount

## The group is cleared. Returns the summary row (also appended to `fights`); an empty Dictionary if no fight was active.
## length_s runs from dash end (or from the click if the dash never ended) to the clear.
func end_fight(now: float) -> Dictionary:
	if not _active:
		return {}
	_active = false
	var dash_end: float = _dash_end_t if _dash_end_t >= 0.0 else _click_t
	var row: Dictionary = {
		"group": _group,
		"length_s": maxf(now - dash_end, 0.0),
		"click_to_first_hit_s": (_first_hit_t - _click_t) if _first_hit_t >= 0.0 else -1.0,
		"dash_s": maxf(dash_end - _click_t, 0.0),
		"inputs": _inputs,
		"input_tally": _tally.duplicate(),
		"powers": _powers.duplicate(),
		"damage_taken": _damage,
		"damage_by_member": _by_member.duplicate(),
	}
	fights.append(row)
	return row

## One human-readable console line for a row.
func row_line(row: Dictionary) -> String:
	var hit: float = float(row.get("click_to_first_hit_s", -1.0))
	var hit_text: String = "never" if hit < 0.0 else "%.2fs" % hit
	return "[mapmode] fight %s: length %.1fs, dash %.1fs, click->first hit %s, inputs %d %s, powers %s, damage taken %.0f %s" % [
		row.get("group", "?"), float(row.get("length_s", 0.0)), float(row.get("dash_s", 0.0)), hit_text, int(row.get("inputs", 0)),
		row.get("input_tally", {}), row.get("powers", []), float(row.get("damage_taken", 0.0)), row.get("damage_by_member", {})]

## Header, one line per fight, and a totals line; suitable for pasting into a PR.
func summary_lines() -> PackedStringArray:
	var lines := PackedStringArray(["[mapmode] fight log (%d fights)" % fights.size()])
	var secs: float = 0.0
	var inputs: int = 0
	var powers: int = 0
	var damage: float = 0.0
	var hit_sum: float = 0.0
	var hit_n: int = 0
	for row: Dictionary in fights:
		lines.append(row_line(row))
		secs += float(row["length_s"])
		inputs += int(row["inputs"])
		powers += (row["powers"] as Array).size()
		damage += float(row["damage_taken"])
		if float(row["click_to_first_hit_s"]) >= 0.0:
			hit_sum += float(row["click_to_first_hit_s"])
			hit_n += 1
	var mean_text: String = "%.2fs" % (hit_sum / hit_n) if hit_n > 0 else "n/a"
	lines.append("[mapmode] totals: %d fights, %.1fs fighting, %d inputs, %d powers used, %.0f damage taken, mean click->first hit %s" % [
		fights.size(), secs, inputs, powers, damage, mean_text])
	return lines

## Prints the row line. (The existing --xplog convention is a plain print() gated by a static flag; there is no shared file writer.)
func emit_line(row: Dictionary) -> void:
	print(row_line(row))
