# Review of e0086af4 — 2026-10-12

READY_TO_PLAYER_TEST=no. This records actual verification, not certification.

## CI failures and fixes

Reviewed Actions run 131 (38239564788), and compared run 130, which already
contained the invalid health access, hover and departure failures.

- Exact invalid-property caller: `TownTests._test_run_modifiers`, formerly
  `town_tests.gd:246`, reading `zombie.health` on EnemyDef. The test now derives
  base life through MonsterScaling and asserts the exact 1.5 modifier. No legacy
  health field or second combat rule was added.
- Swing interruption: obsolete global hotbar setup. Configure/restore the actual
  member's slot, retaining both usable-power cancellation and cooldown checks.
- Hover: the fixture never placed the mouse over its target. Supply a real
  projected mouse position; dummy headless DisplayServer requires the production
  picker's explicit coordinate API. Visible real-pointer check also passed.
  Assert the specific expected silhouette, not either of two possible targets.
- Departure/clan reaction: Cutter is now a permanent companion, not a hired
  recruit. Assert he stays, then test departure with an isolated recruit and
  assert both removal and the exact -3 reaction. No departure assertions removed.
- Repeated full runs exposed fixture contamination: nested town construction
  replaced the harness body registry, breaking later dodge tests. Restore that
  registry. Random shopping stock could correctly fail equipment requirements;
  use ordinary wearable starter gear for the buy-and-equip fixture instead of
  relaxing production requirements.

## Genuine production fixes

Both bodies could collect an already-queued pickup in the same frame. Orbs and
equipment pickups now reject queued deletion; regression checks cover mana,
gold and equipment without duplication. Health uses the same guarded orb path.

The three disconnected queries represented two narrow pockets, not three unique
areas. Hero-radius sweeps could exit but shared 0.75 m navigation clearance could
not. Owner approved widening the gaps: town Gravestone3 moves to (14,0,13), and
camp rubble moves from x=-11.5 to -13.5. Shared navigation clearance is unchanged.
Final town footprint-overlap test passes. Earlier trial placements failed that
check and were corrected, not accepted.

## Executed verification

All gameplay fixtures disable persistence. Disk migration/reload fixtures use
SavePolicy's development directory. No production campaign save was used.

- Focused suites passed: hotkeys, modifiers, townsim, padtarget (headless and
  visible), world, crypt, townlayout, party state and party live.
- Party checks include migration/idempotence, six-member capacity, ownership and
  subgroup separation, independent XP/configuration, delayed arrow/burn identity,
  shared gear rules, and actual serialization/reconstruction.
- Shared navigation suite: zero failures, peak four queries per tick, maximum
  wait six ticks, including six bodies plus twenty enemies, rebaking and rescue.
- Final rubble scan: 180 queries, zero blocked segments/disconnected endpoints;
  six actual Hero/Cutter arrivals at the original failing pairs and eight AI
  rubble-follow approaches passed. Failure now produces a nonzero test exit.
- Opening continuous combat with member switching passed all five groups without
  death: 322 XP, level two. Expanded checks passed actual kill-loot collection,
  three nest rewards and repeat protection, party-share quest XP, isolated disk
  reload, one-member death/switch and whole-party death/revival. Controlled
  placement for the post-combat fixtures is explicit: not an uninterrupted
  human playthrough of all those systems.
- 20,000-roll loot check and same-frame duplicate-pickup regressions passed.
- Full fourteen-group continuous routing/combat with switching also passed:
  1,247 XP, level three, no member deaths, followed by the same integrated
  nest/quest/loot/death/reload checks, zero failures. This was automated headless
  traversal, not a personally played visible full-road acceptance run.
- Visible 1440p opening continuous combat passed without death. Earlier launches
  crashed before script output in the restricted environment; elevated launches
  worked at both resolutions. This associates the failure with launch context,
  but does not establish a symbolicated engine crash cause or a code crash fix.
- Personally reviewed both changed locations at 720p/900p/1080p/1440p and scales
  0.5/1/1.5 (24 captures). These are geometry/HUD captures, not the full UI
  hover/tooltip/menu interaction matrix. Existing intro-log overlap at 720p/1.5
  remains. 1080p uses monitor two; native 1440p uses monitor one.

Full self-test history: baseline reproduced run 131; an intermediate corrected
run passed the strict CI checker. Subsequent repeats exposed the body-registry
and shopping fixtures above. Latest `full_release` assertions completed, but the
strict checker rejected a dummy-renderer `texture_2d_initialize` null parameter
during loading. Focused loading then passed; this error is not suppressed.
ObjectDB exit-leak and legacy material `grow_enabled` warnings also remain.

Final repeat `curse_review_full_repeat.log` completed and passed
`tools/ci_check_selftest.py` with no script errors or failed assertions. The
previous intermittent dummy-renderer failure remains a recorded investigation
gap; one clean repeat does not prove it eliminated.

## Encounter review and outstanding acceptance

Current road has fourteen authored groups, 36 bodies, maximum three per group,
no procedural filler. Fewer/smaller fights are achieved. Opening compositions
remain repetitive melee groups; later rock-thrower groups add limited variation.
Static placement is not a reviewed patrol system. Tactical quality is not proven
by count assertions or a no-death run. No old counts or filler were restored.

Remaining: reproducible clean final full-suite result and fresh Linux Actions
verification; resolve/characterize intermittent renderer error and engine startup
crash; complete visible full-road combat traversal at both target resolutions,
varied seeds, equip found upgrades, and complete UI interaction acceptance.
No networking, new combat architecture or expanded content was implemented.

Follow-up: pushed fix commit 702190492e263a9f869139d0ae53e883fea19500.
Actions run 38248434528 completed with one failed assertion, `roll shoves
non-bosses aside` (attacker displacement printed 0.3 m against a strict >0.3 m
check). The original invalid-property/four assertions did not recur. This new
result is not a CI pass; the roll issue has not been fixed or weakened during
the subsequent target-HUD presentation task.
