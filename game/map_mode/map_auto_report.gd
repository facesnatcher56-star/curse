class_name MapAutoReport
extends RefCounted
## Dev autoplay (`--mapmode-auto`): per-room data of the run and the SYNERGY REPORT written at its end (printed, and saved as
## `<dir>/synergy_report.md`). Reads the counters of MapAutoTally and the equip records of MapAutoGear. A test and balance tool: it never acts on the game.

## synergy -> {name, needs: gear tokens (an item trait id or legendary id, all worn in the same fight), fires: MapAutoTally keys (any), powers: power ids that should be used}
const SYNERGIES: Array[Dictionary] = [
	{"name": "Short Bow mark + warrior damage", "needs": ["bow_mark"], "fires": ["bow_mark_bonus"], "powers": []},
	{"name": "Longsword charge + Brutal Attack", "needs": ["longsword_charge"], "fires": ["longsword_charge"], "powers": ["brutal_attack"]},
	{"name": "Signet + the other member's powers", "needs": ["signet_share"], "fires": ["signet_share"], "powers": []},
	{"name": "Hero's Amulet + both members' powers", "needs": ["heros_amulet"], "fires": ["heros_amulet_share"], "powers": []},
	{"name": "Opening chance (Club / Studded Gloves) + Iron Gauntlets executions", "needs": ["gauntlets_execute", "club_opening"], "fires": ["gauntlets_execution"], "powers": []},
	{"name": "Dagger crit on an open Opening + an Opening source", "needs": ["dagger_swift", "club_opening"], "fires": ["dagger_open_crit"], "powers": []},
	{"name": "Executioner's Sight + Take Aim on an Opening", "needs": ["executioners_sight"], "fires": ["executioners_sight"], "powers": ["take_aim"]},
	{"name": "Splitbow + Thunderous Shot", "needs": ["splitbow"], "fires": ["splitbow_volley"], "powers": ["thunderous_shot"]},
	{"name": "Headsman's Due + Brutal Attack", "needs": ["headsmans_due"], "fires": ["headsman_jump"], "powers": ["brutal_attack"]},
	{"name": "Gravecaller Maul + Whirling Strike", "needs": ["gravecaller_maul"], "fires": ["gravecaller_pull"], "powers": ["whirling_strike"]},
	{"name": "Woven Hood + Leather Boots after a dash", "needs": ["hood_power", "boots_burst"], "fires": ["hood_power_query", "hood_window"], "powers": []},
	{"name": "Iron Greaves knock-back + a melee frontline", "needs": ["greaves_knock"], "fires": ["greaves_knock"], "powers": []},
	{"name": "Mail Hauberk + damage taken (charge)", "needs": ["hauberk_taken"], "fires": ["hauberk_charge"], "powers": []},
	{"name": "Charm / charge-on-kill + kills", "needs": ["charm_kills"], "fires": ["charm_or_kill_charge"], "powers": []},
	{"name": "War Axe bleed + Mace shred", "needs": ["axe_bleed", "mace_shred"], "fires": ["axe_bleed_applied", "mace_shred_applied"], "powers": []},
	{"name": "Falchion cleave", "needs": ["falchion_cleave"], "fires": ["falchion_cleave"], "powers": []},
]

static var rooms: Array[Dictionary] = []
static var _cur: Dictionary = {}
static var _last_hp: float = -1.0
static var _pos: Dictionary = {}   # enemy instance id -> position at the last sample (to tell a stuck one)
static var _written: bool = false

static func reset() -> void:
	rooms.clear()
	_cur = {}
	_written = false
	MapAutoTally.reset()
	MapAutoGear.reset()

## The tokens an item stands for in the synergy table: its trait id, its legendary id.
static func tokens_of(item: Variant) -> Array[String]:
	var out: Array[String] = []
	if item is Dictionary:
		var t: String = String(MapModeTraits.trait_of(item).get("id", ""))
		if t != "":
			out.append(t)
		var l: String = MapModeLegendaries.id_of(item)
		if l != "":
			out.append(l)
	return out

