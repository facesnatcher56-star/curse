import json
import glob
import os
import re

def generate():
    # 1. Load Curse passives
    curse_passives = {}
    for path in sorted(glob.glob("data/passives/*.tres")):
        pid = os.path.splitext(os.path.basename(path))[0]
        content = open(path, encoding="utf-8").read()
        tree = re.search(r'tree = "([^"]+)"', content)
        disp = re.search(r'display_name = "([^"]+)"', content)
        tier = re.search(r'tier = (\d+)', content)
        curse_passives[pid] = {
            "id": pid,
            "tree": tree.group(1) if tree else "",
            "display_name": disp.group(1) if disp else pid,
            "tier": int(tier.group(1)) if tier else 0,
            "path": path.replace("\\", "/")
        }

    # 2. Canonical definitions of all 14 DS2 skill suites
    suite_definitions = {
        "melee_suite_1": {
            "discipline": "melee",
            "skills": ["Barricade", "Toughness", "Reinforced Armor"],
            "description_template": "+<value> to Barricade, Toughness, and Reinforced Armor"
        },
        "melee_suite_2": {
            "discipline": "melee",
            "skills": ["Fortitude", "Overbear", "Smite"],
            "description_template": "+<value> to Fortitude, Overbear, and Smite"
        },
        "melee_suite_3": {
            "discipline": "melee",
            "skills": ["Critical Strike", "Dual Wield", "Alacrity"],
            "description_template": "+<value> to Critical Strike, Dual Wield, and Alacrity"
        },
        "ranged_suite_1": {
            "discipline": "ranged",
            "skills": ["Critical Shot", "Dodge", "Survival"],
            "description_template": "+<value> to Critical Shot, Dodge, and Survival"
        },
        "ranged_suite_2": {
            "discipline": "ranged",
            "skills": ["Biting Arrow", "Far Shot", "Shockwave"],
            "description_template": "+<value> to Biting Arrow, Far Shot, and Shockwave"
        },
        "ranged_suite_3": {
            "discipline": "ranged",
            "skills": ["Quick Draw", "Bleed", "Penetrate"],
            "description_template": "+<value> to Quick Draw, Bleed, and Penetrate"
        },
        "cmagic_suite_1": {
            "discipline": "combat_magic",
            "skills": ["Debilitation", "Grim Necromancy", "Vampirism"],
            "description_template": "+<value> to Debilitation, Grim Necromancy, and Vampirism"
        },
        "cmagic_suite_2": {
            "discipline": "combat_magic",
            "skills": ["Brilliance", "Amplified Lightning", "Arcing"],
            "description_template": "+<value> to Brilliance, Amplified Lightning, and Arcing"
        },
        "cmagic_suite_3": {
            "discipline": "combat_magic",
            "skills": ["Devastation", "Searing Flames", "Ignite"],
            "description_template": "+<value> to Devastation, Searing Flames, and Ignite"
        },
        "nmagic_suite_1": {
            "discipline": "nature_magic",
            "skills": ["Summon Fortitude", "Summon Might", "Summon Bond"],
            "description_template": "+<value> to Summon Fortitude, Summon Might, and Summon Bond"
        },
        "nmagic_suite_2": {
            "discipline": "nature_magic",
            "skills": ["Aquatic Affinity", "Arctic Mastery", "Freezing"],
            "description_template": "+<value> to Aquatic Affinity, Arctic Mastery, and Freezing"
        },
        "nmagic_suite_3": {
            "discipline": "nature_magic",
            "skills": ["Nurturing Gift", "Enveloping Embrace", "Feral Wrath"],
            "description_template": "+<value> to Nurturing Gift, Enveloping Embrace, and Feral Wrath"
        },
        "special_suite_1": {
            "discipline": "hybrid",
            "skills": ["Summon Alacrity", "Quickened Casting"],
            "description_template": "+<value> to Summon Alacrity and Quickened Casting"
        },
        "special_suite_2": {
            "discipline": "hybrid",
            "skills": ["Fortitude", "Toughness"],
            "description_template": "+<value> to Fortitude and Toughness"
        }
    }

    # Canonical skill name to Curse passive ID
    skill_to_curse = {
        "Barricade": "barricade",
        "Toughness": "toughness",
        "Reinforced Armor": "reinforced_armor",
        "Fortitude": "fortitude",
        "Overbear": "overbear",
        "Smite": "smite",
        "Critical Strike": "critical_strike",
        "Dual Wield": None,
        "Alacrity": "alacrity",
        "Critical Shot": "critical_shot",
        "Dodge": "dodge",
        "Survival": "survival",
        "Biting Arrow": "biting_arrow",
        "Far Shot": "far_shot",
        "Shockwave": None,
        "Quick Draw": "quick_draw",
        "Bleed": "bleed",
        "Penetrate": "penetrate",
        "Debilitation": None,
        "Grim Necromancy": None,
        "Vampirism": None,
        "Brilliance": "brilliance",
        "Amplified Lightning": None,
        "Arcing": None,
        "Devastation": "devastation",
        "Searing Flames": "searing_flames",
        "Ignite": "ignite",
        "Summon Fortitude": None,
        "Summon Might": None,
        "Summon Bond": None,
        "Aquatic Affinity": None,
        "Arctic Mastery": None,
        "Freezing": None,
        "Nurturing Gift": None,
        "Enveloping Embrace": None,
        "Feral Wrath": None,
        "Summon Alacrity": None,
        "Quickened Casting": "quickened_casting"
    }

    # Gameplay status in Curse:
    # 'active': wired and scaling in live PlayerStats / Player / combat code
    # 'dormant': .tres definition exists in data/passives/ but not wired to live combat scaling
    # 'unported': no .tres definition in Curse
    active_in_curse = {
        "barricade", "toughness", "reinforced_armor", "fortitude", "overbear", "smite",
        "critical_strike", "alacrity", "critical_shot", "dodge", "survival", "biting_arrow",
        "brilliance", "devastation", "searing_flames", "ignite", "quickened_casting"
    }
    dormant_in_curse = {
        "far_shot", "quick_draw", "bleed", "penetrate"
    }

    # Count occurrences in catalog
    cat = json.load(open("data/reference/ds2_equipment_catalog.json", encoding="utf-8"))
    suite_item_counts = {s: 0 for s in suite_definitions}
    suite_affix_counts = {s: 0 for s in suite_definitions}
    suite_set_counts = {s: 0 for s in suite_definitions}

    for it in cat.get("items", []):
        for eff in it.get("effects", []):
            if eff.get("alteration") == "alter_skill_suite":
                sid = eff.get("suite")
                if sid in suite_item_counts:
                    suite_item_counts[sid] += 1

    for aff in cat.get("affixes", []):
        for eff in aff.get("effects", []):
            if eff.get("alteration") == "alter_skill_suite":
                sid = eff.get("suite")
                if sid in suite_affix_counts:
                    suite_affix_counts[sid] += 1

    for s in cat.get("sets", []):
        for c, effs in s.get("totals", {}).items():
            for eff in effs:
                if eff.get("alteration") == "alter_skill_suite":
                    sid = eff.get("suite")
                    if sid in suite_set_counts:
                        suite_set_counts[sid] += 1

    # Discipline alterations breakdown
    discipline_alts = {
        "ALTER_MELEE_PASSIVE_SKILLS": {"items": 0, "affixes": 0, "sets": 0, "discipline": "melee"},
        "alter_melee_passive_skills": {"items": 0, "affixes": 0, "sets": 0, "discipline": "melee"},
        "ALTER_RANGED_PASSIVE_SKILLS": {"items": 0, "affixes": 0, "sets": 0, "discipline": "ranged"},
        "ALTER_COMBAT_MAGIC_PASSIVE_SKILLS": {"items": 0, "affixes": 0, "sets": 0, "discipline": "combat_magic"},
        "ALTER_NATURE_MAGIC_PASSIVE_SKILLS": {"items": 0, "affixes": 0, "sets": 0, "discipline": "nature_magic"}
    }

    for it in cat.get("items", []):
        for eff in it.get("effects", []):
            alt = eff.get("alteration")
            if alt in discipline_alts:
                discipline_alts[alt]["items"] += 1

    for aff in cat.get("affixes", []):
        for eff in aff.get("effects", []):
            alt = eff.get("alteration")
            if alt in discipline_alts:
                discipline_alts[alt]["affixes"] += 1

    for s in cat.get("sets", []):
        for c, effs in s.get("totals", {}).items():
            for eff in effs:
                alt = eff.get("alteration")
                if alt in discipline_alts:
                    discipline_alts[alt]["sets"] += 1

    # Build output json
    inventory = {
        "schema": 1,
        "title": "Dungeon Siege II Passive Skill Suites and Discipline Alterations Reference",
        "description": "Source-accurate mappings of all 14 DS2 skill suites and 5 discipline-wide passive alterations to Curse passive definitions and gameplay runtime status.",
        "summary": {
            "total_suites": len(suite_definitions),
            "total_catalog_occurrences": sum(suite_item_counts.values()) + sum(suite_affix_counts.values()) + sum(suite_set_counts.values()) + sum(d["items"] + d["affixes"] + d["sets"] for d in discipline_alts.values()),
            "alter_skill_suite_occurrences": sum(suite_item_counts.values()) + sum(suite_affix_counts.values()) + sum(suite_set_counts.values()),
            "discipline_passive_alteration_occurrences": sum(d["items"] + d["affixes"] + d["sets"] for d in discipline_alts.values()),
            "fully_defined_in_curse_count": 0,
            "partially_defined_in_curse_count": 0,
            "unimplemented_in_curse_count": 0,
            "fully_active_gameplay_count": 0
        },
        "discipline_alterations": {},
        "suites": {}
    }

    for alt_name, counts in discipline_alts.items():
        total = counts["items"] + counts["affixes"] + counts["sets"]
        inventory["discipline_alterations"][alt_name] = {
            "alteration": alt_name,
            "normalized_identifier": alt_name.lower(),
            "discipline": counts["discipline"],
            "occurrences": {
                "items": counts["items"],
                "affixes": counts["affixes"],
                "sets": counts["sets"],
                "total": total
            }
        }

    for sid, sdef in suite_definitions.items():
        skills = sdef["skills"]
        curse_ids = [skill_to_curse[sk] for sk in skills]
        defined_ids = [cid for cid in curse_ids if cid is not None]
        active_ids = [cid for cid in defined_ids if cid in active_in_curse]
        dormant_ids = [cid for cid in defined_ids if cid in dormant_in_curse]
        missing_skills = [sk for sk, cid in zip(skills, curse_ids) if cid is None]

        if len(defined_ids) == len(skills):
            def_status = "fully_defined"
            inventory["summary"]["fully_defined_in_curse_count"] += 1
        elif len(defined_ids) > 0:
            def_status = "partially_defined"
            inventory["summary"]["partially_defined_in_curse_count"] += 1
        else:
            def_status = "unimplemented"
            inventory["summary"]["unimplemented_in_curse_count"] += 1

        if len(active_ids) == len(skills):
            active_status = "fully_active"
            inventory["summary"]["fully_active_gameplay_count"] += 1
        elif len(active_ids) > 0:
            active_status = "partially_active"
        else:
            active_status = "inactive"

        total_occ = suite_item_counts[sid] + suite_affix_counts[sid] + suite_set_counts[sid]

        inventory["suites"][sid] = {
            "suite_id": sid,
            "discipline": sdef["discipline"],
            "description_template": sdef["description_template"],
            "skills": skills,
            "curse_passive_ids": curse_ids,
            "definition_status": def_status,
            "gameplay_status": active_status,
            "constituent_details": [
                {
                    "source_name": sk,
                    "curse_id": cid,
                    "curse_display_name": curse_passives[cid]["display_name"] if cid and cid in curse_passives else None,
                    "status": "active" if cid in active_in_curse else ("dormant" if cid in dormant_in_curse else "unimplemented")
                }
                for sk, cid in zip(skills, curse_ids)
            ],
            "occurrences": {
                "items": suite_item_counts[sid],
                "affixes": suite_affix_counts[sid],
                "sets": suite_set_counts[sid],
                "total": total_occ
            }
        }

    with open("data/reference/ds2_skill_suites.json", "w", encoding="utf-8") as f:
        json.dump(inventory, f, indent=2)
    print("Generated data/reference/ds2_skill_suites.json successfully!")
    print(f"Total occurrences recorded: {inventory['summary']['total_catalog_occurrences']}")
    print(f"Suites fully defined: {inventory['summary']['fully_defined_in_curse_count']}")
    print(f"Suites fully active in gameplay: {inventory['summary']['fully_active_gameplay_count']}")

if __name__ == "__main__":
    generate()
