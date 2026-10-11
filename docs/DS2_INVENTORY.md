# DS2 inventory integration

Source: installed Logic.ds2res, extracted to a temporary research folder with `tools/ds2_dump.py`.
No original DS2 interface textures or icons were imported.

Verified definitions:

- `heroes_ds2.gas`: `grid_width = 5`, `grid_height = 13`.
- `wpn_bases.gas`: sword 1x3, two-handed sword 1x4; hammer/axe/mace 1x3;
  two-handed hammer/axe 2x3; staff 1x4; dagger/club/thrown 1x2; crossbow 2x3;
  bow base 1x4 (source comment says individual bows may override to 1x3).
- `amr_bases.gas`: body/helm/shield 2x2, gloves/boots 1x2. Jewellery uses one cell.
- `party_stash.gas`: grid cells, an auto-arrange control, 14 stash rows and a 256px-wide grid with 32px cells (8 columns).

## Implemented first pass

Hero backpack uses the source-backed 5x13 grid and the footprints applicable to our current item bases.
`ItemDef.inventory_size` permits exact per-base overrides as additional weapon families are imported.
The old twelve-item cap and automatic lowest-rarity deletion are removed. Pickup failure leaves the drop on the ground.
Equipment/unequip operations check the complete resulting bag first, including two-handed/shield conflicts.
Saved item definitions/affixes and equipment requirements remain unchanged.

`game/inventory_grid.gd` owns packing and bounds/overlap checks; `PlayerStats` owns atomic item transfers;
`inventory_grid_view.gd` and `inventory_grid_tile.gd` own presentation, dragging and controller placement.
Character view retains its paper doll, statistics and hover comparison cards, but replaces named bag cards with sized icons.
Right/double-click or controller confirm equips. Dragging rearranges items or transfers to/from the paper doll.
Dragging a ring onto the second ring slot targets that slot specifically. Controller Select picks up an icon,
directions move the placement outline, Confirm places, Cancel leaves the original position unchanged.
Sort packs largest items first; a failed sort never replaces the existing arrangement.

Owner-requested rotation (2026-10-11): R over/focused on a backpack item or during mouse drag;
controller Y rotates the focused item or selected placement outline. Both are rebindable under Controls.
The footprint and artwork turn together. Rotation/drop/place checks bounds and other items before committing;
cancel restores position and orientation. Sorting preserves orientation. This is an explicit owner feature,
not a claim that original DS2 rotation behavior has been verified.

## Explicit remaining differences

- This is the hero-backpack integration, not a claim that the entire DS2 inventory ecosystem is complete.
- Existing town/end-expedition bag-to-stash flow remains. Bag positions are session-only, not saved item properties.
  `bag_cell` and `bag_rotated` are stripped at equipment/stash boundaries and ignored by existing item serialization;
  no save migration is required.
- Stash remains our existing card interface, not DS2's 8x14 vault. Its destructive twelve-item eviction is removed;
  storage is uncapped for safety until a paged vault and overflow migration are implemented.
- Cutter still has fixed bow gear, not a separately managed DS2 party backpack/equipment screen.
- Potions remain the existing resource counters rather than grid items; no stacking rules were invented.
- Icons remain existing square artwork fitted inside sized frames; dedicated tall inventory renders remain a presentation improvement.
- Exact original auto-arrange algorithm is compiled/engine-side; largest-first packing is our implementation, not claimed identical.

## Verification

Focused `inventorygrid` checks geometric capacity, failed pickup preservation, full-bag unequip, atomic larger-item swaps,
overlap/bounds, sort, controller placement/cancel and stash preservation. Rendered mode additionally exercises real mouse
dragging to free cells and the second ring equipment slot. Headless cursor-position limitations use direct drop-coordinate checks.
Existing `inventoryequip`, `lootui`, `padmenus` and `townstate` are related regressions.
Visible tests run on monitor two and save a reproducible temporary `curse_ds2_inventory.png` screenshot.
`inventoryrotate` additionally checks footprint rotation, overlap/edge refusal, controller rotate/confirm/cancel,
sort and identity preservation. Rendered mode tests rotation during a native mouse drag and escape cancellation,
with `curse_inventory_rotated.png` as its screenshot. See [UI audit](UI_AUDIT.md) for full-town window checks.
