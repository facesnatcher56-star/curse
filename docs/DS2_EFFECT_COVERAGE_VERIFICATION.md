# Dungeon Siege II Equipment Effect Coverage Verification

## 1. Executive Summary & Objective

This document reports the deterministic source-to-runtime mapping of original Dungeon Siege II equipment effects, item templates, and requirement expressions into the Curse engine.

**Baseline Commit:** `0b99fa28513a5dff8def6731f67e21a7c246a25c` (`origin/main`)  
**Audit Reference:** `docs/DS2_ITEM_MECHANICS_GAP_AUDIT.md` (`origin/codex/ds2-item-mechanics-gap-audit`)  
**Primary Source Catalog:** `data/reference/ds2_equipment_catalog.json` (extracted from original DS2 `Logic.ds2res`)  
**Affix Source Table:** `data/reference/ds2_affixes.json`  

The objective of this verification is to establish a strict, zero-omission boundary:
- Identify every original DS2 equipment alteration identifier and determine its live implementation state in Curse.
- Prevent silent truncation or silent discarding of modifiers during item generation, equipment equip, and combat resolution.
- Prohibit guessing unsupported or proprietary engine formulas.

---

## 2. Catalog & Source Entity Inventory

The reference dataset extracted from `Logic.ds2res` comprises:

| Dataset Entity | Source Count | Notes |
| :--- | :--- | :--- |
| **Equipment Templates** | **768** | 226 Normal, 239 Crafted, 197 Unique, 105 Set, 1 Rare |
| **Source Affix Rows** | **304** | 195 Prefixes, 109 Suffixes |
| **Set Definitions** | **27** | 26 Item Sets (105 set pieces total) + 1 Mysterious Set (3 token tiers) |
| **Distinct Alterations** | **58** | Unique effect identifiers across items, affixes, and set totals |
| **Template Fields** | **24** | 17 top-level item definition fields + 7 weapon attack fields |
| **Distinct Requirement Strings** | **60** | 7 syntactic classes spanning 724 required items and 44 zero-req items |

---

## 3. Coverage Classification Breakdown

Every property is deterministically classified into one of five mutually exclusive states:
1. **`supported`**: Has an active runtime consumer and dedicated automated test coverage in Curse.
2. **`unsupported`**: Original DS2 mechanic identified from source data, but currently lacks runtime pipeline/consumer in Curse.
3. **`unresolved`**: Original source behavior is ambiguous or depends on proprietary Skrit scripting untraced in the catalog.
4. **`cosmetic_only`**: Visual/provenance property supported by source evidence without gameplay stat implications.
5. **`excluded`**: Explicitly excluded by an approved Curse design decision.

### 3.1 Alteration Identifiers Summary (58 Total)

| Status | Count | Percentage |
| :--- | :--- | :--- |
| **Supported** | **28** | 48.3% |
| **Unsupported** | **29** | 50.0% |
| **Unresolved** | **1** | 1.7% |
| **Cosmetic Only** | **0** | 0.0% |
| **Excluded** | **0** | 0.0% |
| **Total** | **58** | **100.0%** |

---

## 4. Detailed Alteration Mapping

### 4.1 Supported Alterations (28)

