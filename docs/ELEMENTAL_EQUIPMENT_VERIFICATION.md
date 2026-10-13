# Elemental equipment: ice, lightning and death

Six DS2 alterations now act in combat, through the one existing pipeline (`Combat.resolve`):

| Alteration | Curse stat | Actor field |
| --- | --- | --- |
| `alter_custom_damage_ice` | `ice_added` / `ice_added_max` | `added_ice`, `added_ice_max` |
| `alter_custom_damage_lightning` | `lightning_added` / `lightning_added_max` | `added_lightning`, `added_lightning_max` |
| `alter_custom_damage_death` | `death_added` / `death_added_max` | `added_death`, `added_death_max` |
| `alter_ice_resistance` | `ice_resist` (percent) | `ice_resist` |
| `alter_lightning_resistance` | `lightning_resist` (percent) | `lightning_resist` |
| `alter_death_resistance` | `death_resist` (percent) | `death_resist` |

Fire (`fire_added`, `fire_resist`) is unchanged in behaviour and now runs through the same generalised code.

## Source evidence

`data/reference/ds2_equipment_catalog.json` (`affixes` list, from `pcontent.gas`) carries the tiers. `tools/import_ds2_element_affixes.py`
copies them into `data/reference/ds2_affixes.json` (12 tiers per damage family: 6 melee / `fighter`, 6 ranged / `ranger`; 5 tiers per
resistance family on armour, rings and amulets) and `tools/write_affix_defs.py` writes the 45 new `AffixDef` tiers (e.g. Arctic: melee ice
13-22 at modifier level 49; Azure: 10% ice resistance at level 6; Necromantic: melee death 35-58 at level 85). Resistances are fractions in the
source and percentage points in Curse, like `fire_resist`. Spellbook slots are dropped (no Curse slot). The catalog's unique/crafted items use the
same alterations (including death resistance of -25% and -30%), but those items are not imported at runtime yet (`runtime_imported: false`).

## Calculation

*Added damage.* For a weapon hit (`PHYSICAL` or `RANGED`, same condition as added fire before) each element with added damage rolls
`uniform(min, max)` independently, multiplies it by `1 - resistance` of the **same** element, floors it at 0, and adds it to the blow
before the critical, armour and level-gap steps (DS2 `CalculateDamage$` step 4). Power and spell hits (`FIRE`, `ICE`, `LIGHTNING`, `DEATH`
typed) never receive added damage. The result keeps the per-element amounts in `result["added_elements"]` (after resistance, before
crit/armour/level gap) so each element stays identifiable; `result["damage"]` is the single combined number as before.

*Resistance.* `Combat.element_multiplier(defender, element) = 1 - clamp(resist, -100%, cap)`; cap 80% for the hero and companions (DS2
`max_resistance`), 200% for monsters (above 100% a hit heals, as in DS2). Typed `ICE`/`LIGHTNING`/`DEATH` damage is scaled by the matching
multiplier at the end, as `FIRE` always was. Negative resistance amplifies (-30% death = x1.3). Resistances sum across equipment
(`gear_totals`); a resistance never applies to another element. Armour, block and dodge are untouched.

*Stacking.* Minimums and maximums of every equipped source sum (`gear_totals`), including the uniform roll of the summed range.

## Not established / not done

- DS2's exact monster resistance ceiling and healing curve above 100% are not in the traced data; the 200% bound is the existing Curse choice.
- DS2's Survival passive also grants ice and lightning resistance (identical table to fire). It is a passive, not equipment, so
  `PlayerStats.refresh` still applies it to fire only. Wiring it is a one-line follow-up; I left it out to keep this change to equipment.
- No status effects (freeze, slow, shock) or elemental spell content were added; no HUD stat line shows the new resistances (item cards and
  comparisons do). The Character window's gear line still only lists fire resistance.
- Enemy definitions carry no elemental resistance data yet; the fields exist on `Actor` and are honoured by `Combat`.
- Catalog uniques/crafted items with these alterations are not imported.

## Tests

`--selftest --only=elements` (`game/dev/suites/element_tests.gd`) covers: source tier values and class/slot gating; aggregation per element
and the card text; unequipping; range rolling (300 rolls per element) and single counting; per-element isolation; matching / unrelated /
zero / boundary resistances on a monster (-30%, -100%, clamp, 100%, 80%, 200% cap); armour, critical and typed damage; ranged weapon hits;
spell exclusion; stacking across a weapon and a ring; mixed fire+ice+lightning+death blows; fire compatibility; hero resistance from rings and
amulets, hero cap/floor, `Actor.receive`; a negative source value through the real equipment path; item and character save/load; and loot
discipline (sword vs bow vs armour).
