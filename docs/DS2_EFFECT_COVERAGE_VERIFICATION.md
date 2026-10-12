# Dungeon Siege II Equipment Effect Coverage Verification

## 1. Executive Summary & Objective

This document reports the verified source-to-runtime mapping of original Dungeon Siege II equipment effects, item templates, and requirement expressions into the Curse engine.

**Baseline Commit:** `0b99fa28513a5dff8def6731f67e21a7c246a25c` (`origin/main`)  
**Audit Reference:** `docs/DS2_ITEM_MECHANICS_GAP_AUDIT.md` (`origin/codex/ds2-item-mechanics-gap-audit`)  
**Primary Source Catalog:** `data/reference/ds2_equipment_catalog.json` (extracted from original DS2 `Logic.ds2res`)  
**Affix Source Table:** `data/reference/ds2_affixes.json`  
**Manifest Artifact:** `data/reference/ds2_effect_coverage_manifest.json`  

The objective of this verification is to establish a strict, zero-omission boundary:
- Identify every original DS2 equipment alteration identifier and determine its live implementation state in Curse.
- Rigorously distinguish between **verified supported mechanics** (demonstrated by active test cases in `game/dev/suites/*.gd`), **implemented but untested mechanics** (present in runtime consumers but unexercised by test suites), **unsupported mechanics** (requiring engine implementation), and **unresolved mechanics** (proprietary Skrit hooks).
- Ensure all referenced consumer files, test suite files, and function symbols exist on disk, verified by automated tooling.
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

Every property is deterministically classified into one of six mutually exclusive states:
1. **`supported`**: Has a verified runtime consumer AND active automated test suite coverage on disk.
2. **`untested`**: Implemented in engine runtime pipelines, but lacks dedicated automated test suite coverage exercising it as an equipment effect.
3. **`unsupported`**: Original DS2 mechanic identified from source data, but currently lacks a runtime consumer pipeline in Curse.
4. **`unresolved`**: Original source behavior is ambiguous or depends on proprietary Skrit scripting untraced in the catalog.
5. **`cosmetic_only`**: Visual/provenance property supported by source evidence without gameplay stat implications.
6. **`excluded`**: Explicitly excluded by an approved Curse design decision.

### 3.1 Alteration Identifiers Summary (58 Total)

| Status | Count | Percentage |
| :--- | :--- | :--- |
| **Supported** | **17** | 29.3% |
| **Untested** | **11** | 19.0% |
| **Unsupported** | **29** | 50.0% |
| **Unresolved** | **1** | 1.7% |
| **Cosmetic Only** | **0** | 0.0% |
| **Excluded** | **0** | 0.0% |
| **Total** | **58** | **100.0%** |

---

## 4. Detailed Alteration Mapping

### 4.1 Supported Alterations (17)

All 17 supported alterations have verified runtime consumers and verified test suite assertions in `game/dev/suites/*.gd`:

