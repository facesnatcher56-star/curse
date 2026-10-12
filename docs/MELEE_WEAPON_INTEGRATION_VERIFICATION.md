# Melee Weapon Expansion: Integration & Verification Report

**Task:** Task 3D — Integrate Six New Melee Weapons Into Curse  
**Branch:** `agents/gemini-melee-integration`  
**Repository:** `https://github.com/facesnatcher56-star/curse.git`  
**Main Baseline:** Commit `f32dcbc6ed9fe00470ddb45dca888a2538c418fd` (incorporating Codex's ranged modifiers)  
**Date:** October 12, 2026  
**Agent:** Gemini  

---

## 1. Executive Summary

This integration incorporates all six missing melee weapon categories created during Tasks 3A and 3B into Curse's live gameplay, inventory, character rig, and loot systems, safely integrated alongside Codex's completed ranged-equipment modifiers:

1. **One-Handed Axe** (`axe_1h`) — War Axe
2. **Mace** (`mace`) — Mace
3. **Club** (`club`) — Club
4. **Dagger** (`dagger`) — Dagger
5. **Two-Handed Battle Axe** (`axe_2h`) — Battle Axe
6. **Two-Handed Warhammer** (`hammer_2h`) — Warhammer

All integrations adhere strictly to verified Dungeon Siege II formulas and mechanics without experimental damage/speed multipliers or out-of-scope combat refactors. The original 19 base item definitions (including `short_bow.tres`, restored exactly to `main`), Codex's 20 ranged affixes, Biting Arrow, projectile snapshots, and unique/set definitions are 100% preserved.

---

## 2. Integrated Weapon Definitions

Each weapon definition resides in `res://data/items/<id>.tres` generated via `tools/write_item_defs.py`.

| Asset ID | Display Name | Slot | Item Type | Level Progression (5 Variants) | Base Stats | Grid Footprint | Stance Requirement | Hand Conflict | Affix Class |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| `axe_1h` | War Axe | 0 | `1h` | `[3, 15, 33, 52, 75]` | `{"damage": 1.0, "speed": 1.0}` | $1 \times 3$ (default) | None (`""`) | None | `fighter` |
| `mace` | Mace | 0 | `1h` | `[4, 18, 36, 55, 78]` | `{"damage": 1.0, "speed": 1.0}` | $1 \times 3$ (default) | None (`""`) | None | `fighter` |
| `club` | Club | 0 | `1h` | `[1, 10, 24, 45, 68]` | `{"damage": 1.0, "speed": 1.0}` | $1 \times 2$ (custom) | None (`""`) | None | `fighter` |
| `dagger` | Dagger | 0 | `1h` | `[1, 11, 28, 48, 70]` | `{"damage": 1.0, "speed": 1.0}` | $1 \times 2$ (custom) | None (`""`) | None | `fighter` |
| `axe_2h` | Battle Axe | 0 | `2h` | `[9, 22, 42, 64, 88]` | `{"damage": 1.0, "speed": 0.82}` | $2 \times 3$ (custom) | `Overbear` (`"overbear"`) | `Slot.SHIELD` | `fighter` |
| `hammer_2h` | Warhammer | 0 | `2h` | `[6, 24, 44, 66, 90]` | `{"damage": 1.0, "speed": 0.82}` | $2 \times 3$ (custom) | `Overbear` (`"overbear"`) | `Slot.SHIELD` | `fighter` |

*Note: Slot 0 corresponds to `Items.Slot.WEAPON`.*

---

## 3. Combat Mechanics & DS2 Baseline Parity

### 3.1 Damage Formulas and Curves
Curse computes weapon base hit ranges using Dungeon Siege II's linear curve macros (`ItemDef.stats_at()` in `game/data/item_def.gd`):

$$\text{Damage}_{\text{avg}}(L) = (a + b \cdot L) \cdot \text{stats}[\text{damage}]$$
$$\text{Damage}_{\text{min}}(L) = 0.75 \cdot \text{Damage}_{\text{avg}}(L), \quad \text{Damage}_{\text{max}}(L) = 1.25 \cdot \text{Damage}_{\text{avg}}(L)$$

- **One-Handed Weapons** (`1h`): $a = 3.4, b = 0.74, \text{speed} = 1.00$
  - Level 10: $3.4 + 7.4 = 10.8 \implies \mathbf{8.10 - 13.50}$ (Speed $1.00$)
  - Level 30: $3.4 + 22.2 = 25.6 \implies \mathbf{19.20 - 32.00}$ (Speed $1.00$)
  - Level 60: $3.4 + 44.4 = 47.8 \implies \mathbf{35.85 - 59.75}$ (Speed $1.00$)
- **Two-Handed Weapons** (`2h`): $a = 5.2, b = 1.20, \text{speed} = 0.82$ (matching `greatsword`)
  - Level 10: $5.2 + 12.0 = 17.2 \implies \mathbf{12.90 - 21.50}$ (Speed $0.82$)
  - Level 30: $5.2 + 36.0 = 41.2 \implies \mathbf{30.90 - 51.50}$ (Speed $0.82$)
  - Level 60: $5.2 + 72.0 = 77.2 \implies \mathbf{57.90 - 96.50}$ (Speed $0.82$)

No experimental damage modifiers or unverified DPS curves were applied.

### 3.2 Affix Disciplines (Fighter vs Ranger)
- In `game/items.gd`, `_affix_class(def)` maps non-ranged weapons to `"fighter"` and ranged weapons (`ranged: true`) to `"ranger"`.
- All six new melee weapons evaluate to `"fighter"` and roll exclusively fighter-appropriate affixes (e.g. melee damage %, added fire, strength). They never carry ranger-exclusive affixes (`ranged_min`, `ranged_max`, `ranged_pct`).
- Bows (`short_bow`) continue resolving to `"ranger"` and roll ranger-appropriate affixes.

### 3.3 Stance Requirements & Hand Conflicts
- **Stance Requirement**: Two-handed melee weapons with `profile["two_handed"] = true` and `profile["ranged"] != true` automatically evaluate stance requirement `Overbear` via `Items.requirement()`. Characters without rank $\ge 1$ in Overbear cannot equip `axe_2h` or `hammer_2h`.
- **Hand Conflict Resolution**: Equipping `axe_2h` or `hammer_2h` conflicts with `Items.Slot.SHIELD` via `PlayerStats._hand_conflict()`. Conversely, equipping a shield while wielding a two-handed weapon requires removing or swapping the weapon.
- **Animation Clips**: Both `axe_2h` and `hammer_2h` specify `two_hand_clips` in their profile, routing basic attack swings to `atk2_slash_r`, `atk2_thrust`, `atk2_slash_l`, `atk2_slash`, and `atk2_finisher`. One-handed weapons default to single-handed `atk_*` clips.

---

## 4. Visual Assets & Rig Attachment

### 4.1 Asset Paths & Verification
All 6 GLB models are complete binary files verified via Git LFS (`Git LFS fsck OK`):
- `res://assets/models/items/axe_1h/model.glb` (33.4 KB)
- `res://assets/models/items/axe_2h/model.glb` (57.3 KB)
- `res://assets/models/items/club/model.glb` (35.5 KB)
- `res://assets/models/items/dagger/model.glb` (53.4 KB)
- `res://assets/models/items/hammer_2h/model.glb` (60.6 KB)
- `res://assets/models/items/mace/model.glb` (43.4 KB)

Matching icons are 192×192 RGBA PNGs with transparency:
- `res://assets/icons/items/axe_1h.png` (21.3 KB)
- `res://assets/icons/items/axe_2h.png` (19.2 KB)
- `res://assets/icons/items/club.png` (21.6 KB)
- `res://assets/icons/items/dagger.png` (21.9 KB)
- `res://assets/icons/items/hammer_2h.png` (18.2 KB)
- `res://assets/icons/items/mace.png` (19.7 KB)

### 4.2 Rig & Grip Verification
When equipped on the live character rig (`Player.gd`), each weapon:
- Instantiates its dedicated `.glb` scene.
- Mounts dynamically to the `RightHand` bone attachment.
- Establishes `weapon_base` and `weapon_tip` transform anchors for weapon trails (`WeaponTrail`).
- Scales properly based on bounding extents ($0.85\times$ held scale).

---

## 5. Inventory Grid Integration

In `game/inventory_grid.gd`, `InventoryGrid.base_footprint()` inspects `def.inventory_size != Vector2i.ZERO` before falling back to type defaults:
- `axe_1h`: Default `1h` $\implies \mathbf{1 \times 3}$ (rotates to $3 \times 1$)
- `mace`: Default `1h` $\implies \mathbf{1 \times 3}$ (rotates to $3 \times 1$)
- `club`: Override `Vector2i(1, 2)` $\implies \mathbf{1 \times 2}$ (rotates to $2 \times 1$)
- `dagger`: Override `Vector2i(1, 2)` $\implies \mathbf{1 \times 2}$ (rotates to $2 \times 1$)
- `axe_2h`: Override `Vector2i(2, 3)` $\implies \mathbf{2 \times 3}$ (rotates to $3 \times 2$)
- `hammer_2h`: Override `Vector2i(2, 3)` $\implies \mathbf{2 \times 3}$ (rotates to $3 \times 2$)

All footprints match original Dungeon Siege II item grid allocations (`wpn_bases.gas`).

---

## 6. Loot Generation & Save/Load Roundtrip

- **Loot Generation**: `Items.pick_base(low, high, slot)` queries `ItemDb.all()`. Monte Carlo loot simulation (1,200 weapon drops across levels 1–80) verified that all 6 weapons are actively rolled and dropped.
- **Rarity Rolling**: `Items.build()` generates valid Magic (1–2 affixes) and Rare (3–4 affixes) variants with full dynamic DS2 title generation (e.g. `Callous War Axe of Grief`, `Wicked Battle Axe of Calamity`).
- **Save/Load Serialization**: Verified roundtrip through `Items.to_save()` and `Items.from_save()`. Item definition, level, rarity, affixes, and calculated min/max damage/speed are preserved with zero corruption.

---

## 7. Verification Test Suite & Results

### 7.1 Dedicated Test Suite
`tools/test_melee_weapon_integration.gd` exercises 9 comprehensive test groups:
1. Item Definitions in ItemDb (Presence, slot, 5 ascending levels)
2. DS2 Baseline Damage and Speed Formulas (levels 10, 30, 60)
3. 3D Models and Icons Resolution (PackedScene instancing, Texture2D dimensions, bounds)
4. 1H vs 2H Mechanics (Overbear requirement, two_handed flag, requirement text)
5. Inventory Footprints and Rotation ($1\times 3, 1\times 2, 2\times 3$, rotated extents)
6. Loot Generation & Affix Classes (Fighter vs Ranger class separation, affix count, name generation)
7. Serialization Save/Load Roundtrip (stats, affixes, rarity preservation)
8. Two-Hand Clips and Animations (`two_hand_clips` mapping to `atk2_*`)
9. Live Character Rig Weapon Equipping and Visual Attachment (`RightHand` mounting, trail anchors, weapon range, hand conflict)

**Result:** `268 / 268 checks passed (100%)`.

### 7.2 Full Suite and Focused Regression Passes
- `--selftest --only=items`: **PASS** (exit code 0)
- `--selftest --only=ds2items`: **PASS** (exit code 0)
- `--selftest --only=rangedmods`: **PASS** (exit code 0)
- `--selftest --only=find`: **PASS** (exit code 0)
- `--selftest --only=equipmenthits`: **PASS** (exit code 0)
- `--selftest --only=inventoryequip`: **PASS** (exit code 0)
- `--selftest --only=weaponstyle`: **PASS** (exit code 0)
- `--selftest --only=twohand`: **PASS** (exit code 0)
- `python -m unittest discover -s tools -p test_ds2_catalog.py`: **PASS** (6 tests passed, exit code 0)
- **Full Godot Selftest (`--selftest`)**: **PASS** (All ~35 test suites pass cleanly, exit code 0)

---

## 8. File Ownership & Scope Compliance

### Modified / Created Files
- `tools/write_item_defs.py` — Updated to write 25 item definitions with custom footprints and path overrides; preserves `short_bow.tres`.
- `data/items/axe_1h.tres` — New base definition.
- `data/items/mace.tres` — New base definition.
- `data/items/club.tres` — New base definition.
- `data/items/dagger.tres` — New base definition.
- `data/items/axe_2h.tres` — New base definition.
- `data/items/hammer_2h.tres` — New base definition.
- `tools/test_melee_weapon_integration.gd` — New integration test suite.
- `docs/MELEE_WEAPON_INTEGRATION_VERIFICATION.md` — This verification document.
- Asset files imported from Task 3A/3B checkpoints under `assets/models/items/`, `assets/icons/items/`, `docs/`, and `tools/blender/make_items.py`.

### Untouched Systems & Codex Implementation Preservation
- `data/items/short_bow.tres` matches `main` byte-for-byte.
- Codex's 20 ranged affixes (`data/affixes/ranged_*`), `ranged_modifier_tests.gd`, `affix_db.gd`, `player_stats.gd`, and projectile snapshots remain completely preserved.
- All 19 original base item definitions and unique/set definitions remain untouched.
- Core combat resolution logic, drop chances, and production save formats remain untouched.

---

## 9. Future Work & Next Steps

1. **Unique & Set Items**: Author dedicated unique/set variants using these bases (e.g. `ax_1h_ba_unq_01`, `mc_1h_mc_unq_01`, `dg_1h_dg_unq_01`, `hm_2h_sh_unq_01`).
2. **Audio Variation**: Map distinct blunt impact audio for maces/clubs/hammers and cutting audio for axes/daggers.
3. **Dual Wielding**: Dual wielding mechanics remains reserved for a dedicated future task.
