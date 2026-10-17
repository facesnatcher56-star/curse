# Worn-gold UI theme

The owner's ornate fantasy UI reference is the presentation target: tarnished carved gold,
dark recessed controls, aged parchment for the specialty chart, and live icon-driven content.
The overall art direction is not decided yet (see ART_DIRECTION.md); the UI rules below still apply.

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

### Texture repeat and text clarity (#49, 2026-10-15)

- Framed plates stretch instead of tiling. Tiling repeated the metal plate's midpoint studs
  and edge knotwork along long bars and windows. `assets/ui/ornate/metal_panel.png` is derived
  from `metal.png` by `tools/make_panel_art.py`: the four ornate corners are kept, every rail is
  a uniform profile from a stud-free stretch, and the centre is a seamless texture-bombed leather
  fill with large-scale grime. Tooltips use the metal plate (`tooltip_box`), because the short button
  plate streaked when stretched into tall cards. Buttons keep `button.png`, stretched.
- The plate's nine-slice corner cell is 24 logical px (96 source px), the same margin HUD plates
  use. A larger margin let the corner filigree spill past its cell and stretch along the bar edge.
- Ornament layers, placed by layout and never stretched: `UiTheme.draw_stud` (bar corners and
  one stud per hotbar divider) and `UiTheme.draw_crest` (bar centre). Lane M's no-repeat rail and
  crest set can replace the art behind these helpers. Brackets around the hotbar and left button
  groups are not built yet.
- Label, Button, CheckBox and TooltipLabel share one 1 px drop shadow (`UiTheme._build`).
- Text A/B at 200% (`docs/screenshots/ui-texture/text-ab/`), measured by mean edge gradient on
  the character title: baseline 21.96; MSDF on both fonts 27.19 (edges stronger, glyphs slightly
  heavier); light hinting 21.96 (no measurable change); no hinting 21.49 (softer). MSDF is ON for
  CrimsonPro and Cinzel, as TD confirmed. Hinting is unchanged. At 1080p the character window,
  tooltip, skill tree, party frames and hotbar labels were checked for clipping with MSDF on: none found.
- The potion stack count sits in the flask slot's lower-right corner, clear of the 22 px flask art.
- `Control.scale`: at 1080p the window is not scaled (fit factor 1.0). At 720p with UI 1.5 it is
  shrunk, and the 200% crop shows smaller but not blurred text. A re-layout at 1.0 was not built.
- Verified at 1080p on screen 1 only (`--only=uitexture`): bottom bar and both ends, character
  window, item tooltip and party frames, before and after, in `docs/screenshots/ui-texture/`.
- The seven `--only=theme` headless failures (Tough Dragon Helm roll and hover-card fit at the
  64x64 headless viewport) reproduce with the original `UiTheme` in this checkout. CI never runs
  `--only=theme` (see `.github/workflows/selftest.yml`), so there is no CI result to compare.
- Known gaps: 1280x720, 1600x900 and 2560x1440 and the interface-scale matrix are not run: the
  owner's latest instruction is 1080p only, with higher resolutions later. The owner has not yet
  judged richness.

Do not restore the removed resource strip, render fake consumables, bake gameplay values
into artwork, or introduce another independent theme system. Ask the owner when uncertain.

## Visual verification tiers

Visual checks follow the risk-based policy in `docs/DEVELOPMENT_RULES.md`:

- Minor localized UI change: visually inspect the affected interaction at one representative resolution.
- Significant UI or layout change: inspect representative supported resolutions and the relevant
  interface-scale boundaries, including affected hover, focus and scroll behaviour.
- Global display, scaling or layout-system change: run the complete resolution and interface-scale matrix
  described below.
- Unrelated gameplay or backend change: no visual matrix requirement.

Screenshot inspection is required when visual appearance changes and a suitable display is available.
Deferred visual checks must be reported as known gaps, never marked verified. Automated bounds assertions
do not replace inspection.

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

### Enemy target readability and discipline notice — 2026-10-12

Owner-approved presentation mapping: ordinary enemies remain cream/red, strong
tier is blue, named/quest enemies and minibosses gold, boss flag red-orange. HP
and level alone never imply special status. Target plaque grows from 400×44 to
480×68, with 20-pixel heading, 18-pixel HP and 17-pixel level text, outlined
numbers, separate level/HP columns, and minimum physical-pixel sizing. Shared
formatting rounds both HP values upward and clamps current display to maximum.
Overhead enemy bars are wider/thicker and share status colors. No combat stats,
enemy names, spawns, or progression formulas change.

Target presentation fits between party cards and the opposite objective region;
paused menus hide it rather than exposing a half-covered name behind their crest.
The character-level toast sits below the target plaque. Discipline feedback
(`Melee increased to …`, etc.) now lasts five seconds, up from two, and follows
the existing member-aware event to appear above the earner, including Cutter,
not whichever member is selected. Character-level toast timing is unchanged.

Executed: classnotice (headless and visible; headless also checks inactive Cutter
attribution), uiaudit, padtarget and padmenus passed. The actual-road
`target_hud_check.gd` captures ordinary/strong/unique/boss and inventory states
at all four supported resolutions × scales 0.5/1/1.5. It asserts fractional HP,
status precedence, no HP/level-based promotion, name/HP fit, minimum numeric
size, and non-intercepting/menu-hidden target decoration. Captures were reviewed
iteratively; low-scale sizing and menu overlap were corrected after inspection.

The broader visible theme run completed all screen/hover/tooltip/focus cases,
but FAILED three physical-monitor-fit assertions: this session exposes only one
1080p display. 1440p images are rendered captures, NOT verified native 1440p
monitor viewing; monitor-two verification is unavailable in this session.
Not every broader theme capture was personally re-reviewed: changed target/HUD
states and selected surrounding menus were reviewed, not a full independent UI
recertification. Existing intro-log overlap at 720p/1.5, small-scale texture/text
softness, exit ObjectDB warnings and the separate Linux roll-shove assertion
remain acceptance gaps. No production save was used or written. Not player-test
readiness certification; these changes remain local until separately committed.