| Alteration Identifier | Category | Units | Runtime Key | Runtime Consumer | Automated Test |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `alter_strength` | Attribute | Flat Integer | `str` | `PlayerStats.refresh()` | `tests/test_stats.gd` |
| `alter_dexterity` | Attribute | Flat Integer | `dex` | `PlayerStats.refresh()` | `tests/test_stats.gd` |
| `alter_intelligence` | Attribute | Flat Integer | `int` | `PlayerStats.refresh()` | `tests/test_stats.gd` |
| `alter_max_life` | Vital | Flat Integer | `life` | `PlayerStats.refresh()` | `tests/test_stats.gd` |
| `alter_max_mana` | Vital | Flat Integer | `mana` | `PlayerStats.refresh()` | `tests/test_stats.gd` |
| `alter_melee_damage_min` | Weapon Damage | Flat Integer | `melee_min` | `PlayerStats.weapon_range()` | `tests/test_equipment_hits.gd` |
| `alter_melee_damage_max` | Weapon Damage | Flat Integer | `melee_max` | `PlayerStats.weapon_range()` | `tests/test_equipment_hits.gd` |
| `alter_ranged_damage_min` | Weapon Damage | Flat Integer | `ranged_min` | `PlayerStats.ranged_range()` | `tests/test_equipment_hits.gd` |
| `alter_ranged_damage_max` | Weapon Damage | Flat Integer | `ranged_max` | `PlayerStats.ranged_range()` | `tests/test_equipment_hits.gd` |
| `alter_custom_damage_fire` | Elemental Damage | Range | `fire_added, fire_added_max` | `Combat.resolve()` | `tests/test_equipment_hits.gd` |
| `alter_melee_damage_source_percent` | Multiplier | Fraction | `melee_pct` | `PlayerStats.weapon_range()` | `tests/test_equipment_hits.gd` |
| `alter_ranged_damage_source_percent` | Multiplier | Fraction | `ranged_pct` | `PlayerStats.ranged_range()` | `tests/test_equipment_hits.gd` |
| `alter_cmagic_damage_percent` | Multiplier | Fraction | `spell_pct` | `abilities/fireball.gd` | `tests/test_stats.gd` |
| `alter_armor` | Defense | Flat Integer | `armor` | `PlayerStats.total_armor()` | `tests/test_stats.gd` |
| `alter_armor_source_percent` | Defense | Fraction | `armor_pct` | `PlayerStats.total_armor()` | `tests/test_stats.gd` |
| `alter_fire_resistance` | Resistance | Fraction | `fire_resist` | `Combat.resolve()` | `tests/test_stats.gd` |
| `alter_chance_to_block_melee_damage` | Shield Block | Fraction | `block` | `Combat.resolve()` | `tests/test_equipment_hits.gd` |
| `alter_chance_to_block_ranged_damage` | Shield Block | Fraction | `block_ranged` | `Combat.resolve()` | `tests/test_equipment_hits.gd` |
| `alter_life_steal` | Sustain (Hit) | Fraction | `life_steal` | `Player._steal_resources()` | `tests/test_equipment_hits.gd` |
| `alter_mana_steal` | Sustain (Hit) | Fraction | `mana_steal` | `Player._steal_resources()` | `tests/test_equipment_hits.gd` |
| `alter_life_bonus` | Sustain (Flat) | Flat Integer | `life_on_hit` | `Player._steal_resources()` | `tests/test_equipment_hits.gd` |
| `alter_mana_bonus` | Sustain (Flat) | Flat Integer | `mana_on_hit` | `Player._steal_resources()` | `tests/test_equipment_hits.gd` |
| `alter_life_recovery_unit` | Sustain (Regen) | Fraction | `life_regen` | `Player._process_regen()` | `tests/test_stats.gd` |
| `alter_mana_recovery_unit` | Sustain (Regen) | Fraction | `mana_regen` | `Player._process_regen()` | `tests/test_stats.gd` |
| `alter_reflect_damage` | Retaliation | Fraction | `reflect` | `Player._on_received_hit()` | `tests/test_equipment_hits.gd` |
| `alter_magic_find_chance` | Utility | Percentage | `magic_find` | `game/loot.gd` | `tests/test_find_rates.gd` |
| `alter_gold_dropped` | Utility | Percentage | `gold_find` | `game/loot.gd` | `tests/test_find_rates.gd` |
| `alter_power_reload` | Utility | Fraction | `recharge` | `PlayerStats.refresh()` | `tests/test_stats.gd` |

### 4.2 Unsupported Alterations (29)

