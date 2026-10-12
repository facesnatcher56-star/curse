# Reliable obstacle navigation — verification ledger

2026-10-11, Godot 4.8-dev2 (7220d456d). Production save access was disabled in every
standalone check (`TownState.persist = false`); the selftest uses SavePolicy isolation.
No notifications, combat formulas, analog movement, dodge displacement or knockback were redesigned.

## Implemented

Shared explicit routing states and waypoint, synchronized-map gating, validated path segments,
strict FIFO four-query budget, retained pending-query paths, map-change invalidation, actual
movement watchdog, one-second failed-route backoff, enemy near-target routing, companion
follow/approach/retreat routing, basic melee/bow solid-world checks and rescue-only catch-up.
Destruction performs real asynchronous rebaking, including a request arriving during a bake.

The old arena regression accepted an empty path and collision sliding. It now requires a
synchronized map, a nonempty detour longer than the straight line, geometric clearance,
body-sweep clearance for every segment, and actual arrival. The production startup fix,
not a test-side forced map update, establishes readiness.

## Actual checks

### Rubble failure reported after the initial pass

The owner's screenshot exposed a missing class of obstacle. The initial visible test selected
a prevalidated clear route, masking bad bake geometry. An unbiased scan found 126 blocked
segments among 165 valid-endpoint rubble approaches: Recast considered sloped rubble tops
walkable, while `Actor.move_with` fixes actors at y=0. Replanning therefore returned the same
impossible route. The prior passing traversal evidence did not cover this failure.

Solid props now project their actual collider hull footprints into height-extruded bake
exclusions, retaining agent-radius clearance. These exclusions share the prop's lifetime,
including destruction/rebaking. This uses the engine's documented
[bake-obstruction support](https://docs.godotengine.org/en/latest/classes/class_navigationobstacle3d.html).
Companions also fall back from a disconnected formation point to the leader using the
existing query result rather than an extra unbudgeted query.

After the correction: 180 rubble approaches scanned, zero body-blocked path segments;
three destinations are on disconnected baked islands (two town-edge approaches and one
road-camp approach), reported separately rather than silently counted as successful routes.
Their full connectivity still needs inspection. Cutter's actual AI follows around two
previously blocked road rubble piles from four directions each (8/8 arrivals within follow
range). A stationary-Hero/opposite-side-Cutter visible reproduction passes at 1080p and
1440p; route/end screenshots were personally reviewed. Production saves remained untouched.
The expanded shared-routing suite passes 43 assertions, including disconnected-formation
fallback; the FIFO still peaks at four queries/tick and six ticks of waiting under crowd load.

Additional developer checks:

```
--headless --script game/dev/navigation_rubble_check.gd -- --navigation-check
--script game/dev/navigation_gameplay_check.gd -- --navigation-check --rubble-only
```

- Deterministic real-physics fixtures: pillar, nearby wall, narrow corridor, U obstacle,
  moving destination, disconnected region, unusable map, real destroyed-prop rebake.
- Hero and Cutter share movement; inactive Cutter follows a detour; selection preserves
  independent route dictionaries, including selection during active traversal. Real enemy chase (including under the old 3.5 m bypass),
  retreat, circling and wall-blocked melee are exercised. Common bow rejects a wall-blocked shot.
- Six common-character bodies plus twenty real enemy bodies move through the FIFO:
  peak four queries per physics tick, longest wait six ticks, every body advances.
- Rescue eligibility, attack/stun/death/dodge rejection, visible departure/arrival,
  missing/blocked/occupied breadcrumb, knockdown/ragdoll, insufficient failure time/replans, absent camera,
  safe off-camera rescue and route reset. Failed disconnected routes stop and back off.
- Strict arena arrival: 25 path points, 42.0 m route versus 18.4 m straight, 7.1 m
  clearance around a 6.2 m prop; actual arrival in 9.1 seconds.
- Focused `ds2combat`, `gamepad`, `enemies` and standalone `party_live_check` passed.
  The latter also covers switching, both members using melee/bow and independent reload.
- Visible automated traversal through the real connected town/road with complete HUD:
  1920×1080 on monitor 2 and 2560×1440 on monitor 1, interface scale 1.0.
  Town Hero: 15-point detour, arrived, companion gap 5.76 m.
  Road Cutter: 11-point detour, arrived, companion gap 3.45 m.
  Plaza through gate to road: 37-point route, arrived, companion gap 3.45 m.
  Swapped ordinary equipment repeats the town with Cutter leading in melee/Hero following
  with a bow, and road with Hero leading with a bow/Cutter following in melee. Both members
  therefore traverse these real-world routes under human and AI assignments with both weapon types.
  Both resolutions passed. Start/route/end captures were recorded under the OS temp folder,
  `curse_navigation_{1080,1440}_{town,gate,road}_{start,route,end}.png`.
  Route/end captures were personally inspected: characters traverse around the authored
  props; road trees can obscure bodies, an existing presentation limitation.

## Reproduce

Use `tools/run_godot.ps1` with a suitable timeout and isolated developer arguments:

```
--headless --script game/dev/navigation_check.gd -- --navigation-check
--script game/dev/navigation_gameplay_check.gd -- --navigation-check
--headless res://game/main.tscn -- --selftest --only=navigation
--headless res://game/main.tscn -- --selftest --only=ds2combat
--headless res://game/main.tscn -- --selftest --only=gamepad
--headless res://game/main.tscn -- --selftest --only=enemies
--headless --script game/dev/party_live_check.gd -- --party-check
```

## Remaining acceptance gaps

Visible checks drive real movement/AI in the actual world but freeze hostile enemies;
they are not a full human-controlled combat playthrough of the entire road. All melee/bow
equipment × controller combinations have not been traversed through every obstacle fixture.
Synchronous map-build frame cost on the full world has not been profiled.
Decorative TownNpc choreography remains its separate
noncombat path follower; it was inspected but is outside the selected three consumers.
No UI layout was changed, so this navigation pass does not replace the broader milestone's
UI-scale/interaction acceptance or establish full player-test readiness.