| Alteration Identifier | Category | Runtime Key | Runtime Consumer | Verified Test Suite & Function | Test Suite Verification Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `alter_strength` | Attribute | `str` | `game/player/player_stats.gd:refresh()` | `game/dev/suites/ds2_tests.gd:_test_ds2_items()` | Lines 322–325: Equips Signet ring with `strength_9` (+72 STR) and verifies attribute increase. |
| `alter_dexterity` | Attribute | `dex` | `game/player/player_stats.gd:refresh()` | `game/dev/suites/ds2_tests.gd:_test_ds2_items()` | Lines 326–328: Equips Band ring with `dexterity_1` and verifies dual ring slot allocation. |
| `alter_max_life` | Vital | `life` | `game/player/player_stats.gd:refresh()` | `game/dev/suites/ds2_tests.gd:_test_ds2_items()` | Lines 322–325: Equips Signet ring with `life_12` (+237 life) and verifies health increase. |
| `alter_ranged_damage_min` | Weapon Damage | `ranged_min` | `game/player/player_stats.gd:ranged_range()` | `game/dev/suites/ranged_modifier_tests.gd:_test_ranged_modifiers()` | Lines 72, 79: Equips Short Bow with `ranged_min_1` (+3 min) and verifies DS2 damage calculation. |
| `alter_ranged_damage_max` | Weapon Damage | `ranged_max` | `game/player/player_stats.gd:ranged_range()` | `game/dev/suites/ranged_modifier_tests.gd:_test_ranged_modifiers()` | Lines 73, 79: Equips Short Bow with `ranged_max_1` (+1 max) and verifies damage calculation. |
| `alter_ranged_damage_source_percent` | Multiplier | `ranged_pct` | `game/player/player_stats.gd:ranged_range()` | `game/dev/suites/ranged_modifier_tests.gd:_test_ranged_modifiers()` | Lines 74, 79: Equips Short Bow with `ranged_pct_1` (+10%) and verifies damage scaling. |
| `alter_armor` | Defense | `armor` | `game/player/player_stats.gd:total_armor()` | `game/dev/suites/ds2_tests.gd:_test_ds2_items()` | Lines 339–341: Equips Roadwarden set pieces and verifies +30 armor set bonus. |
| `alter_armor_source_percent` | Defense | `armor_pct` | `game/player/player_stats.gd:total_armor()` | `game/dev/suites/ds2_tests.gd:_test_ds2_items()` | Lines 335–337: Equips Mail Hauberk with `armor_pct_8` and verifies armor scaling. |
| `alter_chance_to_block_melee_damage` | Shield Block | `block` | `game/player/player_stats.gd:refresh()` | `game/dev/suites/ds2_tests.gd:_test_ds2_items()` | Lines 329–331: Equips Buckler with `block_4` and verifies `player.block_chance`. |
| `alter_chance_to_block_ranged_damage` | Shield Block | `block_ranged` | `game/player/player_stats.gd:refresh()` | `game/dev/suites/ranged_modifier_tests.gd:_test_ranged_modifiers()` | Lines 187–192: Verifies `ranged_block_chance` resolution in combat resolution. |
| `alter_life_steal` | Sustain (Hit) | `life_steal` | `game/player.gd:_steal_resources()` | `game/dev/suites/equipment_hit_tests.gd:_test_equipment_hits()` | Lines 44–48, 140–141: Equips Gravecutter (+5% steal) and tests resource stealing. |
| `alter_mana_steal` | Sustain (Hit) | `mana_steal` | `game/player.gd:_steal_resources()` | `game/dev/suites/equipment_hit_tests.gd:_test_equipment_hits()` | Lines 44–48: Tests mana steal percent on melee blows, clamped to maximum mana. |
| `alter_life_bonus` | Sustain (Flat) | `life_per_hit` | `game/player.gd:_steal_resources()` | `game/dev/suites/equipment_hit_tests.gd:_test_equipment_hits()` | Lines 44–48, 151–153: Equips `life_per_hit_1` rings and verifies flat healing on hit. |
| `alter_mana_bonus` | Sustain (Flat) | `mana_per_hit` | `game/player.gd:_steal_resources()` | `game/dev/suites/equipment_hit_tests.gd:_test_equipment_hits()` | Lines 44–48, 151–153: Equips `mana_per_hit_1` rings and verifies flat mana on hit. |
| `alter_reflect_damage` | Retaliation | `reflect` | `game/player.gd:_on_received_hit()` | `game/dev/suites/equipment_hit_tests.gd:_test_equipment_hits()` | Lines 95–124, 142–146: Equips Warden's Oath shield (+20% reflect) and verifies damage return. |
| `alter_magic_find_chance` | Utility | `magic_find` | `game/party_manager.gd:loot_bonuses()` | `game/dev/suites/find_tests.gd:_test_find()` | Lines 72–73, 80–99: Tests `hero.stats.gear` MF and party averaging across members. |
| `alter_gold_dropped` | Utility | `gold_find` | `game/party_manager.gd:loot_bonuses()` | `game/dev/suites/find_tests.gd:_test_find()` | Lines 70, 80–99: Tests `MonsterLoot.gold_amount()` scaling and party gold find averaging. |

---

### 4.2 Implemented but Untested Alterations (11)

These 11 alterations are implemented in engine consumers, but lack active automated test suite coverage exercising them as equipment modifiers. They are classified as `untested` to maintain strict verification integrity:

