class_name EquipmentRequirement
extends RefCounted
## Parser and evaluator for the requirement syntax preserved by the DS2 equipment catalogue.
## Commas express AND and pipes express OR in this corpus. A string containing both is
## rejected until DS2's mixed-operator precedence can be verified from an authoritative source.

const CLASS_KEYS := {
	"melee": "melee", "ranged": "ranged", "combat magic": "combat", "nature magic": "nature", "uber": "uber",
}
const ATTRIBUTE_KEYS := {"strength": "strength", "dexterity": "dexterity", "intelligence": "intelligence"}
## DS2 source identifiers; `aegis` is DS2's name for Curse's Barricade passive.
const DS2_PASSIVES := ["aegis", "amplified_lightning", "biting_arrow", "dual_wield", "grim_necromancy",
	"overbear", "quick_draw", "searing_flames", "summon_might"]
const PASSIVE_ALIASES := {"aegis": "barricade"}
const PASSIVE_NAMES := {
	"aegis": "Barricade", "amplified_lightning": "Amplified Lightning", "biting_arrow": "Biting Arrow",
	"dual_wield": "Dual Wield", "grim_necromancy": "Grim Necromancy", "overbear": "Overbear",
	"quick_draw": "Quick Draw", "searing_flames": "Searing Flames", "summon_might": "Summon Might",
}

static func parse(source: String) -> Dictionary:
	var expression := source.strip_edges()
	if source.is_empty():
		return {"valid": true, "expression": expression, "operator": "none", "terms": []}
	if expression.is_empty():
		return {"valid": false, "expression": expression, "error": "Whitespace-only requirement is malformed.", "operator": "none", "terms": []}
	if expression.contains(",") and expression.contains("|"):
		return {"valid": false, "expression": expression, "error": "Mixed comma and pipe operators have unresolved DS2 precedence.", "operator": "mixed", "terms": []}
	var operator := "and" if expression.contains(",") else ("or" if expression.contains("|") else "one")
	var separator := "," if operator == "and" else ("|" if operator == "or" else "")
	var pieces: PackedStringArray = expression.split(separator, true) if separator != "" else PackedStringArray([expression])
	var terms: Array[Dictionary] = []
	for piece in pieces:
		var term_result := _parse_term(String(piece).strip_edges())
		if not bool(term_result.get("valid", false)):
			return {"valid": false, "expression": expression, "error": String(term_result.get("error", "Malformed requirement.")), "operator": operator, "terms": []}
		terms.append(term_result["term"])
	return {"valid": true, "expression": expression, "operator": operator, "terms": terms}

static func _parse_term(source: String) -> Dictionary:
	var colon := source.find(":")
	if colon <= 0 or colon == source.length() - 1:
		return {"valid": false, "error": "Expected a requirement key and value in '%s'." % source}
	var key := source.substr(0, colon).strip_edges().to_lower()
	var value_text := source.substr(colon + 1).strip_edges()
	var kind := ""
	var canonical := ""
	if CLASS_KEYS.has(key):
		kind = "class"
		canonical = String(CLASS_KEYS[key])
	elif ATTRIBUTE_KEYS.has(key):
		kind = "attribute"
		canonical = String(ATTRIBUTE_KEYS[key])
	elif DS2_PASSIVES.has(key):
		kind = "passive"
		canonical = String(PASSIVE_ALIASES.get(key, key))
	else:
		return {"valid": false, "error": "Unknown requirement type '%s'." % key}
	var dynamic_pattern := RegEx.new()
	dynamic_pattern.compile("^#item_level(?:\\s*([+-])\\s*(\\d+(?:\\.\\d+)?))?$")
	var dynamic_match := dynamic_pattern.search(value_text)
	var required: float
	var dynamic := dynamic_match != null
	if dynamic:
		var offset_text := String(dynamic_match.get_string(2))
		required = 0.0 if offset_text.is_empty() else float(offset_text) * (-1.0 if dynamic_match.get_string(1) == "-" else 1.0)
	else:
		var number_pattern := RegEx.new()
		number_pattern.compile("^\\d+(?:\\.\\d+)?$")
		if number_pattern.search(value_text) == null:
			return {"valid": false, "error": "Malformed requirement value '%s'." % value_text}
		required = float(value_text)
	if kind == "passive" and not is_equal_approx(required, roundf(required)):
		return {"valid": false, "error": "Passive ranks must be whole numbers in '%s'." % source}
	return {"valid": true, "term": {"key": key, "canonical": canonical, "kind": kind, "required": required, "dynamic": dynamic}}