| Alteration Identifier | Category | Target Pipeline | Required Runtime Implementation |
| :--- | :--- | :--- | :--- |
| `alter_custom_damage_ice` | Elemental Damage | Combat damage | Add ice damage calculation & cold status effect. |
| `alter_custom_damage_lightning` | Elemental Damage | Combat damage | Add lightning damage calculation to Combat pipeline. |
| `alter_custom_damage_death` | Elemental Damage | Combat damage | Add death/curse damage calculation to Combat pipeline. |
| `alter_ice_resistance` | Resistance | PlayerStats / Combat | Add independent ice resistance and damage mitigation. |
| `alter_lightning_resistance` | Resistance | PlayerStats / Combat | Add independent lightning resistance and mitigation. |
| `alter_death_resistance` | Resistance | PlayerStats / Combat | Add independent death resistance and mitigation. |
| `alter_magical_resistance` | Resistance | PlayerStats / Combat | General spell mitigation pipeline. |
| `alter_physical_resistance` | Resistance | PlayerStats / Combat | Flat percentage physical mitigation separate from armor formula. |
| `alter_melee_resistance` | Resistance | PlayerStats / Combat | Attack-type melee physical mitigation. |
| `alter_ranged_resistance` | Resistance | PlayerStats / Combat | Attack-type ranged physical mitigation. |
| `alter_block_combat_magic_damage` | Defense | Combat | Spell damage reduction / block on staves and shields. |
| `alter_chance_to_dodge_hit` | Defense | Combat | Gear-derived general dodge calculation. |
| `alter_chance_to_dodge_hit_melee` | Defense | Combat | Gear-derived melee attack dodge calculation. |
| `alter_chance_to_dodge_hit_ranged` | Defense | Combat | Gear-derived ranged attack dodge calculation. |
| `ALTER_CHANCE_TO_DODGE_HIT_RANGED` | Defense | Combat | Uppercase variant of ranged dodge. |
| `alter_nmagic_damage_percent` | Multiplier | PlayerStats | Nature magic spell damage scaling (Curse only has Combat Magic). |
| `ALTER_POWER_DAMAGE_PERCENT` | Multiplier | Powers | Equipment bonus scaling activated powers. |
| `alter_combat_magic` | Skill Bonus | PlayerStats | Direct Combat Magic discipline level bonus. |
| `alter_nature_magic` | Skill Bonus | PlayerStats | Direct Nature Magic discipline level bonus. |
| `alter_melee_passive_skills` | Passive Bonus | Skill Tree | Bonus to all melee passive skill ranks. |
| `ALTER_MELEE_PASSIVE_SKILLS` | Passive Bonus | Skill Tree | Uppercase variant of melee passive skills bonus. |
| `ALTER_RANGED_PASSIVE_SKILLS` | Passive Bonus | Skill Tree | Bonus to all ranged passive skill ranks. |
| `ALTER_COMBAT_MAGIC_PASSIVE_SKILLS` | Passive Bonus | Skill Tree | Bonus to all combat magic passive skill ranks. |
| `ALTER_NATURE_MAGIC_PASSIVE_SKILLS` | Passive Bonus | Skill Tree | Bonus to all nature magic passive skill ranks. |
| `alter_skill_suite` | Suite Bonus | Skill Tree | 14 distinct triplets/pairs of passive skills. |
| `ALTER_FREEZE_CHANCE` | On-Hit Status | Combat | Chance to apply freeze status effect on hit. |
| `ALTER_DEBUFF_RESISTANCE` | Resistance | PlayerStats | Curse / debuff duration reduction. |
| `ALTER_EXPERIENCE_GAINED` | Utility | Progression | Multiplier on monster experience gained. |
| `ALTER_INTELLIGENCE` | Attribute | PlayerStats | Uppercase variant of intelligence (currently unmapped). |

### 4.3 Unresolved Alterations (1)

| Alteration Identifier | Category | Occurrences | Source Evidence & Rationale |
| :--- | :--- | :--- | :--- |
| `alter_generic` | Script Hook | 89 item records, 3 set tiers | References proprietary Dungeon Siege II Skrit scripting hooks (e.g. `ax_1h_ba_unq_01`, `ax_1h_ea_unq_01`, and `mysterious` set tier values). The actual skrit scripts, arguments, and combat logic are not present in the checked-in catalog JSON. **Marked unresolved; must not be guessed.** |

---

## 5. Equipment Template & Weapon Fields Coverage (24 Total)

All 17 top-level template properties and 7 weapon attack fields are classified:

| Property | Status | Target Consumer | Purpose |
| :--- | :--- | :--- | :--- |
| `id` | `supported` | `ItemDB`, `ItemDef` | Unique item identifier string. |
| `source` | `cosmetic_only` | Provenance metadata | Original .gas file in `Logic.ds2res`. |
| `name` | `supported` | `ItemDef` | Base item display name. |
| `base_name` | `supported` | `ItemDef` | Base item noun for synthesized affix names. |
| `category` | `supported` | `ItemDef` | Rarity classification (`normal`, `crafted`, `unique`, `set`, `rare`). |
| `parent` | `supported` | `ItemDB` | Template inheritance root family. |
| `pcontent_allowed` | `supported` | `Loot` | Procedural loot spawning eligibility. |
| `allow_modifiers` | `supported` | `AffixDB` | Eligibility to receive magic prefixes and suffixes. |
| `variants` | `supported` | `ItemDB` | Leveled variant definitions (level requirement & texture). |
| `requirements` | `supported` | `items.gd:can_equip()` | Discipline level requirement expression. |
| `slot` | `supported` | `Equipment` | Target equip slot (`es_weapon_hand`, `es_shield_hand`, etc.). |
| `class` | `supported` | `ItemDef` | Class restriction (`IST_FIGHTER`, `IST_RANGER`, etc.). |
| `set` | `unsupported` | Missing set tracker | Set association string (Curse lacks set bonus logic). |
| `icon_reference` | `cosmetic_only` | Asset pipeline | Original bitmap texture reference. |
| `attack` | `supported` | `PlayerStats` | Weapon attack stats container. |
| `armor` | `supported` | `PlayerStats` | Base armor value formula. |
| `effects` | `supported` | `ItemDef` | Inherent modifier array. |
| `attack.damage_min` | `supported` | `PlayerStats` | Base minimum damage formula. |
| `attack.damage_max` | `supported` | `PlayerStats` | Base maximum damage formula. |
| `attack.is_melee` | `supported` | `Combat` | Combat style flag (`melee` vs `ranged`). |
| `attack.is_two_handed` | `supported` | `Equipment` | Two-handed grip flag (disables off-hand shield). |
| `attack.reload_delay` | `supported` | `Player` | Weapon recovery cooldown in seconds (0.0 to 1.0s). |
| `attack.skill_class` | `supported` | `Combat` | Skill discipline governing weapon (`melee`, `ranged`). |
| `attack.attack_range` | `supported` | `Combat` | Ranged targeting distance in meters (7.5m to 11.0m). |

