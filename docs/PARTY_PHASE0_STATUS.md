# Common-character milestone — verification ledger

This is work in progress, not player-test readiness or integrated acceptance.

## Implemented foundation

- One CharacterState and common Player component stack, equipment-based bow attacks,
  member-aware DS2 rule access and passive purchases, independent hotbars/vitals/power state.
- Version-11 migration after existing legacy migrations; no free Cutter Take Aim.
- Shared backpack persistence including cell positions/rotation; campaign data stays in TownState.
- Variable roster capped at six; persistent owner IDs separate from character IDs and controller
  subgroups. Validated 1×6, 2×3 and 3×2 allocations. No multiplayer networking or campaign-join UI.
- Instant local switching, camera/HUD/menu handoff, companion order execution, living-member
  selection and whole-party defeat detection. Keyboard C and controller Left Trigger defaults.
- Captured character/owner provenance in combat results, arrows, fireballs and burns.
- Owner-approved party-share multiplier for quest, standing-board and destroyed-nest XP;
  living recipients advance their own most-used discipline. Dead members receive none.

## Actual checks

Run using the project's Godot binary with developer arguments after `--`:

```text
--headless --path . --script game/dev/party_state_check.gd -- --party-state-check
--headless --path . --script game/dev/party_live_check.gd -- --party-live-check
--path . --script game/dev/party_visual_check.gd -- --party-visual-check
```

Data regression passes: isolated on-disk v10 fixture, migration idempotence, XP/classes/gear/
purchases/points, legal starter equipment, no free power, hotbars, vitals/power state, one shared
backpack, six-member serialization, owner/controller separation and subgroup validation.
Live regression passes before the final UI review: common components, no-respawn selection,
camera/HUD handoff, editable input bindings, shared purchases, delayed arrow/burn provenance,
subgroup switch restriction, bow/melee cross-equipping, paused menu handoff and survivor selection.
Fresh actor reconstruction also passes independent vitals, hotbar and recharge restoration.
The data suite passes all 30 checks, including shared non-combat rewards and dead-member exclusion.
Focused suites passed: ds2combat, classskills, skilltree, ds2items, powers, livepowers, inventoryequip
and xp. The XP suite exercises actual quest/board claims and nest destruction, including single
payment, and now expects survivor switching rather than automatic single-character revival.

The first 1080p/1440p × 0.5/1.0/1.5 visible capture matrix completed. Personal review found
menus covered party portraits at maximum scale. Menus now reserve portrait space and identify
the member by name. Revised captures and review are in progress. Captures alone do not pass
hover/focus/controller interactions or integrated gameplay acceptance.

## Remaining acceptance work

Inventory follow-up: narrowed the design from 640 to 560 logical pixels, kept the backpack
at its content width, and enlarged the preview slot from 120 to 180 pixels with a closer
camera (2.4 to 1.75 body heights). The visible theme suite passed all four supported
resolutions at 0.5/1.0/1.5. All 12 populated inventory captures were personally reviewed;
item-tooltip samples at 900p/1080p maximum scale were reviewed. Both-character road
captures completed; Cutter's 1080p scales and 1440p maximum-scale preview were reviewed.
Equip, rotation and controller-menu suites passed. This does not close the wider Phase 0
acceptance gaps below or establish every long-text/tooltip combination.

- Full companion navigation/spacing/power-use verification and rig/weapon animation review.
- Independent save/reload with live bodies, all armed/timed states, death/revival, committed
  casts and effects, and safe menu interactions during switches.
- Update legacy focused suites that assert the retired fixed-Cutter implementation; run the
  relevant combat, inventory, power, menu, loot and gameplay regression suites.
- Complete reviewed screenshot/tooltip/focus matrix and lower-resolution compatibility checks.
- Progression notification clarity/queuing and all UI overlap/target-level boundary checks.
- Later encounter/road rebuild and unchanged DS2 loot distribution audit, then integrated road
  playthrough and the established independent acceptance policy.

No production save has been modified by these checks. Saving remains disabled by SavePolicy.
