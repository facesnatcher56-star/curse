# Equipment integration candidate

Branch `integration/ds2-equipment-complete`, based on `main` `0b99fa2`. It combines four branches that each passed CI alone:

| Merge | Source commit | Contents |
| :--- | :--- | :--- |
| 1 | `603719e` (`integration/item-lab-movement-ui`) | Item Test Lab, ground-click movement priority, UI click protection |
| 2 | `29dcc57` (`codex/ds2-equipment-requirements`) | DS2 equipment requirements enforced on the real equip path |
| 3 | `4acba4a` (`agents/claude-ds2-elements`) | Ice, lightning and death damage and resistance, 45 affixes |
| 4 | `eb79bd1` (`agents/gemini-ds2-effect-tests`) | Equipment effect tests and the coverage manifest |

None of the four merges had a textual conflict. The combination still needed these changes, because the branches were written against `main` and
know nothing of each other:

- **Item Test Lab reporting** (`lab_combat_log.gd`, `lab_stats_readout.gd`): the Lab labelled every hit Physical, Fire or Ranged and read only
  fire damage and resistance. It now names ICE / LIGHTNING / DEATH typed hits, lists each added element of a weapon hit once
  (`[incl. added 14.0 Ice, ...]`) and shows all four elements in the stats readout.
- **Coverage manifest** (`tools/generate_ds2_effect_manifest.py`, regenerated JSON, `docs/DS2_EFFECT_COVERAGE_VERIFICATION.md`,
  `tools/test_ds2_effect_coverage.py`): written against `main`, it still called the six elemental alterations and the OR / AND / passive-rank /
  uber-level / attribute requirement patterns unsupported. Both are implemented in the combined build, so they are now `supported` (34 supported,
  23 unsupported, 1 unresolved). Mixed comma/pipe requirements stay unsupported and fail closed; `alter_generic` stays unresolved.
- **Cross-feature suite** `equipmentintegration` (`game/dev/suites/equipment_integration_tests.gd`): see below.
- **CI** (`.github/workflows/selftest.yml`, `tools/ci_check_selftest.py`): the monolithic self-test does not run `ds2items`, `inventoryequip`,
  `uiaudit` and most other `--only` suites, so CI now runs a list of them plus the Python coverage validation. The checker ignores only the
  engine's resource-leak messages printed after `SELFTEST done`.

## Cross-feature checks (`--only=equipmentintegration`)

- **A, requirements plus elements.** For ice, lightning and death: a level-1 hero is refused an elemental sword and ring (equip and bag-equip
  both return nothing, the reason text names Melee), an ineligible item in the bag adds no damage or resistance, the item equips at exactly the
  level its requirement needs (and not one level earlier), its element reaches `Combat.resolve` once and alone, matching target resistance halves
  only that part, typed incoming damage is cut by the ring's own resistance only, and unequipping restores zero.
- **B, Item Test Lab.** The Lab panel's Equip button is driven with a level-84 ice longsword: refused with the real requirement text at hero level 1,
  accepted after the Lab's own level control raises the real hero level. The Lab has no override control (none is searched for in the scene).
- **C, Lab combat.** Real dummy hits: physical plus one element equals the dummy's health loss, 50% and -100% dummy resistance, a pure typed hit,
  a four-element weapon without double counting, the combat log naming each element exactly once, and the stats readout listing all of them.
- **D, movement and combat.** Equipping mid-swing updates stats at once; a ground click then cancels the swing before its hit and clears every lock;
  unequipping on the move keeps the destination; a landed hit counts the element once and the recovery is cancelled by the next click. The
  existing `movepriority`, `uiblock`, `camera`, `knockdown` suites cover stun, UI clicks and the rest.
- **E, integrity.** Fire stays correct beside the new elements, rings stack per element, repeated `refresh()` does not accumulate, replacing a weapon
  swaps rather than adds, everything removed restores the baseline, items survive a JSON save with mods and requirement, and the elemental
  affix families are registered exactly once (12 added and 5 resistance tiers per element).

The suite was mutation-checked: disabling the requirement gate and the ice-resistance wiring made 32 of its checks fail.

## Known limitations

- `herodown` and `characterui` fail standalone with three failures each, identically on unmodified `main` `0b99fa2`. They are excluded from the
  CI list and are not caused by this integration.
- `data/affixes/life_steal_5/6` and `life_per_hit_5/6` are identical duplicate rows already on `main`; the registration check is scoped to the
  elemental families.
- `tools/test_power_audio_analysis.py` needs `scipy`, which is not installed on the local machine; CI does not run it.
- Elemental statuses (chill, shock, curse) and the Survival passive's ice and lightning resistance are not implemented (see
  `docs/ELEMENTAL_EQUIPMENT_VERIFICATION.md`).
- The Lab combat log reports `added_elements` amounts after resistance and before crit, armour and level gap, as `Combat.resolve` records them.
- No manual GUI playtest or screenshot inspection of the integrated build has been done; checks are automated and headless.

## Owner playtest fixes: dropdown click-through and ultrawide layout

- **Root cause.** An OptionButton's list is an embedded sub-window. It consumes the press and release that choose an entry or dismiss it, so
  `Player._input` never saw them, and `gui_get_hovered_control()` is null while the pointer is over the list. The hero polls
  `Input.is_action_just_pressed("click")`, which ignores that consumption, so the click was read as open terrain.
- **Fix.** `Player` latches the click from the root window's `window_input` signal (it sees every event before sub-window routing) and treats any
  visible `Popup` as interface, so opening, choosing and dismissing never move the hero. The latch clears on release; the next press on terrain
  moves at once. No timer or lockout.
- **Layout.** The Lab positioned its right dock with window pixels, but the project stretches a scaled canvas (3440x1440 is a 1720x720 canvas).
  The dock is now anchored to the canvas right edge, panels sit below the boss bar, party frame and top bar, the dock height is shared between
  Character Stats and Combat Log above the HUD bars, and the overlay scales down only when the canvas is smaller than 1080x730 (a large interface
  scale on a small window).
- **Tests.** `popupclick` (real events through `Input.parse_input_event`, an OptionButton, dismissal, the next ground click), `itemlabdropdowns`
  (the Lab's five dropdowns, attack cancellation afterwards) and `itemlablayout` (five window sizes including 3440x1440, interface scale 0.5 / 1.0 / 1.5).
  Real-window evidence: `--labsizes=1920x1080,3440x1440 --labdir=<dir>` captures the Lab and drives a dropdown with injected pointer events.
