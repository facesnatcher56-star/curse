# DS2 combat detail audit — 2026-10-11

Scope: installed Dungeon Siege II `Logic.ds2res` scripts versus the current canonical Curse project. This is a source and focused runtime audit, not a claim that the games are identical. DS2's compiled engine and original animation playback have not been reverse-engineered here; where those determine behavior, the result is explicitly uncertain.

## Presentation changes made

- Both Brutal Attack and Take Aim now use the shared, restrained orange body-bone wisps while armed, including without a target. DS2 `active_skills.gas` assigns **both** powers `ffx_brutal_attack_prelaunch`. Take Aim was previously only giving a short bow flash.
- Take Aim additionally gathers 30 pale motes at the bow hand over 0.4 seconds when its powered draw starts. This follows `efct_take_aim_charge` (sphere radius 1.3, pale particles and a brief light flare), rather than turning the whole archer white.
- Losing a target or abandoning a draw retains Take Aim's stored aura. Spending it or dying clears the aura. Repeated activation cannot stack duplicate auras.
- Reduced the existing Brutal aura's large, bright oval particles to thin, subdued orange wisps. Checked both powers in a visible monitor-two test.

These are native Godot visual approximations, not imported DS2 textures or an exact reconstruction of its renderer. Brutal's inward gather currently happens on activation; DS2 separates its cast-charge and pre-launch effects. Our bow-hand gather follows the moving bow. The owner's unique overhead melee swing remains.

Audio was left unchanged. DS2's wrappers identify `power_takeaim_charge`, `power_takeaim_cast`, `power_take_aim_hit` and `power_brutal_attack_hit`; identifying those names does not make our recordings identical. The Brutal pre-launch wrapper itself contains no PlaySound instruction. Project rules require owner-supplied recordings; no DS2 audio was imported or synthetic replacement generated.

## Interruption: the largest behavioral difference

DS2 `job_attack_object_melee.skrit` defaults `hit_multiple` to false (line 32). Its global `WE_DAMAGED` handler (492) clears a cautious flag; damage transitions in BattleCry, FleeDownTime and DownTime re-evaluate the action. **ContinueAction (854) and DamagingAndFollowingThrough (907) have no generic damage-cancels-swing transition.** Weapon contact and completion use `WE_ANIM_WEAPON_FIRE` and `WE_ANIM_DONE`. Ranged Loading (663 in `job_attack_object_ranged.skrit`) likewise has no generic `WE_DAMAGED` transition.

This is evidence against assuming that every ordinary DS2 hit cancels a committed attack. It is **not** proof that DS2 never flinches: compiled action/hit-reaction logic is outside these files. Exact ordinary-hit interruption thresholds remain unverified.

Curse's runtime tests demonstrate:

- A normal landed hit stuns a small, low-resistance enemy and cancels its committed melee attack.
- An ordinary enemy hit does not cancel the hero's committed swing.
- A heavy enemy hit knocks down the hero and cancels the swing.
- A stunned archer retains draw progress, then resumes it instead of restarting.

That asymmetric behavior is not established DS2 parity. `Actor.receive`, enemy behavior cancellation and the archer's early stun return implement it. Existing owner-approved physical reactions were not silently replaced during this presentation pass. Recommendation: decide whether ordinary hit reactions should be visual-only during committed attacks, with cancellation reserved for explicit stun/knockdown effects. First verify the remaining DS2 engine behavior through a controlled original-game playtest.

## Fine-detail comparison

