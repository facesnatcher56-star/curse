# Codex 6 — Wave 1 midgame equipment

## Pool audit

The baseline has 28 live base definitions. Ordinary monster item variants are selected from the monster-level window `level - 5 .. level + 1`; if a slot has no variant in that window, `Items.pick_base()` falls back to the nearest level. Counts below are distinct base definitions in each slot, ordered Weapon / Body / Ring / Shield / Helm / Gloves / Boots / Amulet.

| Monster level | Before | After |
| ---: | :--- | :--- |
| 30 | 3 / 3 / 1 / 1 / 2 / 1 / 1 / 1 | 3 / 4 / 2 / 1 / 3 / 1 / 1 / 1 |
| 35 | 3 / 3 / 1 / **0 / 0 / 1 / 0** / 1 | 3 / 4 / 1 / 1 / 1 / 1 / 1 / 2 |
| 40 | 3 / 2 / **0** / 1 / 2 / 1 / 1 / 1 | 3 / 2 / 1 / 2 / 3 / 2 / 2 / 1 |
| 45 | 3 / 3 / 1 / 1 / 1 / 1 / 1 / 1 | 3 / 3 / 2 / 1 / 1 / 2 / 1 / 1 |
| 50 | 4 / 3 / 1 / **0** / 1 / **0** / 1 / 1 | 4 / 4 / 2 / 1 / 2 / 1 / 1 / 2 |

The zeroes were real nearest-level fallback cases. At the five audited levels, all eight slots now have an in-window option. Slots that already had several choices remain modest; this is a coverage repair, not a full DS2 catalogue import. `python tools/equipment_pool_report.py` reproduces the after counts and checks every audited slot is covered.

## Additions and provenance

All nine definitions use normal-category, player-content-allowed rows from `data/reference/ds2_equipment_catalog.json`. Their exact five item levels and catalog requirements are preserved. Blank requirements on Heater Shield and Studded Gloves are source values, not omitted data. Requirements that are not implemented in runtime are not introduced by this batch.

| Live ID | DS2 catalog ID | Source | Runtime art alias |
| :--- | :--- | :--- | :--- |
| `chain_mail` | `amr_bdy_ftr_chain` | `amr_body_fighter.gas` | Mail Hauberk model/icon |
| `heater_shield` | `amr_shd_htr` | `amr_shield.gas` | Kite Shield model/icon |
| `dragon_helm` | `amr_hlm_nmg_dragon` | `amr_helm_nmage.gas` | Iron Helm model/icon |
| `carved_cap` | `amr_hlm_rng_carved` | `amr_helm_ranger.gas` | Leather Cap model/icon |
| `studded_gloves` | `amr_glv_ftr_studded` | `amr_gloves_fighter.gas` | Iron Gauntlets model/icon |
| `sorcerer_boots` | `amr_bot_cmg_sorcerer` | `amr_boot_cmage.gas` | Leather Boots model/icon |
| `gold_ring` | `ring_02` | `trs_ring.gas` | Iron Band model/icon |
| `jeweled_ring` | `ring_03` | `trs_ring.gas` | Signet model/icon |
| `gold_amulet` | `amulet_01` | `trs_amulet.gas` | Charm model/icon |

The aliases use existing Curse art with the correct equipment silhouette. They are not DS2 source art, and no existing art was overwritten. Existing item IDs and drop, rarity, magic-find, and affix formulas are unchanged.

## Verification

- `python tools/write_item_defs.py` regenerated 37 item resources; a second regeneration must leave the intended definitions unchanged.
- `python tools/equipment_pool_report.py` validates coverage and asset paths.
- `tools/equipment_pool_sample.gd` samples one real `Items.pick_base()` result per slot at each of levels 30, 35, 40, 45 and 50; it checks the selected level stays in-window, paths resolve, item save/load retains the ID and level, and the existing `longsword` ID resolves.
- Godot suites run for loot, source-backed item rules, equip/unequip, loot presentation, icon loading, Item Lab catalog/dropdowns, equipment integration and loot rewards. See the run summary from this branch for the exact outcomes.
- Headless Item Lab layout checks passed at 1280×720, 1600×900, 1920×1080, 2560×1440 and 3440×1440 with 0.5×, 1.0× and 1.5× interface multipliers. The Item Lab dropdown interaction and UI audit suites also passed.
- I inspected the existing icon aliases directly; each depicts the right equipment silhouette and no icon art changed. Gameplay screenshot review is still a gap: the GUI launch exited before exposing a window to capture, CUA reported no open apps, and headless `--labsizes` returned a null render texture. The bounds and interaction suites are not visual sign-off; this branch has no claimed gameplay screenshot pass across the resolution/scale matrix.
