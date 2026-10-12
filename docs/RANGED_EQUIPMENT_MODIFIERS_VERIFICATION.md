# Ranged equipment modifiers verification

Task 3 implementation commit: `e857e8b` (cherry-picked directly onto `8d3ad5f`, the requested starting checkpoint).

## Verified Dungeon Siege II rules

The implementation is based on the checked-in original data, not approximated values:

- `ds2_source/ds2_reference/rules.skrit:2101-2172` calculates ranged weapon damage in this order: launcher base range; `GetDamageBonusMinRanged` and `GetDamageBonusMaxRanged`; repair `max >= min`; Dexterity contribution; Biting Arrow for non-thrown weapons; `GetDamageMultiplierRanged` over the completed range.
- `ds2_source/ds2_reference/rules.gas:48-56` supplies the installed Dexterity scalar of `0.2`, with minimum effective Dexterity 10 in `rules.skrit:2133-2146`. The low/high contributions are 75%/125% of that bonus.
- `ds2_source/ds2_reference/pcontent.gas:911-1004` defines the ranged-maximum `ofaccuracy` suffix family; `pcontent.gas:1102-1191` defines the ranged-minimum `ofpiercing` suffix family; `pcontent.gas:1316-1432` defines the ranged-percentage `sharp` prefix family.
- All three source families declare `object_types = ranged` and `skill_types = ranger`. Curse maps that to ranged-profile weapons. Current content contains bows only; the shared profile-based calculation and affix-class selection can be reused by later crossbows or thrown weapons without adding a second combat path.
- DS2 explicitly excludes thrown weapons from Biting Arrow, but not from the flat or percentage ranged enchantments. Curse has no crossbow or thrown-ranged weapon in this milestone, so that distinction is recorded but no new weapon category was invented.
- Take Aim is the current weapon-damage ranged power: it multiplies the completed `ranged_range()`. Current live Repulse and Silence powers do not deal weapon damage. Unimplemented DS2 ranged powers were not added by this task.

## Previous gaps and implementation

`PlayerStats.weapon_base_range()` already selected `ranged_min`/`ranged_max` for a ranged-profile weapon, and `BowAttack` already sampled `ranged_range()` before creating a projectile. The missing pieces were generated definitions, ranger weapon generation, the ranged percentage multiplier, and correct basic-attack damage text.

Changes:

- The source extractor now imports all three ranged families and converts the source percentage fractions to percentage points, exactly like the existing percentage families.
- Twenty generated `AffixDef` resources were added. They use the existing modifier-level windows, prefix/suffix constraints, family exclusion, rarity modifier counts, item save form, and drop tables.
- Weapon affix selection now derives `fighter` versus `ranger` from the weapon's shared ranged profile. Previously every weapon was hardcoded to `fighter`, so bows could roll melee affixes and could not roll ranger affixes.
- `PlayerStats.ranged_range()` now applies `ranged_pct` after flats, Dexterity, and Biting Arrow. `weapon_base_range()` continues to repair an inverted range before Dexterity. No melee formula changed.
- Basic-attack damage summaries use `ranged_range()` while a ranged weapon is equipped. Item descriptions and comparison cards use the shared stat-name/percentage formatting.
- `BowAttack` still passes a final sampled damage value into `CompanionArrow.fire()`. That keeps equipment damage fixed at release and retains the stable originating character/owner identity across active-member switching.
- Drop probabilities, rarity weights, Gold Find, Magic Find, attack speed, enemy values, XP, saves, and party ownership were not changed.

## Generated affix tiers

| Family | Position | Modifier levels and values |
| --- | --- | --- |
| Maximum ranged damage | suffix | Accuracy 1:+1; Focus 11:+4; Sighting 24:+11; Precision 40:+25; Seeking 56:+44; Mastery 74:+72 |
| Minimum ranged damage | suffix | Piercing 3:+3; Driving 7:+4; Puncturing 13:+6; Boring 21:+9; Perforating 33:+13; Penetrating 48:+18 |
| Ranged damage | prefix | Sharp 1:+10%; Honed 10:+15%; Stinging 16:+20%; Jagged 23:+26%; Fine 30:+33%; Serrated 38:+40%; Keen 46:+48%; Razor 55:+56% |

