# Defensive resistance implementation

## Source and approved model

The reference catalog was extracted from the installed DS2 `Logic.ds2res`; examples include Traveler's Robe (`alter_physical_resistance`, +3% Melee and Ranged Resistance), Oakcase Carved Tunic (+6% Melee Resistance), Forest Shroud (+10% Ranged Resistance), and Hero's Amulet (+4% Magic Damage Resistance). The combat notes list armor as a separate ratio, distinguish physical/melee/ranged/magical/elemental resistances, record the 80% hero cap, and place final typed resistance after armor and level-gap mitigation.

The traced material does not establish how broad and attack-specific resistances overlap. The owner approved this additive overlap model for Curse; it is a Curse-specific design choice, not verified original DS2 engine behavior:

- Melee physical effective resistance = physical + melee.
- Ranged physical effective resistance = physical + ranged.
- Typed elemental magic effective resistance = magical + matching elemental resistance.
- Untyped magic uses magical resistance.
- Equipment and set modifiers sum in `PlayerStats.gear_totals()`; the effective sum is clamped once to the existing hero cap of 80%.
- Each effective physical/magical/elemental stage preserves the existing -100% vulnerability floor. Monsters use the existing 200% elemental cap per stage; that enemy cap remains a Curse choice, since the source notes establish that monsters may exceed 100% but do not trace their maximum.

## Damage order and interactions

`Combat.resolve()` keeps dodge and shield block first, physical-only Toughness, criticals, armor, level gap, and the existing minimum damage floor in their existing order. Broad resistance is applied after those stages. It does not modify armor, block chance, or dodge chance.

For each elemental bonus attached to a melee/ranged weapon, the matching elemental resistance reduces that bonus component before it joins the weapon hit (the existing behavior). After the combined hit passes armor and level-gap mitigation, the effective melee/ranged resistance reduces the total once. This intentionally allows sequential component and attack-type reductions; each distinct stage uses its own capped resistance value. A directly typed fire/ice/lightning/death magic hit instead sums magical and matching elemental resistance, then applies that one effective capped value once. The existing elemental bonus is never reduced again at the final stage.

## Equipment, saves, and playable samples

The four stats are aggregated from equipped affixes, uniques, and set bonuses, converted to actor fractions in `PlayerStats.refresh()`, and recalculated on equip, replacement, load, and removal. The Item Lab readout shows physical, effective melee/ranged, general magical, and typed magical values without changing its panel layout.

Source catalog unique templates included for gameplay:

- Traveler's Robe, level 16: +3% physical (Melee and Ranged) resistance, +14% ice resistance, +25 life, +35 mana; source Combat Magic requirement.
- Oakcase Carved Tunic, level 26: +6% melee resistance, +16% death resistance, +13 armor, +50 life; source Ranged requirement.
- Forest Shroud, level 13: +10% ranged resistance, +12% ranged dodge, +12% lightning resistance, +3 Intelligence; source Nature Magic requirement.
- Hero's Amulet, level 5: +4% magical resistance.

The source-supported stats, item levels, and requirement expressions are retained. These templates reuse the closest available Curse item meshes and icons; their visuals are not DS2 source assets. The armor class and armor scaling follow the new source base definitions.

Affix tiers are derived from the extracted catalog by `tools/extract_ds2_affixes.py`, stored in `data/reference/ds2_affixes.json`, and written as runtime resources by `tools/write_affix_defs.py`. The coverage manifest generator classifies the four alterations as supported only when consumer and active-test paths are present.

## Verification

`game/dev/suites/defensive_resistance_tests.gd:_test_defensive_resistances()` exercises physical-versus-elemental/magical classification, melee/ranged selection, armor, elemental weapon bonuses, multiple gear sources, caps, replacement/removal, dodge/block, item and character save/load, and real `Combat.resolve()` → `Actor.receive()` health changes. `equipmentintegration` verifies the live Item Lab readout. Run with `--only=defensiveresistances` and `--only=equipmentintegration`.