## `context` carries class levels, attributes and actual learned passive ranks. Missing character values are not fabricated.
static func evaluate(source: String, item_level: float, context: Dictionary) -> Dictionary:
	var parsed := parse(source)
	if not bool(parsed["valid"]):
		return {"valid": false, "satisfied": false, "error": String(parsed["error"]), "operator": String(parsed["operator"]), "missing": []}
	var terms: Array = parsed["terms"]
	if terms.is_empty():
		return {"valid": true, "satisfied": true, "error": "", "operator": "none", "missing": [], "unsupported": []}
	var results: Array[Dictionary] = []
	var ranks: Dictionary = context.get("passive_ranks", {})
	var levels: Dictionary = context.get("levels", {})
	var attributes: Dictionary = context.get("attributes", {})
	for raw_term in terms:
		var term: Dictionary = raw_term
		var required: float = item_level + float(term["required"]) if bool(term["dynamic"]) else float(term["required"])
		var known_value := true
		var actual := 0.0
		var unsupported := ""
		match String(term["kind"]):
			"class":
				var class_key := String(term["canonical"])
				known_value = levels.has(class_key)
				if known_value:
					actual = float(levels[class_key])
			"attribute":
				var attribute_key := String(term["canonical"])
				known_value = attributes.has(attribute_key)
				if known_value:
					actual = float(attributes[attribute_key])
			"passive":
				var passive_id := String(term["canonical"])
				var passive_def: PassiveDef = PassiveDb.get_def(passive_id)
				if passive_def == null:
					known_value = false
					unsupported = String(PASSIVE_NAMES.get(String(term["key"]), String(term["key"])))
				else:
					actual = float(ranks.get(passive_id, 0))
		results.append({"term": term, "required": required, "actual": actual, "known_value": known_value, "unsupported": unsupported,
			"met": known_value and actual >= required})
	var satisfied := false
	if String(parsed["operator"]) == "or":
		for result in results:
			satisfied = satisfied or bool(result["met"])
	else:
		satisfied = true
		for result in results:
			satisfied = satisfied and bool(result["met"])
	var missing: Array[Dictionary] = []
	var unsupported_items: Array[String] = []
	for result in results:
		if not bool(result["met"]):
			missing.append(result)
		if String(result["unsupported"]) != "":
			unsupported_items.append(String(result["unsupported"]))
	return {"valid": true, "satisfied": satisfied, "error": "", "operator": String(parsed["operator"]), "missing": missing,
		"unsupported": unsupported_items, "terms": results}

static func describe(source: String, item_level: float, context: Dictionary) -> String:
	var result := evaluate(source, item_level, context)
	if not bool(result["valid"]):
		return "Requires unsupported condition: %s" % String(result["error"])
	if String(result["operator"]) == "none":
		return ""
	var rendered: PackedStringArray = []
	for detail in result.get("terms", []):
		var term: Dictionary = detail["term"]
		var label := _display_name(String(term["key"]), String(term["kind"]))
		var required: float = float(detail["required"])
		var text := "%s %s" % [label, _format_number(required)]
		if String(detail["unsupported"]) != "":
			text += " (skill unavailable)"
		elif bool(detail["known_value"]):
			text += " (have %s)" % _format_number(float(detail["actual"]))
		else:
			text += " (current value unavailable)"
		rendered.append(text)
	var joiner := " or " if String(result["operator"]) == "or" else " and "
	return "Requires " + joiner.join(rendered)

static func _display_name(key: String, kind: String) -> String:
	if kind == "class":
		match key:
			"melee": return "Melee"
			"ranged": return "Ranged"
			"combat magic": return "Combat Magic"
			"nature magic": return "Nature Magic"
			"uber": return "Character level"
	if kind == "attribute":
		return key.capitalize()
	return String(PASSIVE_NAMES.get(key, key.replace("_", " ").capitalize()))

static func _format_number(value: float) -> String:
	return str(int(roundf(value))) if is_equal_approx(value, roundf(value)) else "%.1f" % value
