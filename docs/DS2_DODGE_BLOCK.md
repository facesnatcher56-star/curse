# DS2 dodge and block from equipment

## Source evidence (docs/ds2-combat-and-loot.md section 2, `rules.skrit` `CalcCanHit$`; data/reference/ds2_equipment_catalog.json)

- **Dodge:** "Ranger skill Dodge (4% at L1 to 40% at L20, melee and ranged) plus any `chance_to_dodge_hit` gear." There is no accuracy roll.
  Three source alterations exist: `alter_chance_to_dodge_hit` (melee and ranged), `alter_chance_to_dodge_hit_melee`, `alter_chance_to_dodge_hit_ranged`.
  Values are fractions in the catalogue (`0.06` = 6%). They occur on 28 fixed catalogue items and two sets (Night's Shadow, Plainswalker's Journey),
  never on random affixes.
- **Block:** shield required; `shield block % + Barricade bonus`, separately for melee and ranged; a blocked hit deals nothing. Already implemented
  before this change (`alter_chance_to_block_melee_damage`, `alter_chance_to_block_ranged_damage`, shield gate in `PlayerStats.refresh`).

## Implemented

| Stat (gear) | Source alteration | Effect on the hero |
| :--- | :--- | :--- |
| `dodge` | `alter_chance_to_dodge_hit` | adds to melee and ranged dodge |
| `dodge_melee` | `alter_chance_to_dodge_hit_melee` | adds to melee dodge only |
| `dodge_ranged` | `alter_chance_to_dodge_hit_ranged` | adds to ranged dodge only |

```
melee dodge  = Dodge skill + dodge + dodge_melee      (percent, divided by 100)
ranged dodge = Dodge skill + dodge + dodge_ranged
blow of kind K is dodged when randf() < clamp(dodge for K, 0, 1)     (Combat.dodge_chance_against)
```

`Combat.resolve` rolls dodge first (outcome `MISS`, shown as "Dodge"), then, for physical and ranged blows, block (outcome `BLOCK`, "Block"), which is
the order the DS2 notes give (can it connect, then step 4). Spells and powers (`can_miss` false) are never dodged, as before. A blow of type RANGED
meets the ranged chance; every other kind meets the melee one. Monsters keep their single `dodge_chance` for all blows (`Actor.ranged_dodge_chance`
is -1 unless set).

Live items (exact DS2 values on exact DS2 bases, every other alteration already supported): **Dusk** (Leather Jerkin, level 16: armour 8, lightning
and death resistance 13%, melee dodge 6%, magic find 18) and **Grace of Night** (Leather Boots, level 8: life 12, armour 4, ice resistance 12%,
ranged dodge 8%). They are hand-authored uniques like the existing ones (`tools/write_unique_defs.py`) and can drop.

## Assumptions and limits

- DS2's cap on dodge or block is not in the traced data, so none is invented; a chance is only held to 0-100% as a probability.
- Dodge and block add (percent points), as the Dodge skill and Barricade do; DS2's stacking of several gear sources is taken as additive, the same as
  every other additive gear stat in the manifest.
- Block keeps requiring a shield (gear block on a ring does nothing without one), per the DS2 note and the existing code.
- General `dodge` has no live Curse item (the two catalogue items that carry it, Panther's Paw and Restless Gaze, are on bases or with alterations
  Curse lacks); it is tested with a test-only unique.
- The other 26 catalogue items and the two sets with dodge are not imported; set-bonus dodge is not wired.
- `ALTER_CHANCE_TO_DODGE_HIT_RANGED` (upper case, a separate source identifier) stays unsupported until its case handling is verified.
- `alter_block_combat_magic_damage` (spell damage reduction on one quest staff) is a different mechanic and stays unsupported.
- The Item Test Lab log now says DODGE for a dodge (was MISS), and its readout shows melee and ranged dodge.

Tests: `--only=dodgeblock` (`game/dev/suites/dodge_block_tests.gd`), mutation-checked: removing the ranged aggregation and the lookup fails 9 checks.
