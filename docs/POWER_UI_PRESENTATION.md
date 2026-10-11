# Power buttons and specialty chart

Owner-approved presentation pass, 2026-10-11. DS2's original manual (pp. 16-19) and
`character_skills_tab.gas` / `skills_melee_tab.gas` are the reference: specialization
tabs, a separate power row, connected icon nodes, small rank numbers, hover details,
and dark power icons revealing their artwork as they recover. No original art is shipped.

## Implementation

- `game/ui/skill_tree_view.gd`: tabs, contextual hover/focus card, staged ranks,
  Confirm/Reset/Back. Existing purchase/save/unlock rules are unchanged.
- `game/ui/skill_tree_chart.gd`: five class-level tiers, prerequisite paths from
  `PassiveDef.prereqs`, and focusable icon buttons. Skipped-tier paths route around
  intermediate nodes so they don't imply false dependencies. Clicking/accepting an
  icon stages a rank; its small minus button removes an unconfirmed rank.
- `game/ui/power_button_visual.gd`: one renderer for the hotbar and portrait cards.
  Spent icons are dark; artwork reveals upward with recharge; ready has a restrained
  amber rim; armed has a persistent double rim with a moving glint. Unavailable powers
  remain dark even with a full charge. No percentage text or duplicate portrait charge bar.
- Arming is read from the actual Brutal Attack, Staggering Blow and Cutter controllers.
  Recharge is read from existing damage-budget state, not a second UI timer. Instant
  powers return directly to their recharge presentation when spent.

The upward reveal and exact rim animation are Curse's approved approximation, not
a claim of frame-perfect DS2 animation matching. Existing Curse art is reused;
passive illustrations are thematic stand-ins and unillustrated powers use the existing
generic power icon. A `C` badge distinguishes Cutter's always-available Take Aim from
the hero's passive-unlocked power ranks. No new mechanics or missing skills were added.

## Verification

Focused `--only=powerui` tests cover tabs, prerequisite paths, controller focus and
directional navigation, contextual details, staged/undo/confirm purchases, shared
recharge state and real hero/companion arming. The visible variant writes screenshots
to `%TEMP%/curse_ui_*.png` and the harness forces monitor two. Developer sessions do
not write the production save. Related regressions: `skilltree`, `powers`, `hotbar`,
`padmenus`. Full suite is intentionally not required for this presentation-only change.

Result: `powerui` (headless and visible monitor two), `skilltree`, `powers`, `hotbar`,
`padmenus` and `savepolicy` passed. Final visible stderr was empty. Inspected the
rendered melee/ranged/combat charts, focus detail card, half-charge and armed hero
icons, and half-charge Cutter icons in both HUD locations. The hotbar suite had two
stale fixtures: its supposedly benched skill was already equipped, and it tested a
dodge click while the unrelated picker was still open. Corrected the fixtures only;
no assignment or dodge gameplay behavior changed. No full-suite run, commit or push.
