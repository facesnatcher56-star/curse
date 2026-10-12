# Roll-shove CI fixture repair

Starting commit: `41b06355cfd4acceeb0850dae9314466e61656fa`.
Failing Linux run: https://github.com/facesnatcher56-star/curse/actions/runs/38272292655

## Cause

`game/dev/suites/melee_tests.gd::_test_roll_shove` placed the player at
`(20,0,20)` and zombies at `(21.4,0,20.1)` and `(22.4,0,19.9)` without checking
the arena's scenery. Diagnostic world shape queries found both zombie spawn
footprints intersecting the same static scenery body. The initial boss spawn
at `(22,0,26)` also intersected scenery. These were actual collision bodies,
not visual mesh overlap.

On Windows, before the roll's baseline measurement, collision recovery moved
the near zombie to `(21.37445,0,20.15505)` and the attacker to
`(22.53963,0,20.34476)`. The attacker's sideways sign had already changed.
It also had a world contact at the end of the check. The old test moved the
boss again, into a crowded corridor, then printed its approximately 0.6 m
displacement without asserting immunity.

`PlayerMovement.shove_enemies` uses collision-respecting `move_and_collide`
for displacement and `Actor.interrupt` for stun. `Enemy._physics_process`
cancels the attacking state while stunned and calls `move_with`, whose
`move_and_slide` can recover initial penetration even at zero desired speed.
The fixture therefore mixed scenery recovery, obstruction, and the shove in
one final position difference. The Linux result (attacker rounded to 0.3 m)
does not demonstrate insufficient shove strength. Its printed one-decimal
value cannot establish the exact amount relative to the strict threshold.

This is a positioning/measurement defect. Timing affects the contaminated
measurement, but the corrected fixture passes at 30, 60 and 120 physics Hz
without production movement changes. No claim is made that all physics
trajectories are identical across tick rates or operating systems.

## Repair

- Use the existing world-collision query helper to find a clear 9 m by 7 m
  corridor. Assert that it exists and that the zombies remain at their authored
  positions before the roll; clear previous test enemies and movement orders.
- Keep the original `>0.3 m` displacement requirement for both zombies.
- Check that both enemies were actually contacted by the roll and that the
  committed attacker becomes interrupted and stunned during the roll.
- Place the boss in shove range without initial body contact. Assert zero
  direct shove displacement/stun, no shove registration, and less than 0.01 m
  total movement throughout the live roll.
- Assert immediate roll start, world-only roll collision, late immunity and
  restored normal collision. Exercise the real physics loop at 30/60/120 Hz,
  waiting by simulated duration instead of a fixed 40-frame count.
- Add `--only=rollshove` and optional rendered `--rollreview` captures.

Production roll speed, duration, displacement, interruption, collision masks,
boss rules and responsiveness are unchanged. This preserves Curse's existing
roll mechanic; it does not assert that manual roll shoving is a DS2 mechanic.
Task 1 and Task 2 equipment code is unchanged.

## Evidence (2026-10-12)

Godot 4.8-dev2 Windows focused and rendered results:

| Physics Hz | Near sideways m | Attacker sideways m | Boss movement m |
| ---: | ---: | ---: | ---: |
| 30 | 1.600006 | 1.600006 | 0 |
| 60 | 1.400005 | 1.500006 | 0 |
| 120 | 1.399979 | 1.449978 | 0 |

Full default self-test and focused `rollshove`, `dodgecancel`, `impact`,
`knockdown`, `ds2combat`, `equipmenthits`, `find` passed the strict log checker.
The full run still reported 508 leaked ObjectDB instances on shutdown.

Rendered 1920x1080 run passed. Before/during/after viewport captures were
personally inspected: real rolling animation, opposite-side zombie movement,
and stationary boss. This was an automated fixture in the actual main scene,
not a manual road traversal. Only one display was available; the initial
second-monitor attempt produced an invalid-screen error and was rerun cleanly
on screen 0. A material `grow_enabled` warning remains outside this fix.

Local WSL is unavailable. The original Linux failure is preserved in the linked
run; the pushed fix is verified by GitHub Actions, with its exact outcome
reported after completion. Local verification includes unrelated uncommitted
objective/notification work; Linux CI checks only the committed files.

All runs used self-test SavePolicy isolation. Production saves were untouched.
No overall player-test readiness is established by these checks.
