# Task 2: Gold Find and Magic Find

## Evidence and decisions

Baseline: `0888b03f881fe5a4385a7936815db5e3b0e7275f`.

Original installed DS2 `Resources/Logic.ds2res`, extracted with
`tools/ds2_dump.py`, provides `pcontent.skrit`, function
`calc_modifier_count` (lines 282–327). For ordinary generated equipment its
ordered checks are `roll <= .40 * (1 + MF/100)` for one modifier, then
`roll <= .60 * (1 + MF/100)` for two, otherwise zero. These are not three
normalized weights. At MF 0 this is 40% plain / 40% one / 20% two; at MF 100
it is 0% / 80% / 20%; at MF 150 the first check always wins. This corrects
Curse's previous unsupported 50% / 30% / 20% ordinary-item split.

`ds2_source/ds2_reference/pcontent_macros.gas`, monster tier macros, applies
`#magic_find` to rare/unique/set entries. Preserve their relative weights,
eligibility windows, gold and potion entries, and existing world multiplier.
`ds2_source/ds2_catalog_source/pcontent.gas` defines Gold Find through
`alter_gold_dropped` and Magic Find through `alter_magic_find_chance`;
the importer already preserves their magnitudes. Human racial MF remains
the existing 10 percentage points from `heroes_ds2.gas`.

The inspected source does **not** establish DS2's runtime party aggregation,
Gold Find rounding, or modifier ownership for delayed/summoned kills.
`generator_object_pcontent.skrit` passes a catalyst actor into engine code;
that alone does not prove a killer-only rule. The debug generator and gold
collection/share scripts are not proof of the runtime find formula.

Owner-approved **Curse-specific rules**, not verified DS2 behavior:

- Independently average MF and GF over living deployed character bodies.
  Persistent reserves and dead members do not contribute. Empty party: zero.
- Snapshot both bonuses once when death rewards begin; selection, killer,
  controller subgroup and owner identity do not substitute another member's
  stats. No changes to combat attribution, ownership or XP calculation.
- GF changes gold amount only: `max(1, round(base_gold * (1 + GF/100)))`.
  The base is the unrounded existing gold roll; round once to nearest integer.
- Existing find-aware monster/named/miniboss/climax equipment uses the average.
  Fixed quest payments and town quest equipment keep their existing behavior.
  Containers retain their previous explicit 50/30/20 split and do not gain find.

Explicit normal/magic1/magic2 generation remains forced. Jewellery's existing
always-magical rule, rare affix counts, unique/set fallback, item levels and
slot eligibility remain unchanged. The source also says rares have four
modifiers; changing Curse's existing rare-count rule is outside this task.
No new summon system or network implementation was added.

## Audit and implementation

Previously GF was an imported equipment stat with no reward consumer. MF came
from the selected Hero-facing director reference; ordinary item generation
ignored MF entirely. Shared gold pickups already store final integer amounts.

`PartyManager.loot_bonuses()` now supplies the shared snapshot, using each
common character's current equipment-derived stats. `MonsterLoot` applies GF
only after selecting a gold outcome. Shared rarity-weight and ordinary
modifier-count helpers serve equipment generation. Death/drop guards prevent
duplicate reward callbacks; collection still uses the existing queued-deletion
guard. Equipment persistence remains `CharacterState`; no find cache or
parallel inventory/save model is introduced.

## Probabilities

Let `R` be the original rare+unique+set weight, `S` the original total, and
`m=MF/100`. The new total is `S + R*m`; each high-rarity weight is multiplied
by `1+m`, while all other weights are unchanged. GF does not appear here.

| Tier | MF | Gold outcome % | Rare+unique+set outcome % |
| --- | ---: | ---: | ---: |
| Weak | 0 | 14.0000 | 0.7500 |
| Weak | 100 | 13.8958 | 1.4888 |
| Normal | 0 | 15.0000 | 1.2500 |
| Normal | 100 | 14.8148 | 2.4691 |
| Strong | 0 | 18.0814 | 2.2602 |
| Strong | 100 | 17.6817 | 4.4204 |

The strong table already totals .9955, so normalize rather than pretending
its entries are percentages. MF's normalization can dilute gold probability;
**GF cannot**. The explicit rarity-weight formula itself is unchanged from
before this task; party aggregation changes which MF value feeds it.
Guaranteed REWARD's 70/15/15 entries all scale equally, so MF cancels there;
it still gives one item. Minibosses still give one item, not extra gold/items.

## Verification

The `find` suite uses actual loot generation with seed 271828: 100,000 rolls
per weak/normal/strong tier at MF 0 and 100, then the same six configurations
at GF 70 (1,200,000 total rolls). Every GF-paired outcome category is identical;
rarity frequencies must fall within six binomial standard deviations plus one.
Gold totals must match the 1.7 multiplier within bounds for both roundings.

| Tier | MF | Gold outcomes | High-rarity outcomes | Gold total GF0 | Gold total GF70 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Weak | 0 | 14126 | 778 | 423732 | 720369 |
| Weak | 100 | 13948 | 1473 | 421537 | 716622 |
| Normal | 0 | 14945 | 1245 | 1011824 | 1719978 |
| Normal | 100 | 14598 | 2397 | 985509 | 1675212 |
| Strong | 0 | 17841 | 2239 | 1664537 | 2829792 |
| Strong | 100 | 17656 | 4318 | 1651248 | 2807096 |

Deterministic assertions cover threshold boundaries/high MF, rounding/minimum,
two- and six-body averaging, dead/reserve exclusion, selection, real melee,
arrow, Fireball, burn and reflection kills, duplicate death/drop callbacks,
shared gold collection, JSON campaign reload, equipment reload/unequip,
guaranteed reward generation, container thresholds and equipment slot coverage.
The real arrow/spell fixtures switch control before impact; they invoke actual
impact handlers rather than waiting for physical projectile flight.

Verification uses `--selftest` isolation under SavePolicy, with persistence
disabled. No production save writes are required or authorized.
Automated checks do not establish visible road traversal, UI usability, or
overall integrated acceptance. No visual assets/layout were changed by Task 2.
Do not infer `READY_TO_PLAYER_TEST=yes` from this milestone.

Local verification (2026-10-12, Godot 4.8-dev2): full default self-test and
focused `find`, `equipmenthits`, `ds2combat`, `ds2items`, `classskills`, `loot`,
`questlogic`, `savepolicy` all passed `tools/ci_check_selftest.py`, with no
script errors or failed assertions. The full run reports 511 leaked ObjectDB
instances at shutdown; this warning is not resolved by Task 2. Local runs use
the current working tree, which also contains unrelated uncommitted objective
assist/floating-text changes; the pushed commit's Linux CI provides the clean
committed-tree regression check. CI outcome is reported separately after push.