## The gear in force: member id -> {"items": [name (def)], "tokens": [..], "armor": n, "dps_weapon": avg weapon damage}.
static func gear_of(m: MapMode) -> Dictionary:
	var out: Dictionary = {}
	for body in [m.hero, m.companion]:
		var b := body as Player
		if b == null or not is_instance_valid(b):
			continue
		var items: Array[String] = []
		var toks: Array[String] = []
		for place in b.stats.equipment:
			var it: Dictionary = b.stats.equipment[place]
			items.append("%s [%s]" % [it.get("name", "?"), MapAutoGear.rarity_name(it)])
			toks.append_array(tokens_of(it))
		out[b.member_id] = {"items": items, "tokens": toks, "armor": int(b.stats.armor) if "armor" in b.stats else 0, "max_health": int(b.max_health)}
	return out

static func _hp(b: Player) -> float:
	return b.health / maxf(b.max_health, 1.0) if b != null and is_instance_valid(b) else 0.0

## A fight starts (autoplay, state FIGHT): who is in it and the party's state.
static func room_begin(m: MapMode) -> void:
	var kinds: Dictionary = {}
	var champs: int = 0
	var enemies: Array[Enemy] = m.fight_enemies()
	for e in enemies:
		kinds[e.variant] = int(kinds.get(e.variant, 0)) + 1
		if e.champion != null:
			champs += 1
	_cur = {"kinds": kinds, "enemies": enemies.size(), "champions": champs, "hero_hp_begin": _hp(m.hero), "cutter_hp_begin": _hp(m.companion),
		"hero_hp_min": _hp(m.hero), "cutter_hp_min": _hp(m.companion), "potions_begin": m.hero.stats.potions, "potions_min": m.hero.stats.potions,
		"gear": gear_of(m), "t0": m.now(), "timeline": [], "dealt_begin": MapAutoTally.dealt_by.duplicate(), "node_kind": m.graph.kind_of(m._visit_node) if m.graph != null and m._visit_node >= 0 else "?"}
	MapAutoTally.take_hurt()

## About once a second during a fight.
## Returns true when the fight is hung (no enemy has died for HANG_SECONDS): the report is written and the caller quits, so no window is left hanging.
static func sample(m: MapMode) -> bool:
	if _cur.is_empty():
		return false
	var t: float = m.now() - float(_cur.get("t0", m.now()))
	if not _cur.has("cutter_dead_t") and is_instance_valid(m.companion) and m.companion.dead:
		_cur["cutter_dead_t"] = t
	var alive: Array[Enemy] = m.fight_enemies()
	var seen_now: Dictionary = {}
	var who: PackedStringArray = []
	for e in alive:
		var moved: float = e.global_position.distance_to(_pos.get(e.get_instance_id(), e.global_position))
		seen_now[e.get_instance_id()] = e.global_position
		who.append("%s d=%.1f mv=%.1f hp=%.0f" % [e.variant, e.flat_distance_to(m.hero), moved, e.health])
	_pos = seen_now
	_cur["last"] = "hero %.0f%%, Cutter %.0f%%, alive: %s" % [_hp(m.hero) * 100.0, _hp(m.companion) * 100.0, "; ".join(who)]
	if int(t / 10.0) >= (_cur["timeline"] as Array).size():
		(_cur["timeline"] as Array).append("%ds: %d alive, hero %.0f%%, Cutter %.0f%%, hero target %s, hero busy %s; %s" % [int(t), alive.size(), _hp(m.hero) * 100.0, _hp(m.companion) * 100.0,
			(m.hero.attack_target.variant if m.hero.attack_target is Enemy else "none"), m.hero.skills.busy, "; ".join(who)])
	_cur["hero_hp_min"] = minf(float(_cur["hero_hp_min"]), _hp(m.hero))
	_cur["cutter_hp_min"] = minf(float(_cur["cutter_hp_min"]), _hp(m.companion))
	_cur["potions_min"] = mini(int(_cur["potions_min"]), m.hero.stats.potions)
	if alive.size() < int(_cur.get("alive_min", 999)):
		_cur["alive_min"] = alive.size()
		_cur["alive_min_t"] = t
	var stuck_for: float = t - float(_cur.get("alive_min_t", 0.0))
	if stuck_for > 60.0 and t - float(_cur.get("dump_t", -99.0)) > 60.0:
		_cur["dump_t"] = t
		dump_frozen(m)
	if stuck_for > HANG_SECONDS:
		print("[mapmode] HUNG: no enemy died for %d s; aborting the run" % int(stuck_for))
		room_died(m)
		finish(m._auto_dir, "HUNG fight (no kill for %d s) - stopped by the watchdog" % int(stuck_for), m)
		return true
	return false

