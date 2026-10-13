# Loot at a glance: upgrade and locked marks on drops

Branch `agents/claude-loot-rewards`, based on `main` `068cefa`.

## Audit (what the game already did)

- **Drops** (`MonsterLoot.roll`, `Items.item_of_kind`): DS2's own common-monster tables (`pcontent_macros.gas`) per tier. A measured run of 20,000 level-18
  "normal" kills gave 1,870 gear drops (9.4%): 517 plain, 1,072 magic, 172 rare, 54 unique, 55 set. A miniboss always drops (about 22% rare or better).
- **Item level**: the item level is a base's variant inside a window around the monster's level (normal tier: -5..+1; rares -4..+2; uniques and sets from
  a wider authored window). Measured: no plain, magic or rare drop was ever more than 12 below or 7 above the monster.
- **Uniques** come from `UniqueDb` inside their window, falling back to a rare when none is authored there.
- **Containers** (`Destructible._drop_loot`): normal / one-modifier / two-modifier pieces at the local drop level.
- **Pickup**: click the item or its name (or the use key). An empty slot is filled; anything else goes to the bag. A full bag leaves the item on the
  ground ("Inventory full"); it is never deleted. `loot_generated` stops a corpse rolling twice.
- **Comparison**: the item card (hover or controller focus) shows the requirement, every stat difference against what is worn, and what walking over it does.
- **Usability**: 80-90% of drops at the hero's level are wearable (class gear is picked evenly across slots), but nothing told the player which.

## The deficiency

The only way to learn whether a drop is a step up, or cannot be worn yet, was to hover each name plate and read the comparison. After a fight with
several drops (or a miniboss pile) every plate looked the same apart from rarity colour. Nothing on the ground or at pickup said "better than yours", and
an upgrade that went to the bag (anything for an occupied slot) was silent apart from the item's name.

## What changed

- **`LootAppraisal`** (`game/items/loot_appraisal.gd`): one verdict per item for the current hero, built on the existing requirement check and `Items.compare`.
  - `LOCKED`: the hero does not meet its requirements.
  - `UPGRADE`: wearable and either walking over it wears it (empty slot), or the card's own comparison is better on balance (a ring is checked against both
    ring places).
  - `EVEN`: wearable, equal or worse (including a shield that would collide with a two-handed weapon).
- **Name plates**: a green arrow marks an upgrade and a red cross marks a locked piece (drawn as shapes, no font needed). The locked name is dimmed. Plates
  of plain "even" drops are unchanged. Verdicts are recomputed at most every 0.4 s, not every frame.
- **Item card** (the "Walk over it" line): "it goes in the bag (better than what you wear)" in green, or "(you cannot wear it yet)" in red.
- **Pickup**: an upgrade that goes to the bag shows "Upgrade in your bag" over the hero, in green.
- Nothing about drops, odds, requirements or what pickup does changed. Gear is still never swapped in without the player asking.

## Tests

- `--only=lootappraisal`: verdicts (locked, upgrade, even, empty slot, rings, shield vs two-handed), plates on the real HUD carry the verdict and have room for
  the mark, the card lines, no plate overlap, pickup of an upgrade and a locked piece, a second pickup of the same drop, a full bag leaving the drop on the
  ground, then taking it once there is room. Mutation check: a verdict that never returns `LOCKED` fails 3 of its checks.
- `--only=lootrewards`: a real kill leaves exactly one reward within the monster's item-level window, its plate verdict equals the appraisal, it survives
  `to_save`/`from_save`, a second blow on the corpse drops nothing, and the seeded distributions above (drop rate, rarity mix, level window, miniboss rewards).
- Both suites are in the full self-test and in CI.
- A windowed run with `LOOT_SHOT_DIR=<dir>` saves a screenshot of the real HUD with an upgrade, an even and a locked drop (checked at 1920x1080).

## Known limitations

- No sound for drops: the project has no loot audio and everything in `Sfx` is a recorded file.
- The verdict is a net of the card's comparison lines (each better line +1, each worse -1), not a damage-per-second model.
- Only a 1920x1080 window was captured; other resolutions, interface scales and controller focus were not visually inspected.
- At hero level 35 the base pool only holds five equipment slots (the catalogue has few high-level bases), so most late drops come from few slots. That is a
  content gap in the item data, not a drop-table issue.