| Alteration Identifier | Category | Runtime Key | Runtime Consumer | Reason Classified as Untested |
| :--- | :--- | :--- | :--- | :--- |
| `alter_intelligence` | Attribute | `int` | `game/player/player_stats.gd:refresh()` | Implemented in `PlayerStats.refresh()`, but `ds2_tests.gd` only tests Fireball baseline INT scaling, not equipping an INT gear affix. |
| `alter_max_mana` | Vital | `mana` | `game/player/player_stats.gd:refresh()` | Implemented in `PlayerStats.refresh()`, but no dev suite test equips a flat mana item. |
| `alter_melee_damage_min` | Weapon Damage | `melee_min` | `game/player/player_stats.gd:weapon_base_range()` | Implemented in `PlayerStats.weapon_base_range()`, but dev suites only test ranged modifiers or base weapon curves. |
| `alter_melee_damage_max` | Weapon Damage | `melee_max` | `game/player/player_stats.gd:weapon_base_range()` | Implemented in `PlayerStats.weapon_base_range()`, but dev suites only test ranged modifiers or base weapon curves. |
| `alter_melee_damage_source_percent` | Multiplier | `melee_pct` | `game/player/player_stats.gd:weapon_range()` | Implemented in `PlayerStats.weapon_range()`, but no dev suite test equips a `melee_pct` item. |
| `alter_custom_damage_fire` | Elemental Damage | `fire_added, fire_added_max` | `game/player/player_stats.gd:refresh()`, `game/combat.gd:resolve()` | Implemented in `refresh()` and `Combat.resolve()`, but `ds2_tests.gd` tests via manual `player.added_fire` property override rather than equipping an affix. |
| `alter_cmagic_damage_percent` | Multiplier | `spell_pct` | `game/player/player_stats.gd:spell_range()` | Implemented in `PlayerStats.spell_range()`, but dev suite tests only test Devastation passive skill rank scaling. |
| `alter_fire_resistance` | Resistance | `fire_resist` | `game/player/player_stats.gd:refresh()`, `game/combat.gd:resolve()` | Implemented in `refresh()` and `Combat.resolve()`, but tests only verify manual `player.fire_resist` override and Survival passive rank 20. |
| `alter_life_recovery_unit` | Sustain (Regen) | `life_regen` | `game/player/player_stats.gd:regen()` | Implemented in `PlayerStats.regen()`, but no dev suite test exercises `gear_stat('life_regen')`. |
| `alter_mana_recovery_unit` | Sustain (Regen) | `mana_regen` | `game/player/player_stats.gd:regen()` | Implemented in `PlayerStats.regen()`, but no dev suite test exercises `gear_stat('mana_regen')`. |
| `alter_power_reload` | Utility | `recharge` | `game/player/player_stats.gd:power_recharge_damage()` | Implemented in `PlayerStats.power_recharge_damage()`, but dev suite tests only verify Renewal passive ranks. |

---

### 4.3 Unsupported Alterations (29)

These 29 source alterations currently have no runtime consumer pipeline in Curse:

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

---

### 4.4 Unresolved Alterations (1)

| Alteration Identifier | Category | Occurrences | Source Evidence & Rationale |
| :--- | :--- | :--- | :--- |
| `alter_generic` | Script Hook | 89 item records, 3 set tiers | References proprietary Dungeon Siege II Skrit scripting hooks (e.g. `ax_1h_ba_unq_01`, `ax_1h_ea_unq_01`, and `mysterious` set tier values). The actual skrit scripts, arguments, and combat logic are not present in the checked-in catalog JSON. **Marked unresolved; must not be guessed.** |

---

## 5. Equipment Template & Weapon Fields Coverage (24 Total)

All 17 top-level template properties and 7 weapon attack fields are classified with verified file consumers:

