# Wave 3: Crypt Road encounter population report

Source: `game/world/road_encounter_roster.gd` (rows `BEATS`), measured by `--only=roaddensity` in the same code.
Segments are by road z (town gate at z 174): intro z above 110, graveyard 40 to 110, wooded choke -40 to 40,
courtyard -146 to -40, forecourt z at or below -146.

## Before and after (same test, same spawn code)

| Segment | Before (bodies) | After (bodies) | Change |
|---|---|---|---|
| Intro (z above 110) | 8 | 10 | +25% (kept light) |
| Graveyard (40 to 110) | 10 | 18 | +80% |
| Wooded choke (-40 to 40) | 8 | 15 | +88% |
| Courtyard (-146 to -40) | 8 | 16 | +100% |
| Forecourt (z -146) | 2 | 2 | unchanged |
| **Total** | **36** | **61** | **+69%** |
| Groups | 14 | 24 | |

## Per segment (after)

Spacing is about 2.5 m across a group and 9 to 22 m between groups. Groups spawn at fixed authored spots.
Levels are DS2 monster levels set exactly per body. "Wander" groups roam within 6 m of their spot; the rest guard.

**Intro (10 bodies)**
- z 153, 133, 111: trivial zombies (2, 3, 3), level 1, guard. Unchanged.
- z 124: roaming pair of zombies, level 1, trivial. New.

**Graveyard (18 bodies)**
- z 87, 64: trivial zombies (3 each), level 1. Unchanged.
- Side groups at (-21, 58) and (20, 52): zombie pairs, level 2. Unchanged.
- z 98: roaming zombie, ghoul, zombie, level 2, weak. New.
- z 76: rock thrower, zombie, ghoul, level 2, weak. New.
- z 46: BRUTE with zombie, level 3, guards the approach to the second nest (20, 52). New elite-class placement.

**Wooded choke (15 bodies)**
- z 34: zombie and rock thrower, level 2, weak. Unchanged.
- z 24: roaming ghoul, zombie, ghoul, level 3, weak. New.
- z 14: BRUTE with zombie, level 4, guards the choke. New.
- z 6: zombie x3, level 2, weak. Unchanged.
- z -23: zombie x3, level 2, trivial. Unchanged.
- z -36: rock thrower and zombie, level 3, weak. New.

**Courtyard (16 bodies)**
- z -53: zombie and rock thrower, level 2, weak. Unchanged.
- z -68: roaming ghoul, zombie, rock thrower, level 4, weak. New.
- z -83: zombie x3, level 2, weak. Unchanged.
- z -92: zombie, BRUTE, ghoul, level 5, guards the third nest (14, -98) at about 15 m. New elite-class placement.
- z -114: zombie x3, level 3, trivial. Unchanged.
- z -128: WARDEN (miniboss tier) with zombie, level 6. Elite before the forecourt. New.

**Forecourt (2 bodies in the road roster)**
- z -146: zombie pair, level 3. Unchanged. The forecourt climax (groups 27 to 29) is separate and unchanged.

## Performance note

- Static caps are checked by the test: at most 18 bodies per segment (`SEGMENT_CAP`), at most 64 bodies in the road roster (`TOTAL_CAP`), and no group above 4.
- The real count of simultaneously aggroed enemies is NOT measured. Groups wake together on notice, so the worst case is one group per segment at once (at most 4 bodies), but this was not profiled.
- Enemy types are existing only: zombie, ghoul, rock thrower, brute, warden. No acid spitters, priests or bloaters on the road.

## Verification

- `--only=roaddensity`: exit 0, 0 `[FAIL]`, 0 `SCRIPT ERROR`. Checks: segment ranges, per-segment cap, total cap, group size, no overlap (2D spacing of at least 1.2 m), brutes placed, warden placed before the forecourt, regrow restores the same 61 bodies once.
- `--only=crypt`: exit 0, 0 `[FAIL]`, 0 `SCRIPT ERROR`. Updated to 24 groups and 61 bodies.

## NOT verified

- Real engagement frequency in play. Nobody has played this road, so whether the new groups are met often enough is UNKNOWN.
- Difficulty of the brutes and the warden at the expected level. Not playtested.
- Whether the roaming groups stay clear of the nests and quest targets while they wander.
- Frame-time cost under real AI and physics load. Not profiled.
- The pilgrim camp (id 3) and graveyard threshold (id 4) validators, which spawn subsets of the roster, were not run.
- `crypt_forecourt_validation.gd` asserts a 170 to 280 road total. It is not in the selftest and was not run; it already disagreed with the 36-body roster before this change.
- Owner questions still open: whether the warden at z -128 is the intended elite for the approach, and whether the brutes at the nest approaches are the right elite class.