---

## 6. Requirement Syntax & Evaluator Gap Specification

Analysis of the 60 distinct raw requirement strings across the 768 items reveals 7 distinct syntactic patterns:

| Pattern Class | Status | Items | Example Syntax | Runtime Implementation Gap |
| :--- | :--- | :--- | :--- | :--- |
| `discipline_offset` | `supported` | 346 | `melee:#item_level - 2.0` | Evaluated in `items.gd:can_equip()`. |
| `discipline_fixed` | `supported` | 2 | `melee:0` | Evaluated in `items.gd:can_equip()`. |
| `alternative_or` | `unsupported` | 79 | `combat magic:#item_level-8.0\|nature magic:#item_level-8.0` | Requires parsing `\|` delimiter; passes if player satisfies either condition. Currently fails validation. |
| `conjunction_and` | `unsupported` | 117 | `melee:#item_level - 2.0,overbear:1` | Requires parsing `,` delimiter; passes only if player satisfies all conditions. |
| `passive_rank` | `unsupported` | 115 | `overbear:1`, `aegis:8`, `biting_arrow:1` | Requires equipment evaluator to query allocated ranks in passive skill tree. |
| `character_level_uber` | `unsupported` | 109 | `uber:#item_level - 8.0` | Total character level requirement (Curse tracks discipline levels, not unified uber level). |
| `attribute_threshold` | `unsupported` | 1 | `intelligence:99` | Stat threshold requirement on `quest_staff_a1_tower`. |

---

## 7. Explicit Curse Design Exclusions

The following original Dungeon Siege II systems are explicitly excluded from Curse by architectural decisions:

1. **Equipment Durability & Repair Loops:** Equipment does not degrade or require gold sinks to repair.
2. **Consumable Ammo Items & Quivers:** Bows and crossbows fire basic projectiles without separate inventory ammo items.
3. **Tetris Inventory Rotation:** Standardized 1x1 inventory cells are used for jewelry rather than arbitrary rotational grids.
4. **Spellbook Equip-Slot Spell Pages:** Active abilities are bound directly to the action bar rather than equipped spellbook sub-containers.

---

## 8. Automated Tooling & Test Verification

Two automated tools and a dedicated unit test suite enforce manifest integrity:

1. **`tools/generate_ds2_effect_manifest.py`**:
   - Deterministically generates `data/reference/ds2_effect_coverage_manifest.json`.
   - Ensures exact parity with `data/reference/ds2_equipment_catalog.json`.

2. **`tools/check_ds2_effect_coverage.py`**:
   - Validates that 100% of alterations, template properties, attack sub-fields, and requirement syntax patterns are explicitly covered.
   - Asserts that supported entries have non-empty consumers and tests.
   - Fails with non-zero exit code on any unmapped property or silent omission.

3. **`tools/test_ds2_effect_coverage.py`**:
   - 9 automated unit tests verifying catalog counts, deterministic generation, strict classification, and deliberate failure detection when properties are omitted.
   - Run results: `Ran 9 tests in 0.112s - OK`.

---

## 9. Next Highest-Priority Implementation Gap

Based on this coverage analysis, the next highest-priority implementation gap is:

> **Compound Requirement Parsing (`|` and `,`) and Passive Skill Tree Equip Checks**

### Justification:
- **Scope Impact:** Affects **196 items** (79 with OR alternatives, 117 with AND conjunctions, 115 requiring passive skill ranks).
- Currently, attempting to import or equip these items fails equip validation or bypasses checks entirely.
- Implementing an evaluator supporting `|`, `,`, and passive rank queries will instantly unlock equip compatibility for over 25% of the original DS2 catalog without risking gameplay regressions.
