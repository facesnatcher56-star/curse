# Road rebuild — 2026-10-12

Replaces the old crowd layout rather than layering another multiplier over it.
The roster is authored Curse geography with DS2 stats, not an exact DS2 map import.

## Changes

- Fourteen groups, 36 bodies; no multiplied zombie/ghoul packs, grid filler or linked distant cottage reinforcements.
- Opening groups: 2 / 3 / 3 / 3 / 3 level-one trivial fighters, each 7.56 life and 3.9–6.5 raw physical damage.
- Melee attacks use a two-second base duration (Bracken animation source), with random heavy lunges disabled on this road. Existing recovery/random animation-rate scaling is still an approximation, not exact DS2 AI parity.
- Main route centres are 20–32 metres apart; side nests each have two guardians. No roaming 50-metre patrol joining several encounters.
- Acid, puddles, poison/slow, explosive bloaters, summoning priests and heavy-knockdown brutes are absent from this road roster.
- Later rock throwers use DS2 weak ranged stats (23.808 HP at level two), physical projectiles at speed 15 and world collision. Existing spitter model/throw animation is borrowed presentation, not a DS2 golem model.
- Nest bursts: two trivial fighters, nearby wake radius eight rather than 26 metres; uprising reinforcements capped at three.
- Common monster money/potion/equipment alternatives now use the original DS2 oneof weights. Old automatic kill gold and health-dependent kill orbs are removed. Money is represented by a collectible yellow pickup.
- Mana potions have a shared saved count, blue pickup, rebindable W action and focusable/clickable HUD button. They restore 60, matching the current health-potion amount, not a complete DS2 potion-tier import.

## Actual checks

`road_pacing_check.gd`: isolated reset with saving disabled; actual Hero basic-attack input/physics, Cutter AI and enemy physics. No purchased passives, free powers or stat buffs. Starting health potions may be consumed below 40% health. Five seconds of ordinary regeneration between encounters. Pack-to-pack placement is controlled: this is not a continuous traversal test.

Opening passed: 322 XP and level two after five fights; no deaths. Original trial failed before this revision and was not accepted as a pass.

Latest 20,000 weak-tier loot rolls: 2,839 gold results, 853 health potions, 466 mana potions and 1,193 equipment results. Statistical checks passed. Mana pickup, consumption, shared use after switching and actual reload preserving both characters' XP passed.

All fourteen groups passed the controlled-placement combat check: 1,247 XP, level three, no deaths. This check does not include destroying nests or equipping found upgrades.

Continuous visible 1080p traversal from town through the first five groups also passed without pack-to-pack teleporting: 322 XP, level two, no deaths. Captures were reviewed. The equivalent 1440p traversal launch crashed inside the engine before script output twice; it is not a pass.

`--only=ds2items` and `--only=world` passed. Other legacy encounter suites were not run.

Visible opening/potion-dock captures reviewed at 1280×720, 1600×900, 1920×1080 and 2560×1440, each at scales 0.5 / 1 / 1.5. 1080p used monitor two, 1440p monitor one. New count/button fits; keyboard focus is visible. The existing introduction log overlaps party panels at 720p/1.5. Native tooltip, inventory-open and complete mouse/controller interactions are not yet verified; the screenshots do not establish full UI acceptance.

## Remaining acceptance

2026-10-12 review update: see [e0086af4 review](MAIN_E0086AF_REVIEW.md) for
newer actual results. Visible 1440p opening traversal subsequently passed outside
the restricted launch environment; the original pre-script engine crash remains
unsymbolicated. Automated headless continuous traversal of all fourteen groups
with combat-time switching passed without deaths (1,247 XP, level three), as did
post-combat nest/quest XP, loot, isolated disk reload and party defeat checks.
This does not replace visible full-road and complete UI interaction acceptance.

Continuous traversal beyond the opening and at 1440p, nests together with combat, varied seeds, equipping found upgrades, actual later projectile collision checks, complete UI interaction matrix and legacy encounter-suite updates remain necessary. Container loot parity, tiered potions and complete miniboss consumable loot are not implemented. No production save was loaded for verification or written. This is not a player-test-ready certification.