| Property | Status | Target Consumer | Purpose |
| :--- | :--- | :--- | :--- |
| `id` | `supported` | `game/data/item_db.gd, game/items.gd` | Unique item identifier string. |
| `source` | `cosmetic_only` | None | Original .gas file in `Logic.ds2res`. |
| `name` | `supported` | `game/items.gd` | Base item display name. |
| `base_name` | `supported` | `game/items.gd` | Base item noun for synthesized affix names. |
| `category` | `supported` | `game/items.gd` | Rarity classification (`normal`, `crafted`, `unique`, `set`, `rare`). |
| `parent` | `supported` | `game/data/item_db.gd` | Template inheritance root family. |
| `pcontent_allowed` | `unsupported` | None | Procedural loot spawning eligibility flag (not evaluated by Curse loot tables). |
| `allow_modifiers` | `unsupported` | None | Affix eligibility flag (not evaluated by Curse affix generator). |
| `variants` | `supported` | `game/data/item_db.gd, game/data/item_def.gd` | Leveled variant definitions parsed into `ItemDef.levels`. |
| `requirements` | `supported` | `game/items.gd:meets_requirement()` | Discipline level requirement expression. |
| `slot` | `supported` | `game/items.gd, game/player/player_stats.gd` | Target equip slot (`es_weapon_hand`, `es_shield_hand`, etc.). |
| `class` | `supported` | `game/items.gd` | Class restriction (`IST_FIGHTER`, `IST_RANGER`, etc.). |
| `set` | `unsupported` | None | Set association string (Curse lacks set bonus tracker). |
| `icon_reference` | `cosmetic_only` | None | Original bitmap texture reference. |
| `attack` | `supported` | `game/items.gd, game/player/player_stats.gd` | Weapon attack stats container. |
| `armor` | `supported` | `game/items.gd, game/player/player_stats.gd` | Base armor value formula. |
| `effects` | `supported` | `game/items.gd, game/player/player_stats.gd` | Inherent modifier array. |
| `attack.damage_min` | `supported` | `game/items.gd, game/player/player_stats.gd` | Base minimum damage formula. |
| `attack.damage_max` | `supported` | `game/items.gd, game/player/player_stats.gd` | Base maximum damage formula. |
| `attack.is_melee` | `supported` | `game/items.gd, game/combat.gd` | Combat style flag (`melee` vs `ranged`). |
| `attack.is_two_handed` | `supported` | `game/data/item_def.gd, game/player/player_stats.gd` | Two-handed grip flag (disables off-hand shield). |
| `attack.reload_delay` | `supported` | `game/player/player_stats.gd:attack_speed()` | Weapon attack delay and recovery period. |
| `attack.skill_class` | `supported` | `game/items.gd, game/player/player_stats.gd` | Skill discipline governing weapon (`melee`, `ranged`). |
| `attack.attack_range` | `supported` | `game/player.gd, game/combat.gd` | Ranged targeting distance in meters (7.5m to 11.0m). |

---

## 6. Requirement Syntax & Evaluator Gap Specification

Analysis of the 60 distinct raw requirement strings across the 768 items reveals 7 distinct syntactic patterns:

| Pattern Class | Status | Items | Example Syntax | Runtime Implementation Gap |
| :--- | :--- | :--- | :--- | :--- |
| `discipline_offset` | `supported` | 346 | `melee:#item_level - 2.0` | Evaluated in `game/items.gd:meets_requirement()`. |
| `discipline_fixed` | `supported` | 2 | `melee:0` | Evaluated in `game/items.gd:meets_requirement()`. |
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
   - Enforces that every referenced file exists on disk (`os.path.exists`).
   - Enforces that every referenced function symbol exists in the file text.
   - Enforces that `supported` entries have verified runtime consumers and verified test suite cases.
   - Enforces that `untested` entries have verified runtime consumers and strictly `null` test paths until demonstrated.
   - Enforces that `unsupported` and `unresolved` entries do not specify consumers or test paths.
   - Fails with non-zero exit code on any unmapped property, silent omission, fictitious file, or inconsistency.

3. **`tools/test_ds2_effect_coverage.py`**:
   - 12 automated unit tests verifying catalog counts, deterministic generation, strict classification, and deliberate failure detection when nonexistent files, symbols, or untested claims are introduced.
   - Run results: `Ran 12 tests in 0.295s - OK`.

---

## 9. Next Highest-Priority Implementation Gap

Based on this coverage analysis, the next highest-priority implementation gap is:

> **Compound Requirement Parsing (`|` and `,`) and Passive Skill Tree Equip Checks**

### Justification:
- **Scope Impact:** Affects **196 items** (79 with OR alternatives, 117 with AND conjunctions, 115 requiring passive skill ranks).
- Currently, attempting to import or equip these items fails equip validation or bypasses checks entirely.
- Implementing an evaluator supporting `|`, `,`, and passive rank queries will instantly unlock equip compatibility for over 25% of the original DS2 catalog without risking gameplay regressions.
