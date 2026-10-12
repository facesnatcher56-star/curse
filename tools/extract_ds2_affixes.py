#!/usr/bin/env python3
"""Extract supported modifier families from DS2 pcontent.gas into a numeric baseline.
Usage: python tools/extract_ds2_affixes.py PATH_TO_PCONTENT_GAS
"""
import json
import re
import sys
from pathlib import Path


def children(text):
    out = {}
    pos = 0
    while match := re.search(r"\[([\w]+)\]\s*\{", text[pos:]):
        start = pos + match.end()
        end, depth = start, 1
        while depth:
            depth += (text[end] == "{") - (text[end] == "}")
            end += 1
        out[match[1]] = text[start:end - 1]
        pos = end
    return out


ROOTS = {
    "strength": ("ofhardiness", "str"), "dexterity": ("oftheswift", "dex"),
    "intelligence": ("ofawareness", "int"), "life": ("oftherat", "life"), "mana": ("ofthetoad", "mana"),
    "melee_max": ("ofwounding", "melee_max"), "melee_min": ("ofaffliction", "melee_min"),
    "ranged_max": ("ofaccuracy", "ranged_max"), "ranged_min": ("ofpiercing", "ranged_min"),
    "melee_pct": ("cruel", "melee_pct"), "ranged_pct": ("sharp", "ranged_pct"),
    "spell_pct": ("destructive", "spell_pct"),
    "fire_added": ("scorching", "fire_added"), "life_steal": ("oftheparasite", "life_steal"),
    "mana_steal": ("ofthephantom", "mana_steal"), "mana_per_hit": ("ofcandlelight", "mana_per_hit"),
    "life_per_hit": ("ofconsumption", "life_per_hit"), "armor": ("stout", "armor"),
    "armor_pct": ("steadfast", "armor_pct"), "fire_resist": ("crimson", "fire_resist"),
    "reflect": ("ofreversal", "reflect"), "life_regen": ("ofmending", "life_regen"),
    "mana_regen": ("ofbrightening", "mana_regen"), "block": ("ofrepulsion", "block"),
    "block_ranged": ("ofdeflection", "block_ranged"), "recharge": ("rousing", "recharge"),
    "magic_find": ("fortunate", "magic_find"), "gold_find": ("glittering", "gold_find"),
}
FRACTIONS = {"melee_pct", "ranged_pct", "spell_pct", "armor_pct", "fire_resist", "life_regen", "mana_regen", "recharge", "gold_find"}
PERCENT = FRACTIONS | {"life_steal", "mana_steal", "reflect", "block", "block_ranged", "magic_find"}


def field(body, key, default=""):
    match = re.search(r"\b" + key + r"\s*=\s*([^;]+);", body)
    return match[1].strip().strip('"') if match else default


def main():
    text = Path(sys.argv[1]).read_text(encoding="latin1")
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    blocks = children(children(text)["modifiers"])
    output = {}
    for family, (root, stat) in ROOTS.items():
        roots = {root, "charmed"} if family == "magic_find" else {root}
        selected = {name for name in roots}
        while True:
            found = {name for name, body in blocks.items() if field(body, "specializes") in selected}
            if found <= selected:
                break
            selected |= found
        records = []
        for name in selected:
            body = blocks[name]
            base = blocks[root]
            effects = children(body)
            effect = next((v for v in effects.values() if field(v, "value")), None)
            assert effect is not None, name
            scale = 100 if family in FRACTIONS else 1
            value = round(float(field(effect, "value")) * scale, 6)
            maximum = round(float(field(effect, "max_value", str(value / scale))) * scale, 6)
            ceiling = round(float(field(effect, "min_value_ceiling", str(value / scale))) * scale, 6)
            kinds = field(base, "object_types").split(",")
            slots = []
            for kind in kinds:
                kind = kind.strip()
                slots += ["body", "helm", "gloves", "boots", "shield"] if kind == "armor" else ["weapon"] if kind in {"weapon", "melee", "ranged"} else [kind] if kind != "spellbook" else []
            records.append(dict(source=name, title=field(body, "screen_name"), level=int(field(body, "level")),
                                value=value, max_value=maximum, value_ceiling=ceiling, stat=stat, percent=family in PERCENT,
                                position=field(base, "type"), slots=sorted(set(slots)),
                                classes=field(base, "skill_types").split(",") if field(base, "skill_types") else []))
        output[family] = sorted(records, key=lambda r: r["level"])
    path = Path(__file__).resolve().parents[1] / "data/reference/ds2_affixes.json"
    path.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("wrote", sum(map(len, output.values())), "source modifier tiers")


if __name__ == "__main__":
    main()