## Everything that tells why an enemy does not act: processing flags, velocity, target, behaviour state. Printed and kept in the room record.
static func dump_frozen(m: MapMode) -> void:
	var lines: PackedStringArray = []
	for e in m.fight_enemies():
		var beh: Variant = e.behavior
		lines.append("%s#%d phys=%s proc=%s mode=%d in_tree=%s vel=%s target=%s tdist=%.1f aggro=%s dormant=%s stun=%.1f attacking=%s beh=%s state=%s active=%s alert=%.1f layer=%d mask=%d hp=%.0f pos=%s" % [
			e.variant, e.get_instance_id() % 10000, e.is_physics_processing(), e.is_processing(), e.process_mode, e.is_inside_tree(), e.velocity,
			(e.target.name if e.target != null else "none"), e.flat_distance_to(e.target) if e.target != null else -1.0, e.is_aggro(), e.dormant, e.stun_time, e._attacking,
			beh.get_class() if beh != null else "null", beh.get("_state") if beh != null else "-", beh.get("_active") if beh != null else "-", e.alert_delay,
			e.collision_layer, e.collision_mask, e.health, e.global_position])
	for b in [m.hero, m.companion]:
		if is_instance_valid(b):
			lines.append("%s phys=%s dead=%s busy=%s vel=%s target=%s goal=%s pos=%s hp=%.0f" % [b.member_id, b.is_physics_processing(), b.dead, b.skills.busy, b.velocity,
				(b.attack_target.variant if b.attack_target is Enemy else "none"), b.movement.has_goal, b.global_position, b.health])
	for b in [m.hero, m.companion]:
		if is_instance_valid(b) and b.attack_target is Actor:
			var t: Actor = b.attack_target
			var map: RID = Nav.map_of(b)
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, b.global_position, t.global_position, true)
			lines.append("%s -> %s: goal=%s dist=%.1f nav_path_points=%d path_end_gap=%.1f line_clear=%s target_off_navmesh=%.1f self_off_navmesh=%.1f nav_ready=%s" % [b.member_id, t.name,
				b.movement.goal, b.flat_distance_to(t), path.size(), (path[-1].distance_to(t.global_position) if path.size() > 0 else -1.0), Nav.line_clear(b, t.global_position),
				NavigationServer3D.map_get_closest_point(map, t.global_position).distance_to(t.global_position), NavigationServer3D.map_get_closest_point(map, b.global_position).distance_to(b.global_position), Nav.ready(b)])
	for b in [m.hero, m.companion]:
		if is_instance_valid(b):
			var st: Dictionary = b.movement._nav_state
			var path: PackedVector3Array = st.get("path", PackedVector3Array())
			var idx: int = mini(int(st.get("index", 0)), maxi(path.size() - 1, 0))
			var route: Dictionary = Nav.route(b, b.movement.goal, st.duplicate(true), 0.0)
			lines.append("%s nav_state: route_status=%d (0 following? see Nav.Status) path=%d index=%d next=%s clearance_to_next=%s failed_time=%.1f failed_replans=%s blocked=%s queries=%s pending=%d" % [b.member_id,
				int(route["status"]), path.size(), idx, str(path[idx]) if path.size() > 0 else "-", Nav.clearance(b, b.global_position, path[idx]) if path.size() > 0 else "-",
				float(st.get("failed_time", 0.0)), st.get("failed_replans", 0), st.get("blocked", false), st.get("queries", 0), Nav._pending.size()])
	for l in lines:
		print("[mapmode] FROZEN-DUMP " + l)
	(_cur["timeline"] as Array).append("DUMP: " + " || ".join(lines))

