# DS2 equipment power damage (`ALTER_POWER_DAMAGE_PERCENT`)

## Source evidence

- **Formula** (`rules.skrit`, `DamageGoPower$`, the one entry point for every power's damage): `damagevar *= 1.0 + Attacker.Attack.GetPowerDamageBonusPercent()`,
  before the damage is dispatched by class: melee and ranged powers pass a damage *percentage* to `DamageGoMeleeMultiplier$` / `DamageGoRangedMultiplier$`
  (so the bonus scales the power's own multiplier), `magic` and `special` pass pre-calculated damage. Ordinary attacks do not go through it.
- **Unit:** the catalogue writes `0.03` and describes it "+3% Power Damage", so the value is a fraction (+3%).
- **Carriers:** the alteration is on 16 catalogue items: armour, amulets, a ring and talismans (levels 40 to 95). None is a weapon, and none is a random affix.
  Values 2% to 6% (one Talisman is 50%).
- The engine function that sums `GetPowerDamageBonusPercent()` is C++ and not in the extracted data, so the stacking rule is an assumption (below).
- DS2's magic *powers* separately carry `(1 + #increased_magic_power_damage_percentage)` from the Arcane Fury passive (already in Curse's fire powers);
  that is a different source and multiplies with this one.

## Implemented

```
power_damage_mult = max(1 + (sum of worn power_damage %) / 100, 0)        PlayerStats.power_damage_mult()
activated power damage  x= power_damage_mult                               once, at each power's damage site
```

| Power | Where | How |
| :--- | :--- | :--- |
| Brutal Attack | `SkillController._apply_skill` | its damage multiplier x `power_damage_mult` |
| Whirling Strike, Staggering Blow | `PowerController._strike` | the power's multiplier x `power_damage_mult` |
| Flame Nexus, Detonation | `PowerController._fire_blast` | fire damage x `power_damage_mult` |
| Take Aim (hero's arrow) | `BowAttack.loose` | the arrow's damage x `power_damage_mult` when armed |

Not scaled: ordinary swings and arrows, Fireball (a spell, not a power), War Cry, Provoke, Repulse and Silence (no damage), enemies' attacks, and
`Combat.resolve` / resistances (untouched). Tooltips for Brutal Attack and Take Aim use the same multiplier.

Live item: **Assailing Talisman** (`mgc_a3_vet_crafted_4`, Talisman, level 75): +18 maximum melee and ranged damage, +7% power recharge, +3% power damage,
30% reflected. Requirement `melee:#item_level-8|ranged:#item_level-8` (carried by the new optional `UniqueDef.requirements`, rebuilt on load).
The Item Test Lab readout shows "Power damage: +N%".

## Assumptions and limits

- Several sources **add** (the usual DS2 rule for alterations of one kind); this is not shown in the extracted data.
- The bonus is **multiplicative** with a power's own multiplier, the Arcane Fury passive and Searing Flames, as in `DamageGoPower$`.
- The Cutter companion's Take Aim arrows (`ArcherCompanion`, no gear model) and powers Curse has not built (Thunderous Shot, Shrapnel Blast, Flurry,
  chain lightning and the rest of `data/powers`) are not scaled; they gain it when they are implemented.
- The other 15 catalogue items carrying the alteration are not imported: each also needs resistance (physical, magical), nature magic, skill-suite or
  passive-skill alterations, or a base Curse does not have.
- A set bonus with power damage (`sets.gas`) is not wired.

Tests: `--only=powerdamage` (`game/dev/suites/power_damage_tests.gd`): seeded ratios of real runs of Whirling Strike, Flame Nexus, Brutal Attack and the Take Aim
arrow with 0, +3% and +10% (three sources), replace, repeat, unequip, bag, save, the real talisman and the Lab readout; mutation-checked (applying the multiplier twice fails 5 checks).
