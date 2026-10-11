# UI consistency audit — 2026-10-11

Owner request: fix inconsistent passive requirements and inspect related UI for the same local-only
implementation mistakes. Standing acceptance rules are in CLAUDE.md; this records actual scope, not
a guarantee that every game screen and every possible state is flawless.

## Fixed

- Active powers and passives use the same requirement-line formatter: required/current class levels,
  prerequisite ranks and available points are green when met, red when unmet. Passives list all
  requirements rather than only the first blocker. Unmet chart tiers are red; prerequisite nodes pulse.
  Rank zero never claims a current learned effect; capped ranks show no fictitious next rank.
  Existing purchase validation remains authoritative, including staged ranks.
- Removed the duplicate town resource strip in both layouts. The underlying economy is unchanged.
  Town overlays yield to character/skill screens, which explicitly own modal state and foreground order.
  Opening town services replaces a character/skill screen rather than stacking them.
- Character statistics wrap within their column rather than spilling into the backpack.
- Inventory move/drag cancellation restores the item without closing the entire window.
- Equipment requirements use consistent red feedback in inventory, shop, worn-item and ground-loot cards,
  including cards with comparison disabled. Tooltip descendants remain mouse-transparent.
- Take Aim's tooltip uses the actual arrow damage range, never a random damage roll. Actual combat still rolls damage.
- I/C dock buttons open the existing combined character/inventory screen; J opens the town chronicle and
  is disabled outside the town scene. Potion clicks do not drink while a modal has paused play.
- Owner clarified backpack item rotation, not 3D preview rotation. Added rebindable R/Y rotation for
  hovered/focused items, controller placement and mouse dragging. Invalid placements do not mutate items;
  cancel restores orientation; sort keeps orientation. UI metadata is excluded from item identity.

## Verified

`--only=uiaudit` instantiates TownScene with its real HUD, without the road (layout does not require
combat encounters). Persistence is disabled. It checks every passive in all three current trees at
unmet class levels, mixed met/unmet prerequisites, staged versus learned state, point exhaustion,
rank cap, locked purchase rejection, modal replacement, cancellation, utility buttons, stable tooltip
damage, and settings bounds/controller focus.

Rendered tests run on monitor two. Engine-generated screenshots were inspected for empty/populated
inventory, Melee/Ranged/Combat skill tabs, passive requirements, trader, stash, job board, chronicle,
pause and all four settings tabs. Temporary files use `curse_audit_*.png`.

Related focused checks: `powerui`, `inventorygrid`, `inventoryrotate`, `inventoryequip`, `lootui`,
and `padmenus`. Rendered `inventorygrid` exercises native mouse dragging and the second ring slot;
rendered `inventoryrotate` exercises rotate-during-drag and escape cancellation. Controller checks
inject engine input events; this is not a claim of a human hardware-controller playthrough.

## Limits and follow-ups

- This is not a full game regression run or an exhaustive resolution/UI-scale matrix. Main menu and
  death/respawn screens were not visually revalidated. Settings changes were not saved during the audit.
- Some headless regressions report exit-time resource/RID leaks despite passing assertions; rendered
  audit/rotation runs did not report script errors. These checks do not certify leak-free shutdown.
- The earlier broad `townscene` test reported two shop-purchase assertions; this audit checks shop
  layout/navigation, not that purchase regression. Do not describe the economy as fully verified.
- Square item badges remain small inside multi-cell frames; dedicated tall inventory artwork is not
  implemented. Backpack layout/orientation is session-only under the existing end-run stash flow.
- Unsupported powers/passives retain their existing explicit implementation warnings. This audit does
  not implement missing gameplay effects or redesign the stash/companion inventories.
- Native drag cancellation uses Godot's documented
  [Viewport.gui_cancel_drag](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-gui-cancel-drag).