Generated source eligibility is ranged weapons only. The shared equipment accumulator was also tested with two equipped sources to protect authored/future item compatibility without broadening the generated DS2 pool.

## Calculation example

A level-10 Short Bow has source-curve damage `7.125-11.875`. With Piercing (+3 minimum), Accuracy (+1 maximum), Dexterity 11, Biting Arrow rank 1 (+8%), and Sharp (+10%):

1. Flats: `10.125-12.875`.
2. Dexterity: add `0.75 × (0.2 × 11) = 1.65` minimum and `1.25 × (0.2 × 11) = 2.75` maximum, producing `11.775-15.625`.
3. Biting Arrow: `×1.08`, producing `12.717-16.875`.
4. Ranged percentage: `×1.10`, producing `13.989-18.563` before target resolution.

Critical Shot selects whether the resolved hit is critical; Mortal Wound supplies its critical multiplier. Take Aim multiplies the completed range and cannot critical. Ranged block, toughness, armour, and level-gap mitigation remain in the common `Combat.resolve()` path.

## Automated verification

Focused suites executed against the implementation:

- `--only=rangedmods`: PASS. Covers base/min/max/percentage/combined ranges, inverted range repair, attack-speed and melee isolation, multi-source stacking, exact source tiers, valid/invalid modifier levels, bow/sword generation discipline, tooltip/comparison/hover text, Hero/Cutter independence, switching, JSON save/reload, Biting Arrow, Critical Shot, Mortal Wound, Take Aim, real projectile critical/block/armour outcomes, and arrow-flight snapshot ownership.
- `--only=equipmenthits`: PASS. Task 1 restoration/reflection regression.
- `--only=find`: PASS. Task 2 Gold Find/Magic Find statistical regression (100,000 samples for each tier and MF state).
- `--only=items`, `--only=ds2items`, `--only=lootui`, `--only=itemicons`, `--only=uiaudit`, `--only=inventoryequip`, `--only=powerui`: PASS.
- Complete `--selftest`: PASS, exit code 0. It reported the pre-existing test-shutdown warning of 534 leaked `ObjectDB` instances.

Those successful runs used the primary checkout at the same Task 3 source diff. A secondary clean-worktree run was attempted after isolating the commit onto `8d3ad5f`, but that checkout contained Git-LFS pointer stubs rather than usable model binaries. Godot consequently emitted model-load/script errors even after copying the ignored import cache; its apparent exit code was not accepted as test evidence. GitHub Actions is the clean Linux verification authority for the pushed commit.

The standalone `--only=inventorygrid` fixture still fails `failed pickup leaves the drop on the ground`: after its `TownState.reset()`, the live body's equipment is empty, so the pickup fills the empty weapon slot instead of attempting the deliberately full backpack. The unchanged test passes in the complete ordered suite. It was not weakened or changed for Task 3.

## UI verification

The theme matrix's inventory fixture was changed to a rare bow carrying all three modifiers, so its actual hover card is the longest new ranged-modifier presentation. Headless bounds/hover verification passed. Visible captures were produced and reviewed at 1280×720, 1920×1080, and rendered 2560×1440 for interface scales 0.5, 1.0, and 1.5. All modifier, requirement, and comparison lines were visible without clipping or text overlap.

The visible matrix retained two existing environment/harness gaps rather than suppressing them:

- This session exposes one physical 1080p display, so the three native 2560×1440 physical-monitor-fit assertions fail. The 1440p rendered captures were reviewed, but native 1440p display verification remains outstanding.
- The synthetic pointer event missed the item once at 1600×900/scale 0.5; that capture therefore has no tooltip. The inventory rendered correctly, and the same 0.5 tooltip was successfully captured at 720p, 1080p, and rendered 1440p. The test was not weakened.

## Remaining limitations

- Crossbows and thrown-ranged weapons do not exist in current content and were not added.
- Damaging ranged powers other than Take Aim are not currently implemented, so there is no additional live power path to exercise.
- Native 1440p viewing and the single 1600×900/0.5 synthetic-hover miss remain UI acceptance gaps.
- The engine's existing test-shutdown leak warnings remain.
- This milestone does not establish overall player-test readiness and does not alter networking or party architecture.
