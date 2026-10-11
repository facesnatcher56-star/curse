# Worn-gold UI theme

The owner's ornate fantasy UI reference is the presentation target: tarnished carved gold,
dark recessed controls, aged parchment for the specialty chart, and live icon-driven content.
The game remains grounded and weathered, as required by ART_DIRECTION.md.

## Assets and implementation

- `assets/ui/ornate/` contains the project-owned generated materials, transparent compass
  and crest, icon frame, and high-resolution parchment detail. The built-in image-generation
  tool created the artwork; the exact prompts are recorded in `prompts.json` alongside it.
- `source/` retains the untouched original images and is excluded from Godot imports.
  `tools/prepare_ornate_ui.gd` rebuilds the runtime textures from those sources. It only
  normalizes pixel dimensions and crops the parchment interior; it does not regenerate art.
- Nine-slice materials retain four physical pixels per logical pixel. UiTheme caches an
  ImageTexture with a logical-size override, preserving existing trim/margin geometry
  without downsampling away the high-DPI detail. Metal/button material repeats through
  stretchable regions instead of smearing grain across tall tooltips or wide HUD plates.
  The inventory portrait renders at its actual displayed pixel dimensions.
- UiTheme owns shared texture styles, colors, focus feedback and responsive window fitting.
  Corners use nine-slice textures; the crest is separate so container layout cannot stretch it.
  Modal windows fit the viewport and reserve space for the bottom hotbar, including at the
  maximum interface-size setting. Decoration never captures input.
- Skills use dark ink on parchment; item cards and requirement details remain cream on dark
  metal. Unmet requirements remain red, met requirements green. This is not a skill purchase.
- Party vitals, real levels, minimap content, skill paths, power charge overlays and inventory
  rotation stay data-driven. Existing ability icons and OFL fonts are retained.

Do not restore the removed resource strip, render fake consumables, bake gameplay values
into artwork, or introduce another independent theme system. Ask the owner when uncertain.

## Verification tools

`--selftest --only=theme` follows `GameSettings.RESOLUTIONS`: currently 1280x720, 1600x900,
1920x1080 and 2560x1440, with interface-size multipliers 0.5, 1.0 and 1.5. Visible runs use monitor 2
for 720p/1080p, and monitor 1 for native 1440p, as explicitly authorized by the owner.
It captures HUD, inventory, skills, hovered tooltips, stash, board, chronicle, trader,
all four settings tabs, pause and death at each combination; loading is captured separately.
`uiaudit`, `inventoryrotate`, `inventorygrid`, `inventoryequip`, `powerui`, `padmenus`,
`lootui` and `minimapfog` cover related interactions. These are focused checks, not a full
gameplay regression or proof that every possible tooltip/resolution combination is perfect.

### Verified on 2026-10-11

The visible nine-case theme matrix completed at all three resolutions and all three scale
settings, with 1440p on monitor 1 and 720p/1080p on monitor 2. Inventory, skills, town-service
and settings bounds checks passed. Screenshots were reviewed for the complete HUD, empty
and populated inventory, rotated items, locked skills/passive requirements, town services,
menus, settings, loading and death presentation.

The eight focused suites listed above passed. A final visible UI audit and mouse-drag
inventory-rotation run also passed with empty stderr. The theme matrix still reports
472 ObjectDB instances leaked at process exit; this is an unresolved test-shutdown warning,
not a clean-exit claim. No full gameplay regression was performed.

Representative actual game captures are saved in `docs/screenshots/theme-{hud,inventory,skills}.png`.

### Hover and tooltip follow-up

Native TooltipPanel popups, item cards and skill details share `UiTheme.tooltip_box()`;
the drawn hotbar tooltip uses that same material. Button hover gently brightens the frame
without changing padding; item tiles, item names and hotbar slots use restrained warm
feedback. Rarity/requirement colors and power-charge states keep their meanings.

Owner-supplied ability icons should not acquire a second decorative frame: preserve the
source artwork, remove baked outside trim when it clashes with the shared icon bezel,
and check the result in the hotbar, party power cell and skill chart at actual icon sizes.

The nine-case visible matrix also exercises actual item/skill hover, checks popup bounds,
and captures item, skill and hotbar tooltips at every resolution/scale combination.
Town tracker/help draws behind combat tooltips so text cannot overlay their contents.
Every future visual change must repeat this capture-and-inspect workflow and related
interaction tests, as required by CLAUDE.md; record any untested cases explicitly.