const HANG_SECONDS := 150.0

## Any visit ends (MapMode._begin_collect). `row` is the fight-log row ({} for a chest or shrine without a fight).
static func room_end(m: MapMode, row: Dictionary) -> void:
	var rec: Dictionary = _cur.duplicate(true)
	_cur = {}
	var dealt: Dictionary = {}
	for k in MapAutoTally.dealt_by:
		var d: float = float(MapAutoTally.dealt_by[k]) - float((rec.get("dealt_begin", {}) as Dictionary).get(k, 0.0))
		if d > 0.0:
			dealt[k] = d
	rec.erase("dealt_begin")
	rec["visit"] = m._visit_kind
	rec["group"] = String(row.get("group", m.graph.row(m._visit_node).get("name", "?") if m.graph != null and m._visit_node >= 0 else "?"))
	rec["fought"] = not row.is_empty() and rec.has("enemies")
	rec["length_s"] = float(row.get("length_s", 0.0))
	rec["damage_taken"] = float(row.get("damage_taken", 0.0))
	rec["damage_by_member"] = row.get("damage_by_member", {})
	rec["powers"] = (row.get("powers", []) as Array).duplicate()
	rec["hurt_by"] = MapAutoTally.take_hurt()
	rec["dealt"] = dealt
	rec["hero_level"] = m.hero.character.level
	rec["cutter_level"] = m.companion.character.level
	rec["hero_hp_end"] = _hp(m.hero)
	rec["cutter_hp_end"] = _hp(m.companion)
	rec["potions_end"] = m.hero.stats.potions
	rec["cutter_dead"] = m.companion.dead
	if not rec.has("gear"):
		rec["gear"] = gear_of(m)
		rec["hero_hp_begin"] = _last_hp if _last_hp >= 0.0 else rec["hero_hp_end"]
		rec["cutter_hp_begin"] = rec["cutter_hp_end"]
	rec["hero_hp_at_arrival"] = _last_hp
	_last_hp = rec["hero_hp_end"]
	rooms.append(rec)
	print("[mapmode] ROOM %d %s (%s): hero L%d cutter L%d, hp %.0f%%->min %.0f%%->end %.0f%% (cutter min %.0f%%), potions %s->%s, hurt by %s" % [rooms.size(),
		rec["group"], rec.get("kinds", {}), int(rec["hero_level"]), int(rec["cutter_level"]), float(rec.get("hero_hp_begin", 0.0)) * 100.0, float(rec.get("hero_hp_min", 0.0)) * 100.0,
		float(rec["hero_hp_end"]) * 100.0, float(rec.get("cutter_hp_min", 0.0)) * 100.0, rec.get("potions_begin", "-"), rec["potions_end"], rec["hurt_by"]])

