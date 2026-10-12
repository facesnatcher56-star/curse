#!/usr/bin/env python3
"""
Generate the Dungeon Siege II equipment effect and property coverage manifest.
Outputs data/reference/ds2_effect_coverage_manifest.json.

Deterministic generator that maps all 58 alterations, template fields, and
requirement patterns from data/reference/ds2_equipment_catalog.json to Curse runtime
systems, strictly classifying them as supported, unsupported, unresolved, cosmetic_only, or excluded.
"""

import json
import os
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG_PATH = os.path.join(BASE_DIR, "data", "reference", "ds2_equipment_catalog.json")
MANIFEST_PATH = os.path.join(BASE_DIR, "data", "reference", "ds2_effect_coverage_manifest.json")


def build_manifest_data(catalog):
    items = catalog.get("items", [])
    affixes = catalog.get("affixes", [])
    sets = catalog.get("sets", [])

    # Collect source occurrences for all 58 alterations
    alt_stats = {}
    for it in items:
        for eff in it.get("effects", []):
            alt = eff["alteration"]
            if alt not in alt_stats:
                alt_stats[alt] = {"items": 0, "affixes": 0, "sets": 0, "sample_descriptions": set()}
            alt_stats[alt]["items"] += 1
            desc = eff.get("description", "")
            if desc and len(alt_stats[alt]["sample_descriptions"]) < 3:
                alt_stats[alt]["sample_descriptions"].add(desc)

    for aff in affixes:
        for eff in aff.get("effects", []):
            alt = eff["alteration"]
            if alt not in alt_stats:
                alt_stats[alt] = {"items": 0, "affixes": 0, "sets": 0, "sample_descriptions": set()}
            alt_stats[alt]["affixes"] += 1
            desc = eff.get("description", "")
            if desc and len(alt_stats[alt]["sample_descriptions"]) < 3:
                alt_stats[alt]["sample_descriptions"].add(desc)

    for s in sets:
        for t_name, effs in s.get("totals", {}).items():
            for eff in effs:
                alt = eff["alteration"]
                if alt not in alt_stats:
                    alt_stats[alt] = {"items": 0, "affixes": 0, "sets": 0, "sample_descriptions": set()}
                alt_stats[alt]["sets"] += 1
                desc = eff.get("description", "")
                if desc and len(alt_stats[alt]["sample_descriptions"]) < 3:
                    alt_stats[alt]["sample_descriptions"].add(desc)

    # 58 Alterations Definitions
    alterations = {
        # --- SUPPORTED ALTERATIONS (25) ---
        "alter_strength": {
            "status": "supported",
            "category": "attribute",
            "runtime_key": "str",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["amulet", "ring", "armor", "weapon"],
            "source_evidence": "alter_strength in items, affixes (e.g. +<value> Strength).",
            "runtime_consumer": "game/player/player_stats.gd:refresh()",
            "test_path": "tests/test_stats.gd",
            "notes": "Direct additive bonus to base Strength attribute."
        },
        "alter_dexterity": {
            "status": "supported",
            "category": "attribute",
            "runtime_key": "dex",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["amulet", "ring", "armor", "weapon"],
            "source_evidence": "alter_dexterity in items, affixes (e.g. +<value> Dexterity).",
            "runtime_consumer": "game/player/player_stats.gd:refresh()",
            "test_path": "tests/test_stats.gd",
            "notes": "Direct additive bonus to base Dexterity attribute."
        },
        "alter_intelligence": {
            "status": "supported",
            "category": "attribute",
            "runtime_key": "int",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["amulet", "ring", "armor", "weapon"],
            "source_evidence": "alter_intelligence in items, affixes (e.g. +<value> Intelligence).",
            "runtime_consumer": "game/player/player_stats.gd:refresh()",
            "test_path": "tests/test_stats.gd",
            "notes": "Direct additive bonus to base Intelligence attribute."
        },
        "alter_max_life": {
            "status": "supported",
            "category": "vital",
            "runtime_key": "life",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_max_life in items, affixes, sets (e.g. +<value> Health).",
            "runtime_consumer": "game/player/player_stats.gd:refresh()",
            "test_path": "tests/test_stats.gd",
            "notes": "Increases maximum player health."
        },
        "alter_max_mana": {
            "status": "supported",
            "category": "vital",
            "runtime_key": "mana",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "spellbook"],
            "source_evidence": "alter_max_mana in items, affixes, sets (e.g. +<value> Mana).",
            "runtime_consumer": "game/player/player_stats.gd:refresh()",
            "test_path": "tests/test_stats.gd",
            "notes": "Increases maximum player mana."
        },
        "alter_melee_damage_min": {
            "status": "supported",
            "category": "weapon_damage",
            "runtime_key": "melee_min",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["melee", "ring", "amulet"],
            "source_evidence": "alter_melee_damage_min in items, affixes, sets.",
            "runtime_consumer": "game/player/player_stats.gd:weapon_range()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Adds flat minimum melee damage."
        },
        "alter_melee_damage_max": {
            "status": "supported",
            "category": "weapon_damage",
            "runtime_key": "melee_max",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["melee", "ring", "amulet"],
            "source_evidence": "alter_melee_damage_max in items, affixes, sets (e.g. +<value> Melee Damage).",
            "runtime_consumer": "game/player/player_stats.gd:weapon_range()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Adds flat maximum melee damage."
        },
        "alter_ranged_damage_min": {
            "status": "supported",
            "category": "weapon_damage",
            "runtime_key": "ranged_min",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["ranged", "ring", "amulet"],
            "source_evidence": "alter_ranged_damage_min in items, affixes, sets.",
            "runtime_consumer": "game/player/player_stats.gd:ranged_range()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Adds flat minimum ranged damage."
        },
        "alter_ranged_damage_max": {
            "status": "supported",
            "category": "weapon_damage",
            "runtime_key": "ranged_max",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["ranged", "ring", "amulet"],
            "source_evidence": "alter_ranged_damage_max in items, affixes, sets (e.g. +<value> Ranged Damage).",
            "runtime_consumer": "game/player/player_stats.gd:ranged_range()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Adds flat maximum ranged damage."
        },
        "alter_custom_damage_fire": {
            "status": "supported",
            "category": "elemental_damage",
            "runtime_key": "fire_added, fire_added_max",
            "units": "damage_range",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_custom_damage_fire in items, affixes, sets (e.g. Adds <value> to <max_value> Fire Damage).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/combat.gd:resolve()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Flat added fire damage evaluated in combat resolution."
        },
        "alter_melee_damage_source_percent": {
            "status": "supported",
            "category": "damage_multiplier",
            "runtime_key": "melee_pct",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_melee_damage_source_percent in items, affixes, sets (e.g. +10% Melee Damage).",
            "runtime_consumer": "game/player/player_stats.gd:weapon_range()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Percentage scalar on total melee damage."
        },
        "alter_ranged_damage_source_percent": {
            "status": "supported",
            "category": "damage_multiplier",
            "runtime_key": "ranged_pct",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_ranged_damage_source_percent in items, affixes, sets (e.g. +10% Ranged Damage).",
            "runtime_consumer": "game/player/player_stats.gd:ranged_range()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Percentage scalar on total ranged damage."
        },
        "alter_cmagic_damage_percent": {
            "status": "supported",
            "category": "spell_multiplier",
            "runtime_key": "spell_pct",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["spellbook", "ring", "amulet", "armor"],
            "source_evidence": "alter_cmagic_damage_percent in items, affixes, sets (e.g. +<value>% Combat Magic Damage).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/abilities/fireball.gd",
            "test_path": "tests/test_stats.gd",
            "notes": "Maps to spell_pct which scales Combat Magic spells like Fireball."
        },
        "alter_armor": {
            "status": "supported",
            "category": "defense",
            "runtime_key": "armor",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "shield", "ring", "amulet"],
            "source_evidence": "alter_armor in items, affixes, sets (e.g. +<value> Armor).",
            "runtime_consumer": "game/player/player_stats.gd:total_armor()",
            "test_path": "tests/test_stats.gd",
            "notes": "Direct additive bonus to total armor."
        },
        "alter_armor_source_percent": {
            "status": "supported",
            "category": "defense_multiplier",
            "runtime_key": "armor_pct",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet"],
            "source_evidence": "alter_armor_source_percent in items, affixes (e.g. +100% Armor).",
            "runtime_consumer": "game/player/player_stats.gd:total_armor()",
            "test_path": "tests/test_stats.gd",
            "notes": "Percentage scalar on base item armor."
        },
        "alter_fire_resistance": {
            "status": "supported",
            "category": "resistance",
            "runtime_key": "fire_resist",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_fire_resistance in items, affixes, sets (e.g. +<value>% Fire Resistance).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/combat.gd:resolve()",
            "test_path": "tests/test_stats.gd",
            "notes": "Percentage reduction of incoming fire damage."
        },
        "alter_chance_to_block_melee_damage": {
            "status": "supported",
            "category": "shield_block",
            "runtime_key": "block",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["shield", "amulet"],
            "source_evidence": "alter_chance_to_block_melee_damage in items, affixes, sets (e.g. +<value>% Chance to Block Melee Attacks).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/combat.gd:resolve()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Shield block chance against melee attacks."
        },
        "alter_chance_to_block_ranged_damage": {
            "status": "supported",
            "category": "shield_block",
            "runtime_key": "block_ranged",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["shield", "amulet"],
            "source_evidence": "alter_chance_to_block_ranged_damage in items, affixes, sets (e.g. +<value>% Chance to Block Ranged Attacks).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/combat.gd:resolve()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Shield block chance against ranged attacks."
        },
        "alter_life_steal": {
            "status": "supported",
            "category": "sustain_steal",
            "runtime_key": "life_steal",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_life_steal in items, affixes, sets (e.g. <value>% Health Steal).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_steal_resources()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Percentage of physical damage dealt returned as health on hit."
        },
        "alter_mana_steal": {
            "status": "supported",
            "category": "sustain_steal",
            "runtime_key": "mana_steal",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_mana_steal in items, affixes, sets (e.g. <value>% Mana Steal).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_steal_resources()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Percentage of physical damage dealt returned as mana on hit."
        },
        "alter_life_bonus": {
            "status": "supported",
            "category": "sustain_hit",
            "runtime_key": "life_on_hit",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_life_bonus in items, affixes, sets (e.g. +<value> Health on Hit).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_steal_resources()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Flat health restored on hit."
        },
        "alter_mana_bonus": {
            "status": "supported",
            "category": "sustain_hit",
            "runtime_key": "mana_on_hit",
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_mana_bonus in items, affixes, sets (e.g. +<value> Mana on Hit).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_steal_resources()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Flat mana restored on hit."
        },
        "alter_life_recovery_unit": {
            "status": "supported",
            "category": "regen",
            "runtime_key": "life_regen",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet"],
            "source_evidence": "alter_life_recovery_unit in items, affixes, sets (e.g. +<value>% Health Regeneration).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_process_regen()",
            "test_path": "tests/test_stats.gd",
            "notes": "Passive health regeneration rate multiplier."
        },
        "alter_mana_recovery_unit": {
            "status": "supported",
            "category": "regen",
            "runtime_key": "mana_regen",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "spellbook"],
            "source_evidence": "alter_mana_recovery_unit in items, affixes, sets (e.g. +<value>% Mana Regeneration).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_process_regen()",
            "test_path": "tests/test_stats.gd",
            "notes": "Passive mana regeneration rate multiplier."
        },
        "alter_reflect_damage": {
            "status": "supported",
            "category": "retaliation",
            "runtime_key": "reflect",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["shield", "armor", "ring", "amulet"],
            "source_evidence": "alter_reflect_damage in items, affixes, sets (e.g. <value>% Damage Reflected).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/player/player.gd:_on_received_hit()",
            "test_path": "tests/test_equipment_hits.gd",
            "notes": "Reflects incoming physical damage back to attacker."
        },
        "alter_magic_find_chance": {
            "status": "supported",
            "category": "utility",
            "runtime_key": "magic_find",
            "units": "flat_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet"],
            "source_evidence": "alter_magic_find_chance in items, affixes, sets (e.g. +<value>% Chance to Find Magic Items).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/loot.gd",
            "test_path": "tests/test_find_rates.gd",
            "notes": "Additive bonus to loot rarity roll chances."
        },
        "alter_gold_dropped": {
            "status": "supported",
            "category": "utility",
            "runtime_key": "gold_find",
            "units": "flat_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet"],
            "source_evidence": "alter_gold_dropped in items, affixes, sets (e.g. +<value>% Extra Gold From Monsters).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/loot.gd",
            "test_path": "tests/test_find_rates.gd",
            "notes": "Additive bonus to dropped gold quantity."
        },
        "alter_power_reload": {
            "status": "supported",
            "category": "utility",
            "runtime_key": "recharge",
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_power_reload in items, affixes, sets (e.g. +<value>% Power Recharge Rate).",
            "runtime_consumer": "game/player/player_stats.gd:refresh(), game/powers/",
            "test_path": "tests/test_stats.gd",
            "notes": "Reduces power cooldowns and recharge timers."
        },

        # --- UNSUPPORTED ALTERATIONS (32) ---
        "alter_custom_damage_ice": {
            "status": "unsupported",
            "category": "elemental_damage",
            "runtime_key": None,
            "units": "damage_range",
            "target": "combat_damage",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_custom_damage_ice in items, affixes, sets (e.g. Adds <value> to <max_value> Ice Damage).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Requires adding ice damage calculation and cold status pipeline to Combat."
        },
        "alter_custom_damage_lightning": {
            "status": "unsupported",
            "category": "elemental_damage",
            "runtime_key": None,
            "units": "damage_range",
            "target": "combat_damage",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_custom_damage_lightning in items, affixes, sets (e.g. Adds <value> to <max_value> Lightning Damage).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Requires adding lightning damage calculation to Combat."
        },
        "alter_custom_damage_death": {
            "status": "unsupported",
            "category": "elemental_damage",
            "runtime_key": None,
            "units": "damage_range",
            "target": "combat_damage",
            "stacking": "additive",
            "applicable_families": ["weapon", "ring", "amulet"],
            "source_evidence": "alter_custom_damage_death in items, affixes, sets (e.g. Adds <value> to <max_value> Death Damage).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Requires adding death damage calculation to Combat."
        },
        "alter_ice_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_ice_resistance in items, affixes, sets (e.g. +<value>% Ice Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Requires independent ice resistance stat on PlayerStats and mitigation in Combat."
        },
        "alter_lightning_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_lightning_resistance in items, affixes, sets (e.g. +<value>% Lightning Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Requires independent lightning resistance stat on PlayerStats and mitigation in Combat."
        },
        "alter_death_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_death_resistance in items, affixes, sets (e.g. +<value>% Death Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Requires independent death resistance stat on PlayerStats and mitigation in Combat."
        },
        "alter_magical_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_magical_resistance in items, affixes, sets (e.g. +<value>% Magic Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "General magic resistance mitigation pipeline missing."
        },
        "alter_physical_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_physical_resistance in items, affixes, sets (e.g. +<value>% Physical Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Flat percentage physical mitigation separate from armor defense formula missing."
        },
        "alter_melee_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_melee_resistance in items, affixes, sets (e.g. +<value>% Melee Damage Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Attack-type specific physical mitigation missing."
        },
        "alter_ranged_resistance": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "shield"],
            "source_evidence": "alter_ranged_resistance in items, affixes, sets (e.g. +<value>% Ranged Damage Resistance).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Attack-type specific ranged physical mitigation missing."
        },
        "alter_block_combat_magic_damage": {
            "status": "unsupported",
            "category": "defense",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["staff", "shield"],
            "source_evidence": "alter_block_combat_magic_damage on quest_staff_a1_tower ('Magic Damage Reduced by 6%').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Spell damage reduction / block on equipment missing."
        },
        "alter_chance_to_dodge_hit": {
            "status": "unsupported",
            "category": "defense_dodge",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor"],
            "source_evidence": "alter_chance_to_dodge_hit in items (e.g. +3% Chance to Dodge Ranged and Melee Attacks).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "General gear-derived dodge bonus missing from combat resolution."
        },
        "alter_chance_to_dodge_hit_melee": {
            "status": "unsupported",
            "category": "defense_dodge",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "set"],
            "source_evidence": "alter_chance_to_dodge_hit_melee in items, sets (e.g. +4% Chance to Dodge Melee Attacks).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Melee-specific dodge bonus missing."
        },
        "alter_chance_to_dodge_hit_ranged": {
            "status": "unsupported",
            "category": "defense_dodge",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "weapon"],
            "source_evidence": "alter_chance_to_dodge_hit_ranged in items (e.g. +12% Chance to Dodge Ranged Attacks).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Ranged-specific dodge bonus missing."
        },
        "ALTER_CHANCE_TO_DODGE_HIT_RANGED": {
            "status": "unsupported",
            "category": "defense_dodge",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor"],
            "source_evidence": "ALTER_CHANCE_TO_DODGE_HIT_RANGED in 2 unique body armors (uppercase variant).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Uppercase variant of alter_chance_to_dodge_hit_ranged in source gas."
        },
        "alter_nmagic_damage_percent": {
            "status": "unsupported",
            "category": "spell_multiplier",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet", "spellbook"],
            "source_evidence": "alter_nmagic_damage_percent in items, affixes, sets (e.g. +<value>% Nature Magic Damage).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Nature magic spell damage multiplier missing (Curse currently only has combat magic Fireball)."
        },
        "ALTER_POWER_DAMAGE_PERCENT": {
            "status": "unsupported",
            "category": "power_multiplier",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "amulet"],
            "source_evidence": "ALTER_POWER_DAMAGE_PERCENT in items, affixes, sets (e.g. +<value>% Power Damage).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Equipment-driven damage bonus for activated powers missing from power pipelines."
        },
        "alter_combat_magic": {
            "status": "unsupported",
            "category": "skill_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["staff"],
            "source_evidence": "alter_combat_magic on quest_staff_a1_tower ('Adds 1 to Combat Magic Skill').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Direct discipline level bonus from gear missing."
        },
        "alter_nature_magic": {
            "status": "unsupported",
            "category": "skill_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["staff"],
            "source_evidence": "alter_nature_magic on quest_staff_a1_tower ('Adds 1 to Nature Magic Skill').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Direct discipline level bonus from gear missing."
        },
        "alter_melee_passive_skills": {
            "status": "unsupported",
            "category": "passive_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "weapon"],
            "source_evidence": "alter_melee_passive_skills in items (e.g. +<value> to Melee Skills).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Bonus to all melee passive skill ranks."
        },
        "ALTER_MELEE_PASSIVE_SKILLS": {
            "status": "unsupported",
            "category": "passive_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "weapon", "affix", "set"],
            "source_evidence": "ALTER_MELEE_PASSIVE_SKILLS in items, affixes, sets (uppercase variant).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Uppercase variant of alter_melee_passive_skills."
        },
        "ALTER_RANGED_PASSIVE_SKILLS": {
            "status": "unsupported",
            "category": "passive_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["ranged", "amulet", "armor", "affix", "set"],
            "source_evidence": "ALTER_RANGED_PASSIVE_SKILLS in items, affixes, sets (e.g. +<value> to Ranged Skills).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Bonus to all ranged passive skill ranks."
        },
        "ALTER_COMBAT_MAGIC_PASSIVE_SKILLS": {
            "status": "unsupported",
            "category": "passive_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["spellbook", "amulet", "armor", "affix", "set"],
            "source_evidence": "ALTER_COMBAT_MAGIC_PASSIVE_SKILLS in items, affixes, sets (e.g. +<value> to Combat Magic Skills).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Bonus to all combat magic passive skill ranks."
        },
        "ALTER_NATURE_MAGIC_PASSIVE_SKILLS": {
            "status": "unsupported",
            "category": "passive_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["spellbook", "amulet", "armor", "affix", "set"],
            "source_evidence": "ALTER_NATURE_MAGIC_PASSIVE_SKILLS in items, affixes, sets (e.g. +<value> to Nature Magic Skills).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Bonus to all nature magic passive skill ranks."
        },
        "alter_skill_suite": {
            "status": "unsupported",
            "category": "suite_bonus",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["armor", "weapon", "ring", "amulet", "set"],
            "source_evidence": "alter_skill_suite with 14 distinct suite identifiers across items, affixes, sets.",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Grants bonuses to specific triplets or pairs of passive skills (e.g. melee_suite_1: Barricade, Toughness, Reinforced Armor)."
        },
        "ALTER_FREEZE_CHANCE": {
            "status": "unsupported",
            "category": "on_hit_effect",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "combat_effects",
            "stacking": "additive",
            "applicable_families": ["armor", "ring", "weapon"],
            "source_evidence": "ALTER_FREEZE_CHANCE in 4 crafted items (e.g. 3% chance to Freeze Enemies).",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "On-hit status effect application missing from runtime."
        },
        "ALTER_DEBUFF_RESISTANCE": {
            "status": "unsupported",
            "category": "resistance",
            "runtime_key": None,
            "units": "fractional_percent",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["ring", "amulet"],
            "source_evidence": "ALTER_DEBUFF_RESISTANCE in 3 crafted items ('5% Curse Resistance').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Debuff / curse duration/potency reduction missing."
        },
        "ALTER_EXPERIENCE_GAINED": {
            "status": "unsupported",
            "category": "utility",
            "runtime_key": None,
            "units": "flat_percent",
            "target": "player_progression",
            "stacking": "additive",
            "applicable_families": ["ring"],
            "source_evidence": "ALTER_EXPERIENCE_GAINED in mgc_a3_elt_crafted_6 ('+8% Experience Bonus').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "XP gain multiplier from equipment missing."
        },
        "ALTER_INTELLIGENCE": {
            "status": "unsupported",
            "category": "attribute",
            "runtime_key": None,
            "units": "flat_integer",
            "target": "player_stats",
            "stacking": "additive",
            "applicable_families": ["ring"],
            "source_evidence": "ALTER_INTELLIGENCE in mgc_a3_vet_crafted_3 ('+25 Intelligence').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "Uppercase variant of alter_intelligence. Currently unmapped in PlayerStats."
        },

        # --- UNRESOLVED ALTERATIONS (1) ---
        "alter_generic": {
            "status": "unresolved",
            "category": "generic_script",
            "runtime_key": None,
            "units": "arbitrary_skrit",
            "target": "skrit_engine",
            "stacking": "unknown",
            "applicable_families": ["weapon", "set"],
            "source_evidence": "alter_generic across 89 item records and 3 mysterious set tiers with unextracted Skrit hooks (e.g. ax_1h_ba_unq_01, '5 2 6 4 3 9 2 8').",
            "runtime_consumer": None,
            "test_path": None,
            "notes": "89 instances refer to proprietary DS2 Skrit script callbacks whose logic and parameters are not documented in the checked-in catalog JSON."
        }
    }

    # Template Properties Definitions (17 top-level + 7 attack fields)
    template_properties = {
        "id": {
            "status": "supported",
            "category": "identity",
            "runtime_key": "id",
            "consumer": "game/data/item_db.gd, game/items.gd",
            "notes": "Unique identifier for item template."
        },
        "source": {
            "status": "cosmetic_only",
            "category": "provenance",
            "runtime_key": None,
            "consumer": None,
            "notes": "Source .gas filename in original DS2 Logic.ds2res archive."
        },
        "name": {
            "status": "supported",
            "category": "presentation",
            "runtime_key": "name",
            "consumer": "game/items.gd",
            "notes": "Display name of the item template."
        },
        "base_name": {
            "status": "supported",
            "category": "presentation",
            "runtime_key": "base_name",
            "consumer": "game/items.gd",
            "notes": "Base item type name for affix naming synthesis."
        },
        "category": {
            "status": "supported",
            "category": "classification",
            "runtime_key": "rarity / category",
            "consumer": "game/items.gd",
            "notes": "normal, crafted, unique, set, rare."
        },
        "parent": {
            "status": "supported",
            "category": "classification",
            "runtime_key": "family / type",
            "consumer": "game/data/item_db.gd",
            "notes": "Base template inheritance parent."
        },
        "pcontent_allowed": {
            "status": "supported",
            "category": "loot_generation",
            "runtime_key": "pcontent_allowed",
            "consumer": "game/loot.gd",
            "notes": "Determines if item can spawn via dynamic procedural loot."
        },
        "allow_modifiers": {
            "status": "supported",
            "category": "affix_generation",
            "runtime_key": "allow_modifiers",
            "consumer": "game/data/item_db.gd, game/data/affix_db.gd",
            "notes": "Determines whether magical prefixes/suffixes can roll on this base item."
        },
        "variants": {
            "status": "supported",
            "category": "level_scaling",
            "runtime_key": "variants",
            "consumer": "game/data/item_db.gd",
            "notes": "List of variant definitions with level and icon tiers."
        },
        "requirements": {
            "status": "supported",
            "category": "equip_requirement",
            "runtime_key": "requirements",
            "consumer": "game/items.gd:can_equip()",
            "notes": "Discipline level requirements (single requirements supported; compound and passives unsupported)."
        },
        "slot": {
            "status": "supported",
            "category": "equipment_slot",
            "runtime_key": "slot",
            "consumer": "game/items.gd, game/player/equipment.gd",
            "notes": "es_weapon_hand, es_shield_hand, es_chest, es_head, es_forearms, es_feet (es_spellbook unsupported, rings/amulets have empty slot string in source catalog)."
        },
        "class": {
            "status": "supported",
            "category": "class_restriction",
            "runtime_key": "item_class",
            "consumer": "game/items.gd",
            "notes": "IST_FIGHTER, IST_RANGER, IST_CMAGE, IST_NMAGE, IST_ALL, IST_MAGE."
        },
        "set": {
            "status": "unsupported",
            "category": "set_bonus",
            "runtime_key": None,
            "consumer": None,
            "notes": "Reference to parent set ID. Curse lacks set bonus tracker and set completion evaluation."
        },
        "icon_reference": {
            "status": "cosmetic_only",
            "category": "presentation",
            "runtime_key": "icon_texture",
            "consumer": "UI asset pipelines",
            "notes": "Original DS2 bitmap texture reference string."
        },
        "attack": {
            "status": "supported",
            "category": "weapon_stats",
            "runtime_key": "attack",
            "consumer": "game/items.gd, game/player/player_stats.gd",
            "notes": "Weapon damage, speed, range container."
        },
        "armor": {
            "status": "supported",
            "category": "armor_stats",
            "runtime_key": "defense / armor",
            "consumer": "game/items.gd, game/player/player_stats.gd",
            "notes": "Base item armor formula expression."
        },
        "effects": {
            "status": "supported",
            "category": "item_effects",
            "runtime_key": "modifiers",
            "consumer": "game/items.gd, game/player/player_stats.gd",
            "notes": "Inherent item modifier array."
        },
        # Attack sub-fields
        "attack.damage_min": {
            "status": "supported",
            "category": "weapon_damage",
            "runtime_key": "damage_min",
            "consumer": "game/items.gd, game/player/player_stats.gd",
            "notes": "Minimum base weapon damage formula."
        },
        "attack.damage_max": {
            "status": "supported",
            "category": "weapon_damage",
            "runtime_key": "damage_max",
            "consumer": "game/items.gd, game/player/player_stats.gd",
            "notes": "Maximum base weapon damage formula."
        },
        "attack.is_melee": {
            "status": "supported",
            "category": "combat_style",
            "runtime_key": "is_melee",
            "consumer": "game/items.gd, game/combat.gd",
            "notes": "Flag distinguishing melee attacks from ranged attacks."
        },
        "attack.is_two_handed": {
            "status": "supported",
            "category": "grip_type",
            "runtime_key": "is_two_handed",
            "consumer": "game/items.gd, game/player/equipment.gd",
            "notes": "Flag indicating weapon occupies both hands and unequips shields."
        },
        "attack.reload_delay": {
            "status": "supported",
            "category": "attack_speed",
            "runtime_key": "attack_speed / cooldown",
            "consumer": "game/player/player.gd",
            "notes": "Attack delay / recovery period in seconds."
        },
        "attack.skill_class": {
            "status": "supported",
            "category": "combat_discipline",
            "runtime_key": "skill_class",
            "consumer": "game/items.gd, game/player/player_stats.gd",
            "notes": "'melee' or 'ranged'."
        },
        "attack.attack_range": {
            "status": "supported",
            "category": "range",
            "runtime_key": "attack_range",
            "consumer": "game/player/player.gd, game/combat.gd",
            "notes": "Maximum targeting/firing distance in world units (7.5 to 11.0 meters)."
        }
    }

    # Requirement Syntax Patterns (60 distinct raw strings mapped to 7 syntactic classes)
    requirement_patterns = {
        "discipline_offset": {
            "status": "supported",
            "syntax": "<discipline>:#item_level - <offset>",
            "occurrences": 346,
            "examples": ["melee:#item_level - 2.0", "ranged:#item_level - 8.0", "combat magic:#item_level-2.0"],
            "runtime_consumer": "game/items.gd:can_equip()",
            "notes": "Supported for single discipline level requirement offset from item level."
        },
        "discipline_fixed": {
            "status": "supported",
            "syntax": "<discipline>:<level>",
            "occurrences": 2,
            "examples": ["melee:0"],
            "runtime_consumer": "game/items.gd:can_equip()",
            "notes": "Supported for fixed discipline level requirements."
        },
        "alternative_or": {
            "status": "unsupported",
            "syntax": "<clause>|<clause>",
            "occurrences": 79,
            "examples": [
                "combat magic:#item_level-8.0|nature magic:#item_level-8.0",
                "combat magic:#item_level-2.0|nature magic:#item_level-2.0",
                "melee:#item_level-8.0|ranged:#item_level-8.0",
                "combat magic:7.0|nature magic:7.0"
            ],
            "runtime_consumer": None,
            "notes": "Disjunctive requirement where player needs either condition A OR condition B. Currently fails equip check."
        },
        "conjunction_and": {
            "status": "unsupported",
            "syntax": "<clause>,<clause>[,<clause>]",
            "occurrences": 117,
            "examples": [
                "melee:#item_level - 2.0,overbear:1",
                "ranged:#item_level - 8.0,biting_arrow:1",
                "combat magic:#item_level-16.0, melee:25",
                "wpn_a1_elt_crafted_1: melee:#item_level - 12.0, nature magic:25, aegis:8"
            ],
            "runtime_consumer": None,
            "notes": "Conjunctive requirement where player must satisfy all conditions simultaneously."
        },
        "passive_rank": {
            "status": "unsupported",
            "syntax": "<passive_name>:<rank>",
            "occurrences": 115,
            "examples": [
                "overbear:1", "aegis:1", "aegis:8", "biting_arrow:1",
                "quick_draw:1", "amplified_lightning:8", "grim_necromancy:8",
                "searing_flames:8", "summon_might:6", "dual_wield:4"
            ],
            "runtime_consumer": None,
            "notes": "Requires specific allocated rank in passive skill tree. Curse currently lacks player passive skill tree state query on equipment."
        },
        "character_level_uber": {
            "status": "unsupported",
            "syntax": "uber:#item_level[-<offset>]",
            "occurrences": 109,
            "examples": [
                "uber:#item_level", "uber:#item_level - 2.0", "uber:#item_level - 8.0", "uber:#item_level-8"
            ],
            "runtime_consumer": None,
            "notes": "Total hero character level (uber level) requirement. Curse uses discipline skills rather than unified uber character level."
        },
        "attribute_threshold": {
            "status": "unsupported",
            "syntax": "<attribute>:<threshold>",
            "occurrences": 1,
            "examples": ["intelligence:99"],
            "runtime_consumer": None,
            "notes": "Raw attribute requirement on quest_staff_a1_tower ('intelligence:99')."
        }
    }

    # Explicit Exclusions (Curse Architectural & Scope Decisions)
    explicit_exclusions = {
        "equipment_durability": {
            "status": "excluded",
            "rationale": "Curse design explicitly avoids equipment degradation and repair chore loops; gear does not lose durability.",
            "source_equivalent": "Not used in core DS2 combat gear; confirmed excluded from Curse."
        },
        "separate_consumable_ammo": {
            "status": "excluded",
            "rationale": "Curse bows and crossbows fire unlimited basic ammunition; quivers/arrows are not separate inventory equip slots.",
            "source_equivalent": "DS2 bows have built-in arrows and reload delays without separate inventory arrow items."
        },
        "tetris_inventory_rotation": {
            "status": "excluded",
            "rationale": "Curse jewelry and charms occupy standardized slot tiles; arbitrary multi-cell rotational Tetris is excluded.",
            "source_equivalent": "DS2 grid inventory sizing."
        },
        "spellbook_spell_slots": {
            "status": "excluded",
            "rationale": "Curse implements active abilities via dedicated action bar skill slots; equip-slot spellbooks with nested spell pages are not implemented.",
            "source_equivalent": "DS2 es_spellbook equipped book holding active spells."
        }
    }

    # Summary counts
    status_counts = {"supported": 0, "unsupported": 0, "unresolved": 0, "cosmetic_only": 0, "excluded": 0}
    for alt in alterations.values():
        status_counts[alt["status"]] += 1

    return {
        "manifest_version": "1.0.0",
        "baseline_commit": "0b99fa28513a5dff8def6731f67e21a7c246a25c",
        "source_archive": catalog.get("source_archive", "Logic.ds2res"),
        "summary": {
            "total_catalog_items": len(items),
            "total_source_affixes": len(affixes),
            "total_set_definitions": len(sets),
            "total_distinct_alterations": len(alterations),
            "alterations_by_status": status_counts,
            "template_properties_count": len(template_properties),
            "requirement_patterns_count": len(requirement_patterns),
            "explicit_exclusions_count": len(explicit_exclusions)
        },
        "alterations": alterations,
        "template_properties": template_properties,
        "requirement_patterns": requirement_patterns,
        "explicit_exclusions": explicit_exclusions
    }


def main():
    if not os.path.exists(CATALOG_PATH):
        print(f"Error: Catalog file not found at {CATALOG_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        catalog = json.load(f)

    manifest = build_manifest_data(catalog)

    os.makedirs(os.path.dirname(MANIFEST_PATH), exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    print(f"Successfully generated {MANIFEST_PATH}")
    print(f"Distinct alterations: {len(manifest['alterations'])}")
    for status, count in manifest['summary']['alterations_by_status'].items():
        print(f"  {status}: {count}")


if __name__ == "__main__":
    main()
