#!/usr/bin/env python3
"""Extract the installed DS2 equipment catalogue as reference data, NOT live loot.

Usage: python tools/extract_ds2_catalog.py
Source scripts stay in ignored ds2_source/ds2_catalog_source. No scripts or art
are distributed with the JSON. Expressions are retained as data, never evaluated.
"""
import copy
import hashlib
import json
import re
from pathlib import Path

from ds2_dump import DEFAULT_GAME_RES, extract_targets, list_files

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\[[^\]]*\]|[{};=]|[^\s{}\[\];=]+', re.S)
WEAPONS = {"sword_1h", "sword_2h", "axe_1h", "axe_2h", "hammer_1h", "hammer_2h",
           "mace", "club", "dagger", "staff_fighter", "staff_mage", "cestus", "bow", "crossbow", "thrown"}
OTHER = {"trs_ring.gas", "trs_amulet.gas", "trs_book_spell.gas", "wpn_misc.gas", "sets.gas", "crafted_items.gas"}


def parse(text):
    """Small GAS data reader. Preserve repeated [*] effects and quoted delimiters."""
    tokens = [m[0] for m in TOKEN.finditer(text)
              if not m[0].isspace() and not m[0].startswith(("//", "/*"))]
    pos = 0

    def node():
        nonlocal pos
        result = {"fields": {}, "children": {}}
        while pos < len(tokens) and tokens[pos] != "}":
            key = tokens[pos]
            pos += 1
            if key.startswith("["):
                assert tokens[pos] == "{", tokens[max(0, pos - 15):pos + 12]
                pos += 1
                child = node()
                assert tokens[pos] == "}", key
                pos += 1
                result["children"].setdefault(key[1:-1], []).append(child)
            else:
                # GAS permits typed fields, e.g. `f defense = ...`.
                while tokens[pos] != "=":
                    assert tokens[pos] not in {"{", "}", ";"}, (key, tokens[pos])
                    key = tokens[pos]
                    pos += 1
                assert tokens[pos] == "=", (key, tokens[pos])
                pos += 1
                value = []
                while tokens[pos] != ";":
                    value.append(tokens[pos])
                    pos += 1
                pos += 1
                result["fields"][key] = " ".join(value).strip('"')
        return result

    result = node()
    assert pos == len(tokens), tokens[pos:pos + 10]
    return result


def merge(parent, child):
    out = copy.deepcopy(parent)
    out["fields"].update(child["fields"])
    for key, values in child["children"].items():
        if key != "*" and len(values) == 1 and len(out["children"].get(key, [])) == 1:
            out["children"][key] = [merge(out["children"][key][0], values[0])]
        else:
            out["children"][key] = copy.deepcopy(values)
    return out


def section(node, key):
    return node["children"].get(key, [{"fields": {}, "children": {}}])[0]


def effects(node):
    result = []
    for values in node["children"].values():
        for child in values:
            fields = child["fields"]
            if "alteration" in fields:
                # Explicitly omit executable custom-effect scripts and visual effect names.
                result.append({k: v for k, v in fields.items() if k in {
                    "alteration", "value", "max_value", "min_value_ceiling", "max_value_ceiling",
                    "suite", "skill", "description", "damage_type", "duration"}})
            else:
                result.extend(effects(child))
    return result


def equipment_file(name):
    return name in OTHER or (name.startswith("amr_") and name not in {"amr_bases.gas", "amr_generic_sets.gas"}) \
        or (name.startswith("wpn_") and name[4:-4] in WEAPONS)