## The party fell mid-fight: the unfinished room is recorded as it stood.
static func room_died(m: MapMode) -> void:
	if _cur.is_empty():
		return
	var rec: Dictionary = _cur.duplicate(true)
	_cur = {}
	rec.erase("dealt_begin")
	rec["visit"] = "group"
	rec["group"] = "%s (PARTY DIED HERE)" % m.log._group
	rec["fought"] = true
	rec["length_s"] = maxf(m.now() - m.log._click_t, 0.0)
	rec["damage_taken"] = m.log._damage
	rec["damage_by_member"] = m.log._by_member
	rec["powers"] = m.log._powers.duplicate()
	rec["hurt_by"] = MapAutoTally.take_hurt()
	rec["dealt"] = {}
	rec["hero_level"] = m.hero.character.level if is_instance_valid(m.hero) else 0
	rec["cutter_level"] = m.companion.character.level if is_instance_valid(m.companion) else 0
	rec["hero_hp_end"] = 0.0
	rec["cutter_hp_end"] = 0.0
	rec["potions_end"] = m.hero.stats.potions if is_instance_valid(m.hero) else 0
	rec["cutter_dead"] = true
	rec["hero_hp_end"] = 0.0
	(rec["timeline"] as Array).append("last sample: " + String(rec.get("last", "?")))
	rooms.append(rec)
	print("[mapmode] ROOM %d %s: hurt by %s, hero min hp %.0f%%, cutter min hp %.0f%%" % [rooms.size(), rec["group"], rec["hurt_by"], float(rec.get("hero_hp_min", 0.0)) * 100.0, float(rec.get("cutter_hp_min", 0.0)) * 100.0])

# --- The report ---------------------------------------------------------------------------------------------------------------------------

static func _fmt_map(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	var keys: Array = d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return float(d[a]) > float(d[b]))
	for k in keys:
		parts.append("%s %s" % [k, ("%.0f" % float(d[k])) if d[k] is float else str(d[k])])
	return ", ".join(parts) if not parts.is_empty() else "none"

static func _worn_together(tokens: Array) -> Array[int]:
	var out: Array[int] = []
	for i in rooms.size():
		var have: Array[String] = []
		for id in (rooms[i].get("gear", {}) as Dictionary):
			have.append_array(rooms[i]["gear"][id]["tokens"])
		var ok: bool = true
		for t in tokens:
			ok = ok and have.has(t)
		if ok:
			out.append(i)
	return out

static func _dropped_tokens() -> Dictionary:
	var out: Dictionary = {}
	for k in MapAutoGear.seen:
		var e: Dictionary = MapAutoGear.seen[k]
		for t in [String(e.get("trait", "")), String(e.get("legendary", ""))]:
			if t != "":
				out[t] = out.get(t, []) + [e]
	return out

static func _stats(vals: Array) -> String:
	if vals.is_empty():
		return "n/a"
	var sum: float = 0.0
	for v in vals:
		sum += float(v)
	var sorted: Array = vals.duplicate()
	sorted.sort()
	return "n=%d mean %.1fs median %.1fs max %.1fs" % [vals.size(), sum / vals.size(), float(sorted[sorted.size() / 2]), float(sorted[-1])]

