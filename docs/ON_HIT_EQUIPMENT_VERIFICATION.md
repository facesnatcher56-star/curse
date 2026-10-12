# Task 1: existing on-hit equipment effects

2026-10-12. No affix/unique values, enemy scaling, XP formulas, loot probabilities, equipment types, or party architecture changed.

## Audit and changes

All five effects already had numeric definitions and consumers. Life/Mana Steal and Life/Mana per Hit worked on ordinary weapon hits, capped resources, used member-local gear, and received overkill-clamped damage from Actor.receive. Direct spells were incorrectly excluded, and secondary physical events could trigger restoration. Reflection ran in a pre-damage filter, before wards and overkill clamping, rejected ranged attacks, and forced at least one reflected damage.

The existing shared pipeline now uses Combat eligibility helpers. Resolved physical/ranged attacks carry a weapon-hit marker; environmental/manual damage without that marker does not qualify. Direct Fireball hits qualify as spells. Secondary/quiet events never qualify. There is no duplicated bow, melee, or spell restoration implementation.

Actor.receive invokes a new post-hit receiver hook after mitigation, actual-damage clamping, damage application, and the attacker's existing post-hit handling, including lethal hits. Player reflection uses that hook instead of the incoming filter. Fully ward-absorbed successful hits return without resource effects, reflection, or recharge. Reflection carries the defender's stable character/owner identity, bypasses a second Combat.resolve armor/crit roll, has no artificial minimum, and is marked secondary. Normal damage reception and existing kill attribution remain in use.

## Rules and source decisions

Installed `ds2_source/ds2_reference/rules.skrit`, lines 1730–1767, explicitly checks melee, ranged, or spell weapons and applies:

`resource = min(maximum, resource + flat_per_hit + steal_percent / 100 * effective_damage)`

Lines 1769–1818 permit melee/ranged weapon reflection (including the attacker-as-weapon case), multiply applied damage by reflect percent, and call DamageGo directly with an invalid attacking weapon to prevent recursive weapon effects. Curse preserves attribution explicitly through its secondary marker instead of erasing ownership.

Owner approved on this task: percentage restoration and reflection use actual post-mitigation health damage excluding overkill; direct Fireball restoration is restored; DoT/secondary restoration and recursive reflection are excluded. Reflection does not grant restoration. The separate source reflection-to-self and aura mechanics are outside these five existing modifiers.

Each qualifying direct victim receives one post-hit event, including direct area weapon/spell victims; periodic burns and secondary events do not repeat rewards. Fireball's actual Projectile._hit and bow's CompanionArrow._hit_enemy are exercised, not just tooltips. Current direct-spell recognition is Fireball, the implemented direct spell; future spells need explicit eligibility integration, not blanket elemental-damage eligibility. Fire powers/environmental fire are not automatically treated as spell hits.

## Verification

New `--selftest --only=equipmenthits` executes real Combat.resolve/Actor.receive with actual resource assertions: normal/critical hits; miss/block/zero; quiet and secondary events; direct Fireball and burn exclusion; real arrow ownership after selection changes; multiple victims; separate Hero/Cutter effects; resource caps and fractional amounts; ranged and melee reflection; ward and full absorption; tiny reflection; spell rejection; two reflective characters; overkill/killing blows; reflected kill character/owner attribution; unique modifiers; stacking pieces; JSON CharacterState equipment reload; melee/bow equipment changes; death/revival; immediate unequip.

Existing `ds2items` helper fixtures now identify weapon events explicitly; its old “spells” exclusion label is corrected to “unclassified fire,” with actual direct Fireball covered in the new regression. No avoidance, zero-damage, reflection, or resource-cap assertion was removed.

Executed:

- Final focused `equipmenthits`: headless pass, clean log; rendered run pass. No manual screenshot review or road traversal is claimed.
- `ds2items`, `ds2combat`, `fireballframes`, `savepolicy`: pass.
- Full default self-test: pass via `tools/ci_check_selftest.py`; exit-time ObjectDB warnings remain. This default dispatcher does not run every named focused suite.
- `livepowers`: assertions pass, but exit reports six ObjectDB instances and three resources still in use. This is **not** a strict clean pass. This task has not independently established whether that teardown defect predates the change.

The sandboxed engine initially crashed at startup; tests above used the approved outside-sandbox engine execution. An initial invocation opened the menu rather than tests and was stopped; verification uses `res://game/main.tscn` explicitly. All runs used developer arguments and SavePolicy isolation; no production save was modified. Equipment persistence checks use an in-memory JSON round trip, not a production disk save.

## Remaining acceptance limitations

No new UI or feedback presentation was introduced. Broader road traversal, six simultaneous live-character combat, native resolution/scale screenshots, and unrelated item mechanics are not certified here. The resource teardown diagnostic in `livepowers` remains unresolved. Existing uncommitted objective-assistance, floating-text, and catalogue-report work was preserved and is outside this task's commit. Do not mark READY_TO_PLAYER_TEST=yes from these results.