| Detail | Current Curse behavior | Comparison / confidence |
| --- | --- | --- |
| Normal melee targets | One engaged target; no greatsword arc or corpse-collision damage | Matches DS2's default single-target job. Deliberate area powers remain area powers. |
| Power priority | Activation immediately replaces a normal attack/draw; can store power without a target | Owner requirement retained. DS2 jobs mark normal attacks interruptible and cast-power jobs differently, but this alone does not prove exact engine queue behavior. Instant arming is not instant damage. |
| Power charge timing | Brutal uses the custom overhead swing; Take Aim uses a 0.92-second powered draw | Not exact timing parity: DS2 skill entries specify `charge_time = 0.5`; total timing also depends on its animation/job system. |
| Contact timing | Melee damage at authored contact fraction; arrows release after draw | Same contact/release concept as DS2 animation events, but native clips/timing are not identical. |
| Hit pause | Brief attacker/victim freeze on landing hits; additional critical feedback | Curse-specific feel, not verified in DS2 scripts. A paused attack is distinct from a canceled attack. |
| Small-enemy flinch | Most ordinary hits stun and cancel attacks at low stun resistance | Major unverified departure; see interruption findings above. |
| Hero heavy-hit reaction | Heavy blows cause physical knockdown and cancel actions | Existing Curse physical-combat rule, not verified as DS2's generic heavy-hit rule. |
| Archer interrupted draw | Stun pauses accumulated draw progress | Observed Curse behavior; exact DS2 hit-reaction behavior remains uncertain. |
| Third basic swing | Combo finisher still has a 35% damage bonus and heavier reaction/lunge | Remaining Curse modifier, not supported by the traced DS2 ordinary-attack rules. Worth removing in a dedicated baseline correction. |
| Weapon cadence | Native clip timing plus weapon-profile recovery multipliers and speed stats | Not full DS2 cadence parity. DS2 reload delays (one-hand 0.67, two-hand 0.9, bow 0.625) interact with its animation system; copying a delay alone is insufficient. |
| Archer cadence/targeting | Normal draw 0.62 seconds, cooldown 1.05 seconds plus random jitter; periodically retargets threats attacking the hero | Custom companion AI. DS2 attack jobs pursue an engaged target; random mid-draw retargeting is not established parity. |
| Arrow trajectory | Linear lead, capped prediction; terrain/intervening enemies can intercept | Not exact DS2 ranged aiming. Original job computes trajectory, predicted target position and `ComputeAimingError`. |
| Take Aim projectile | Double normal arrow speed; enhanced shot; cannot crit | Double velocity and noncritical power behavior follow the traced source. Visuals remain approximations. |
| Take Aim spending | Reload starts at release, even if projectile later hits terrain or misses | Matches `power_take_aim.skrit` release behavior. Target loss before release preserves the stored power. |
| Brutal miss/block | Explicitly retains power on miss, dodge, block or invalid target | Owner-approved rule. Original power script calls reload after a valid `DamageGoPower` cast, without testing its damage result. Exact miss handling across the original engine/job path is not established; do not label our preservation rule proven 1:1. |
| Recharge | Party damage reduces the level/group-size budget; waiting alone does not recharge; power does not refill itself | Traced DS2 formula retained, including the 21-second-equivalent budget for these powers. |
| Dodge / block | No additional accuracy roll; dodge and shield block; block prevents damage | Follows DS2 baseline. Curse's physical shove on block is presentation/physics, not independently verified DS2 behavior. |
| Critical damage | Ordinary critical doubles the rolled damage before other supported modifiers | Approximately DS2's baseline 200%; original uses a second independent damage roll, so distribution is not identical. Powers cannot crit. |
| Potions | Instant 60 HP with a one-second cooldown; drinking cancels a current swing | Not DS2's traced 12-second restoration model. Original interruption/order semantics need separate confirmation. |
| Deaths | Power kills gib; critical kills gib; other kills use physical ragdolls | Owner's power-gib rule retained. DS2 also has its own normal-hit gib thresholds, so not exact death parity. |
| Target becomes invalid | Melee validates target/range before applying damage; armed Brutal survives an invalid swing | Both systems validate targets, but exact ranges, chase and job-exit rules differ. No accidental fallback area hit. |

## Evidence and regression checks

Original resource paths: `world/global/skills/active_skills.gas`, effect files `efct_brutal_attack.gas` / `efct_take_aim.gas`, flick wrappers `ffx_brutal_attack.flick` / `ffx_take_aim.flick`, power scripts `power_brutal_attack.skrit` / `power_take_aim.skrit`, melee/ranged attack jobs, `job_abstract_type.gas` and `rules.skrit`, extracted read-only from the installed game. Extracted original files are kept outside this repository.

Curse implementation: `game/actor.gd`, `game/enemies/melee_behavior.gd`, `game/player/skill_controller.gd`, `game/player/player_stats.gd`, `game/archer_companion.gd`, `game/companion_arrow.gd`, `game/skills/brutal_attack_fx.gd`, `game/skill_fx.gd`.

Focused checks passed: `armedfx`, `hitinterrupt`, `brutal`, `archer`, `skillintegrity`, `basicsingle`. `armedfx` also passed visibly on monitor two. The `hitinterrupt` checks lock **observed current behavior for the audit**, not an assertion that it matches DS2. No balance/interruption rule was changed by those tests. The full suite was deliberately not run; verification was limited to affected powers, presentation, interruption observations and single-target attack regressions.