## The report text. `outcome`: "Run complete", "RUN ENDED EARLY (party dead)", "time cap".
static func build(outcome: String, m: Variant = null) -> String:
	var L: PackedStringArray = []
	L.append("# SYNERGY REPORT (map-mode autoplay)")
	L.append("")
	L.append("Outcome: **%s** after %d rooms (%d fights)." % [outcome, rooms.size(), rooms.filter(func(r: Dictionary) -> bool: return bool(r.get("fought", false))).size()])
	L.append("")
	# Equips
	L.append("## Equip log (%d equips)" % MapAutoGear.equips.size())
	for rec in MapAutoGear.equips:
		L.append("- " + MapAutoGear.line_of(rec).trim_prefix("[mapmode] "))
	L.append("")
	# Synergies
	L.append("## Synergies")
	var dropped: Dictionary = _dropped_tokens()
	var found: PackedStringArray = []
	var silent: PackedStringArray = []
	var missed: PackedStringArray = []
	for s in SYNERGIES:
		var needs: Array = s["needs"]
		var primary: Array = [needs[0]]
		var together: Array[int] = _worn_together(needs)
		var primary_rooms: Array[int] = _worn_together(primary)
		var fires: float = 0.0
		var amount: float = 0.0
		for key in s["fires"]:
			fires += MapAutoTally.n(key)
			amount += MapAutoTally.amount(key)
		var used: PackedStringArray = []
		for pid in s["powers"]:
			var n: int = 0
			for r in rooms:
				n += (r.get("powers", []) as Array).count(pid)
			used.append("%s x%d" % [pid, n])
		var detail: String = "worn together in %d/%d rooms; effect fired %d times (amount %.0f)%s" % [together.size(), rooms.size(), int(fires), amount,
			("; powers: " + ", ".join(used)) if not used.is_empty() else ""]
		if not together.is_empty() and fires > 0:
			found.append("- **%s** - %s" % [s["name"], detail])
		elif not together.is_empty():
			silent.append("- **%s** - worn together but NEVER fired: %s" % [s["name"], detail])
		else:
			var why: PackedStringArray = []
			for t in needs:
				if _worn_together([t]).is_empty():
					if dropped.has(t):
						var e: Dictionary = (dropped[t] as Array)[0]
						why.append("%s dropped (%s) but %s" % [t, e["name"], ("worn only outside a fight (after the last clear)" if String(e["who"]) != "" else "never worn: " + String(e["reason"]))])
					else:
						why.append("%s never dropped" % t)
			if primary_rooms.is_empty() == false and why.is_empty():
				why.append("pieces were worn in different fights")
			missed.append("- **%s** - %s. %s" % [s["name"], ", ".join(why), detail])
	L.append("### FOUND (worn together and fired)")
	L.append_array(found if not found.is_empty() else PackedStringArray(["- none"]))
	L.append("### Worn together but SILENT (too weak or not triggered)")
	L.append_array(silent if not silent.is_empty() else PackedStringArray(["- none"]))
	L.append("### MISSED (a piece never came together)")
	L.append_array(missed if not missed.is_empty() else PackedStringArray(["- none"]))
	L.append("")
	# Counters
	L.append("## Effect counters (fires / amount of damage or charge)")
	var keys: Array = MapAutoTally.counts.keys()
	keys.sort()
	for k in keys:
		L.append("- %s: %d fires, amount %.0f" % [k, MapAutoTally.n(k), MapAutoTally.amount(k)])
	if keys.is_empty():
		L.append("- no trait or legendary effect fired")
	L.append("")
	# Damage
	var total: float = 0.0
	for k in MapAutoTally.dealt_by:
		total += float(MapAutoTally.dealt_by[k])
	L.append("## Damage dealt (%.0f total, by member/skill)" % total)
	var dk: Array = MapAutoTally.dealt_by.keys()
	dk.sort_custom(func(a: Variant, b: Variant) -> bool: return float(MapAutoTally.dealt_by[a]) > float(MapAutoTally.dealt_by[b]))
	for k in dk:
		L.append("- %s: %.0f (%.0f%%)" % [k, float(MapAutoTally.dealt_by[k]), 100.0 * float(MapAutoTally.dealt_by[k]) / maxf(total, 1.0)])
	var mark_share: float = MapAutoTally.amount("bow_mark_bonus") / maxf(total, 1.0)
	L.append("")
	L.append("## Looks too weak / too strong")
	var flags: PackedStringArray = []
	for k in dk:
		if float(MapAutoTally.dealt_by[k]) / maxf(total, 1.0) > 0.6:
			flags.append("- STRONG: %s accounts for %.0f%% of all damage dealt" % [k, 100.0 * float(MapAutoTally.dealt_by[k]) / maxf(total, 1.0)])
	if mark_share > 0.0:
		flags.append("- Short Bow mark added %.0f damage = %.1f%% of all damage" % [MapAutoTally.amount("bow_mark_bonus"), mark_share * 100.0])
	for s in silent:
		flags.append("- WEAK: " + s.trim_prefix("- "))
	if MapAutoTally.n("bow_mark_denied_to_cutter") > 0:
		flags.append("- Cutter hit %d marked targets the hero had marked: no bonus by design (warrior only)" % MapAutoTally.n("bow_mark_denied_to_cutter"))
	L.append_array(flags if not flags.is_empty() else PackedStringArray(["- nothing stands out"]))
	L.append("")
	# Items never equipped
	L.append("## Dropped items never equipped")
	var never: int = 0
	for k in MapAutoGear.seen:
		var e: Dictionary = MapAutoGear.seen[k]
		if String(e["who"]) == "":
			never += 1
			L.append("- %s (%s, %s%s): %s" % [e["name"], e["rarity"], e["slot"], (", trait " + String(e["trait"])) if String(e["trait"]) != "" else "", e["reason"]])
	if never == 0:
		L.append("- none")
	L.append("")
	# Rooms
	L.append("## Rooms")
	L.append("| # | room | enemies | hero/cutter lvl | hero hp begin/min/end | cutter hp begin/min/end | potions | length | damage taken | hurt by |")
	L.append("|---|---|---|---|---|---|---|---|---|---|")
	var i: int = 0
	for r in rooms:
		i += 1
		L.append("| %d | %s (%s) | %s | %d/%d | %.0f%%/%.0f%%/%.0f%% | %.0f%%/%.0f%%/%.0f%% | %s->%s | %.1fs | %.0f | %s |" % [i, r["group"], r["visit"], _fmt_map(r.get("kinds", {})) + (" +%d champion" % int(r.get("champions", 0)) if int(r.get("champions", 0)) > 0 else ""),
			int(r["hero_level"]), int(r["cutter_level"]), float(r.get("hero_hp_begin", r["hero_hp_end"])) * 100.0, float(r.get("hero_hp_min", r["hero_hp_end"])) * 100.0, float(r["hero_hp_end"]) * 100.0,
			float(r.get("cutter_hp_begin", r["cutter_hp_end"])) * 100.0, float(r.get("cutter_hp_min", r["cutter_hp_end"])) * 100.0, float(r["cutter_hp_end"]) * 100.0, r.get("potions_begin", "-"), r["potions_end"], float(r["length_s"]), float(r["damage_taken"]), _fmt_map(r["hurt_by"])])
	L.append("")
	var normal: Array = []
	var champ: Array = []
	for r in rooms:
		if bool(r.get("fought", false)):
			(champ if int(r.get("champions", 0)) > 0 else normal).append(float(r["length_s"]))
	L.append("## Fight length")
	L.append("- normal packs: " + _stats(normal))
	L.append("- champion packs: " + _stats(champ))
	L.append("")
	L.append("## Gear by room (hero | cutter)")
	i = 0
	for r in rooms:
		i += 1
		var g: Dictionary = r.get("gear", {})
		L.append("- %d %s: hero %s | cutter %s" % [i, r["group"], ", ".join(g.get("hero", {}).get("items", [])), ", ".join(g.get("cutter", {}).get("items", []))])
		if r.has("cutter_dead_t"):
			L.append("  - the Cutter died %ds into this fight" % int(r["cutter_dead_t"]))
		if float(r.get("length_s", 0.0)) > 30.0:
			var tls: Array = r.get("timeline", [])
			for k in tls.size():
				if k % 3 == 0 or k >= tls.size() - 1:
					L.append("  - " + String(tls[k]))
	L.append("")
	L.append("## Hurt by (whole run; * = champion)")
	L.append("- " + _fmt_map(MapAutoTally.hurt_total))
	if m is MapMode and (m as MapMode).graph != null:
		var g: MapGraph = (m as MapMode).graph
		var left: PackedStringArray = []
		for id in g.ids():
			if not g.cleared.has(int(id)):
				left.append("%s(%s)" % [g.row(int(id)).get("name", id), g.kind_of(int(id))])
		L.append("")
		L.append("## Nodes never cleared: " + (", ".join(left) if not left.is_empty() else "none"))
	return "\n".join(L)

## Prints the report and writes `<dir>/synergy_report.md` (once per run).
static func finish(dir: String, outcome: String, m: Variant = null) -> void:
	if _written:
		return
	_written = true
	var text: String = build(outcome, m)
	print(text)
	var f := FileAccess.open("%s/synergy_report.md" % dir, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