def build(source):
    templates, origins, parsed = {}, {}, {}
    for path in sorted(source.glob("*.gas")):
        text = path.read_text(encoding="latin1")
        if path.name == "set_definitions.gas":
            # Installed AS7_set total_4 omits ONE opening brace. Record the
            # transcription repair below; never alter the source file/numbers.
            text, repairs = re.subn(r'(\[\*\]\s*)(?=alteration\s*=\s*alter_chance_to_dodge_hit;\s*value\s*=\s*0\.12;)',
                                    r'\1{\n', text)
            assert repairs == 1, repairs
        tree = parse(text)
        parsed[path.name] = tree
        for key, values in tree["children"].items():
            if key.lower().startswith("t:template,n:"):
                ident = key.split(":", 2)[2]
                assert ident not in templates, ident
                templates[ident], origins[ident] = values[0], path.name
    resolved, missing = {}, set()
    canonical = {ident.lower(): ident for ident in templates}

    def resolve(ident, trail=()):
        if ident in resolved:
            return resolved[ident]
        assert ident not in trail, (ident, trail)
        raw = templates[ident]
        parent = raw["fields"].get("specializes", "")
        parent = canonical.get(parent.lower(), parent)
        if parent and parent not in templates:
            missing.add(parent)
        out = merge(resolve(parent, trail + (ident,)), raw) if parent in templates else copy.deepcopy(raw)
        resolved[ident] = out
        return out

    items = []
    for ident in sorted(templates):
        if not equipment_file(origins[ident]):
            continue
        if ident.lower().startswith("base_"):
            continue
        node = resolve(ident)
        common, gui = section(node, "common")["fields"], section(node, "gui")["fields"]
        if not common.get("screen_name"):
            continue
        variants = []
        for variant, nodes in section(node, "pcontent")["children"].items():
            for child in nodes:
                if "item_level" in child["fields"]:
                    variants.append({"variant": variant, **{k: v for k, v in child["fields"].items()
                                                           if k in {"item_level", "inventory_icon"}}})
        if not variants and "item_level" in gui:
            variants = [{"variant": "base", "item_level": gui["item_level"]}]
        category = "crafted" if origins[ident] == "crafted_items.gas" else common.get("rarity", "normal")
        items.append({"id": ident, "source": origins[ident], "name": common["screen_name"],
                      "base_name": common.get("base_screen_name", common["screen_name"]),
                      "category": category, "parent": templates[ident]["fields"].get("specializes", ""),
                      "pcontent_allowed": common.get("is_pcontent_allowed", "true"),
                      "allow_modifiers": common.get("allow_modifiers", "true"),
                      "variants": variants, "requirements": gui.get("equip_requirements", ""),
                      "slot": gui.get("equip_slot", ""), "class": gui.get("use_class", ""),
                      "set": gui.get("set", ""), "icon_reference": gui.get("inventory_icon", ""),
                      "attack": {k: v for k, v in section(node, "attack")["fields"].items() if k in {
                          "damage_min", "damage_max", "reload_delay", "attack_range", "skill_class", "is_melee", "is_two_handed"}},
                      "armor": section(node, "defend")["fields"].get("defense", ""),
                      "effects": effects(section(node, "magic"))})

    modifiers = section(parsed["pcontent.gas"], "modifiers")["children"]
    mod_cache = {}

    def resolve_mod(ident, trail=()):
        assert ident not in trail, ident
        if ident not in mod_cache:
            raw = modifiers[ident][0]
            parent = raw["fields"].get("specializes", "")
            mod_cache[ident] = merge(resolve_mod(parent, trail + (ident,)), raw) if parent else raw
        return mod_cache[ident]

    affixes = []
    for ident in sorted(modifiers):
        node = resolve_mod(ident)
        affixes.append({"id": ident, **{k: v for k, v in node["fields"].items() if k in {
            "screen_name", "level", "type", "object_types", "skill_types", "family",
            "exclusion_family_1", "exclusion_family_2", "exclusion_family_3", "exclusion_family_4"}},
                       "effects": effects(node)})
    sets = []
    for key, nodes in section(parsed["set_definitions.gas"], "set_definitions")["children"].items():
        node = nodes[0]
        sets.append({"id": key.split("n:", 1)[1], "name": node["fields"]["screen_name"],
                     "pieces": int(node["fields"]["num_pieces"]),
                     "totals": {name: effects({"fields": {}, "children": {"bonus": values}})
                                for name, values in node["children"].items() if name.startswith("total_")}})
    return {"schema": 1, "runtime_imported": False,
            "source_notes": ["AS7_set total_4: missing opening brace transcribed; numeric values unchanged. Engine handling unverified."],
            "items": items, "affixes": affixes, "sets": sets,
            "unresolved_parents": sorted(missing)}


def main():
    source = ROOT / "ds2_source/ds2_catalog_source"
    names = [name for name, _ in list_files() if equipment_file(name)]
    names += ["templates.gas", "wpn_bases.gas", "amr_bases.gas", "amr_generic_sets.gas", "pcontent.gas", "set_definitions.gas"]
    extract_targets(str(source), names)
    output = build(source)
    output["source_archive"] = Path(DEFAULT_GAME_RES).name
    output["source_sha256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source.glob("*.gas"))}
    target = ROOT / "data/reference/ds2_equipment_catalog.json"
    target.write_text(json.dumps(output, indent=2, ensure_ascii=True) + "\n", encoding="utf-8", newline="\n")
    counts = {kind: sum(i["category"] == kind for i in output["items"]) for kind in sorted({i["category"] for i in output["items"]})}
    print(json.dumps({"items": counts, "affixes": len(output["affixes"]), "sets": len(output["sets"]),
                      "unresolved_parents": output["unresolved_parents"]}, indent=2))


if __name__ == "__main__":
    main()
