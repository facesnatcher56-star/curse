# DS2 parity corrections — 2026-10-11

The authoritative project remains this checkout. These corrections use the owner's installed DS2 data, not web summaries.
The extraction tools store numeric tables only; the original game scripts/art are not copied into the game.

## Movement

`heroes_ds2.gas` gives average movement velocity 4.5 for the hero bodies. Hero and Cutter use 4.5 world units/second.
`actor_evil_melee.gas`, `actor_evil_ranged.gas`, and `actor_evil_magic.gas` give these tier/role averages:

| Role | Trivial | Weak | Normal | Strong | Miniboss |
| --- | ---: | ---: | ---: | ---: | ---: |
| Melee (including tank/rogue) | 2.7 | 2.7 | 2.5 | 2.3 | 2.7 |
| Ranged | 3.2 | 3.2 | 3.0 | 2.3 | 3.2 |
| Magic | 3.7 | 3.7 | 3.5 | 2.8 | 3.7 |

This supersedes the earlier 70% non-leaper slowdown. Ghoul ground movement follows its weak melee/rogue template; pounce trajectory,
windup, recovery and damage remain unchanged. Remove per-spawn speed jitter. This matches source numbers, not a claim that different
models/cameras have identical perceived scale. The existing walk clips cover speeds through 3.0, faster enemies run; cadence follows speed.

## Existing-system corrections

- Brutal Attack and Fireball cannot crit; forced critical charges do not override that restriction.
- Armor applies to fire spells/powers. The minimum damage floor precedes final resistance: immunity is zero and absorption heals.
- Physical power multipliers include added elemental damage. Added fire rolls its actual min/max range.
- Party damage from arrows and sourced burns feeds other powers, never its originating power. Overkill does not inflate recharge/leech.
- Fierce Renewal affects all melee powers; Cunning Renewal affects hero ranged powers. Arcane Fury grows magic power damage.
- Powers cancel normal attacks immediately. Staggering Blow starts a powered swing when a target already exists.
- Take Aim starts reload at arrow release, even on a terrain miss; projectile speed is twice an ordinary bow arrow.
- Barricade's extra shield armor is added after Reinforced Armor, before percentage gear/Provoke armor.
- Higher-rank live powers now have their missing passive prerequisite paths. Prerequisite-only hero ranged passives are labeled honestly.
- Live powers no longer display the stale “not built yet” blocker.

## Progression and items

`extract_ds2_xp.py` extracts the first 100 experience thresholds from `formulas.gas`; save version 10 preserves earned levels/fractions.
`extract_ds2_affixes.py` extracts supported family names, modifier levels, values, fire ranges, slot/class restrictions and magic-find
roll ceilings from `pcontent.gas`. `write_affix_defs.py` uses that snapshot, not interpolated guesses. Rolled modifier values persist
with their item. Older overflow tier IDs remain readable, but cannot roll on new items.

## Deliberate limitations

This is not full-game parity. Nature systems, missing damage types, the complete DS2 item catalogue, and DS2's unconscious/death flow
are not introduced by this correction pass. Existing owner-approved kill-paid XP, physical knockdown, power-kill gibs and physical
projectiles remain. Crit's second roll still equals the first; Fireball's fitted curve, some power geometry, loot windows/counts and
Cutter's rank-1/passive-free build remain documented approximations or deliberate departures in COMBAT_REFERENCE.md.

DS2 numeric data does not prove exact animation cadence or render scale. Visible movement/archer checks belong on monitor 2.

## Verification

Passed focused watchdog suites: `ds2combat`, `classskills`, `ds2items`, `skilltree`, `powers`, `livepowers`, `brutal`, `archer`,
`xp`, `enemyspeed`, `enemyrun`, `savepolicy`, `actionqueue`, `fireblast`. Added exact-table/migration, fire armor/immunity/absorption,
power elemental amplification, sourced-burn party recharge, affix roll persistence, renewal and missing-prerequisite regressions.
The archer fixture separates stationary draw/impact from retreat/tether checks so random target movement does not conflate them.

Visible `--enemyfight` completed on monitor 2 and frames were inspected. `--archershot` logged `screen=1` and captured the draw frame
and 34 sequence frames, but exceeded its 45-second export watchdog; it is not reported as a completed visual test. No runtime script
error appeared in that run. Existing bow/quiver art was not retuned by this numbers/correctness pass.

Godot MCP project/scene/error queries were used. Its editor output still contains historical DevHarness parse messages; fresh
watchdog runs compile and execute successfully. The production save was not touched. No full-suite, unrelated world/UI regression,
commit or push was performed. 
