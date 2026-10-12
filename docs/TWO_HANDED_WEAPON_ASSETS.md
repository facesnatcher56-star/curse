# Two-Handed Weapon Asset Expansion: Technical Report

**Task**: Task 3B — Two-Handed Weapon Asset Expansion  
**Branch**: `agents/gemini-twohand-assets`  
**Starting Commit**: `7790add25400e817de4e0d456b50eb4024774cff`  
**Reference Alignment**: Curse Dark-Fantasy Art Direction (`docs/ART_DIRECTION.md`), Equipment Audit (`docs/EQUIPMENT_EXPANSION_PLAN.md`), DS2 Baseline Combat Specifications (`docs/COMBAT_REFERENCE.md`)  
**Pipeline**: Blender 5.1 Procedural Asset Generator (`tools/blender/make_items.py`) & Godot 4.8-dev2 Import System  

---

## 1. Executive Summary

Following the completion of Task 3A (One-Handed Weapon Assets), Task 3B introduces production-ready 3D models and inventory icons for the two missing heavy two-handed melee weapon categories from Dungeon Siege II:
1. **Two-Handed Battle Axe** (`axe_2h`)
2. **Two-Handed Warhammer** (`hammer_2h`)

These weapons are engineered as heavy two-handed battlefield armaments, featuring substantial proportions (~1.41m to 1.43m in overall length), dedicated lower and upper grip sections for two-handed wielding, reinforced haft langets with structural rivets, and distinct silhouettes that remain instantly readable at Curse's elevated isometric camera distance.

Both assets use procedural vertex-colored PBR materials (`wood`, `leather_dark`, `leather`, `iron`, `dark_steel`, `steel`, `brass`), export as optimized GLB scenes without auxiliary texture requirements, and include matching 192×192 transparent RGBA inventory icons.

---

## 2. Asset Specifications & Geometry Analysis

Both models are procedurally generated along the **+X long axis**, centered along X and Y, and grounded on the ground plane ($Z = 0$ in Blender, imported into Godot as $Y = 0$).

```
[Butt/Pommel -X] === [Lower Grip] === [Divider] === [Upper Grip] === [Langets/Haft] === [Head/Socket +X]
```

### 2.1 Two-Handed Battle Axe (`axe_2h`)
- **Archetype**: Heavy Danish war axe / executioner's battle axe with armor-piercing pick.
- **Visual Features**:
  - **Haft**: 1.30m long faceted hardwood haft (`wood`), tapered from throat to butt.
  - **Dual Grips**:
    - Lower grip: 22cm wrapped dark leather grip (`leather_dark`) bound with raised cord ribs for leverage during wide swings.
    - Upper grip: 24cm wrapped dark leather grip (`leather_dark`) for choke-up handling, half-swording, and guard positions.
    - Dividing collar: Decorative brass ring with iron retaining collars separating the two grips.
  - **Haft Protection**: Four long forged steel langets (`dark_steel`) extending 34cm down the haft from the socket, fastened with six hexagonal steel rivets (`iron`) to prevent the haft from being sheared off in combat.
  - **Axe Head & Socket**: Heavy dark steel socket eye (`dark_steel`) enveloping the wood haft, reinforced with an iron throat collar.
  - **Cutting Bit**: Broad, sweeping crescent cutting cheek (`dark_steel`) terminating in a razor-honed steel cutting edge (`steel`) spanning 38.5cm across its cutting arc, featuring visible edge bevels.
  - **Rear Armor-Piercing Spike**: Curved raven's beak pick (`dark_steel`) projecting 15cm from the rear poll (-Y) for puncturing heavy plate armor.
  - **Top Thrusting Spike**: Forged 4-sided pyramid spike (`steel`) projecting from the crest (+X) seated on a faceted brass collar.
  - **Butt**: Conical steel butt cap with an armor-piercing heel spike for close-quarters bashing.
- **Dimensions (Godot World Units / Meters)**:
  - Length (X): $1.435\text{ m}$
  - Head Height / Blade Arc (Z in Godot, Y in Blender): $0.385\text{ m}$
  - Head Thickness (Y in Godot, Z in Blender): $0.059\text{ m}$
- **Geometry Optimization**:
  - Vertices: $998$
  - Polygons: $743$
  - Materials: `wood`, `leather_dark`, `leather`, `iron`, `dark_steel`, `steel`, `brass`
- **Grip Proportions**:
  - Lower grip: $x = -0.62\text{ m}$ to $-0.40\text{ m}$ (center: $-0.51\text{ m}$)
  - Upper grip (primary hold): $x = -0.37\text{ m}$ to $-0.13\text{ m}$ (center: $-0.25\text{ m}$)

---

### 2.2 Two-Handed Warhammer (`hammer_2h`)
- **Archetype**: Heavy two-handed warhammer / Lucerne pole-hammer.
- **Visual Features**:
  - **Shaft**: 1.28m long octagonal hardwood shaft (`wood`) reinforced for high-impact concussive blows.
  - **Dual Grips**:
    - Lower grip: 22cm dark leather grip with raised bindings for two-handed swing velocity.
    - Upper grip: 24cm dark leather grip with raised bindings for close-in control.
    - Dividing collar: Polished brass divider with iron stop washers.
  - **Langets & Throat**: Four full-length dark steel langets extending 32cm down the shaft, secured with six structural rivet bolts (`iron`).
  - **Socket & Impact Head**: Heavy octagonal socket block (`dark_steel`) reinforced with lateral iron cheek plates and central domed rivet studs.
  - **Striking Face**: Massive square striking block (`dark_steel`) flared out from a brass decorative collar, tipped with a four-pronged diamond waffle face (`steel`) designed to crush plate armor without skidding.
  - **Rear Crowbill Pick**: Heavy curved armor-piercing beak (`dark_steel`) on the rear poll (-Y) with honed steel tip.
  - **Top Thrusting Spike**: Acute 4-sided steel pyramid thrusting spike (+X) seated on a brass rosette collar.
  - **Pommel**: Rounded steel counterweight pommel with an articulated iron lanyard/tether ring.
- **Dimensions (Godot World Units / Meters)**:
  - Length (X): $1.411\text{ m}$
  - Head Width across Faces (Z in Godot, Y in Blender): $0.331\text{ m}$
  - Head Thickness across Cheeks (Y in Godot, Z in Blender): $0.104\text{ m}$
- **Geometry Optimization**:
  - Vertices: $1,058$
  - Polygons: $797$
  - Materials: `wood`, `leather_dark`, `leather`, `iron`, `dark_steel`, `steel`, `brass`
- **Grip Proportions**:
  - Lower grip: $x = -0.60\text{ m}$ to $-0.38\text{ m}$ (center: $-0.49\text{ m}$)
  - Upper grip (primary hold): $x = -0.35\text{ m}$ to $-0.11\text{ m}$ (center: $-0.23\text{ m}$)

---

## 3. Comparative Proportions: Two-Handed vs One-Handed Lineup

The table below contrasts the dimensions and geometry of the two new two-handed weapons against the baseline reference two-handed `greatsword` as well as the one-handed melee weapons introduced in Task 3A:

| Weapon Asset ID | Category | Overall Length (m) | Head / Blade Width (m) | Thickness (m) | Verts | Polys | Primary Grip Center (m) |
|---|---|---|---|---|---|---|---|
| **`greatsword`** | 2H Sword (Baseline) | **$1.713$** | $0.359$ | $0.080$ | $919$ | $704$ | $-0.22$ |
| **`axe_2h`** | **2H Battle Axe (New)** | **$1.435$** | **$0.385$** | **$0.059$** | **$998$** | **$743$** | **$-0.25$** |
| **`hammer_2h`** | **2H Warhammer (New)** | **$1.411$** | **$0.331$** | **$0.104$** | **$1,058$** | **$797$** | **$-0.23$** |
| `axe_1h` | 1H Axe (Task 3A) | $0.711$ | $0.228$ | $0.052$ | $540$ | $440$ | $-0.10$ |
| `mace` | 1H Mace (Task 3A) | $0.738$ | $0.132$ | $0.116$ | $528$ | $398$ | $-0.095$ |
| `club` | 1H Club (Task 3A) | $0.675$ | $0.166$ | $0.153$ | $676$ | $538$ | $-0.10$ |
| `dagger` | 1H Dagger (Task 3A) | $0.478$ | $0.120$ | $0.046$ | $430$ | $332$ | $-0.08$ |

### Visual Distinctiveness & Proportions
1. **Scale**: Both `axe_2h` ($1.435\text{ m}$) and `hammer_2h` ($1.411\text{ m}$) are approximately double the length of their one-handed counterparts (`axe_1h` at $0.711\text{ m}$, `mace` at $0.738\text{ m}$). They are intentionally shorter than the massive 1.71m greatsword to reflect historical pole-axe/warhammer leverage physics while avoiding ground clipping during combat swings.
2. **Dual-Grip Separation**: Unlike the single 15cm grip of one-handed weapons, both two-handed weapons provide two distinct wrapped grip zones (22cm lower, 24cm upper) separated by metal collar stops, clearly communicating two-handed wielding.
3. **Head Mass & Silhouettes**:
   - `axe_2h` features an asymmetrical broad crescent cutting cheek ($38.5\text{ cm}$) balanced by a narrow curved raven's beak pick ($15\text{ cm}$) and top thrusting spike.
   - `hammer_2h` features an octagonal socket block with a prominent square 4-pronged waffle face on the front (+Y) and a curved crowbill pick on the rear (-Y).

---

## 4. Rigging, Grip Alignment, and Character Rig Integration

### 4.1 Rig Coordinate System & Transforms
In Curse's character attachment system:
- Weapon models are exported along the **+X axis** (length), with butt at negative X and head at positive X.
- Models are grounded with bounding box minimum $Z = 0$ in Blender ($Y = 0$ in Godot) and centered across width.
- In `player.gd`, weapons attached to the right hand socket are rotated upright via:
  ```gdscript
  inst.basis = Basis(Vector3(0, 0, 1), PI * 0.5)
  ```
  This places the weapon vertically along the character's body (+Y up, -Y down).

### 4.2 Grip Offset Handling
- The `player.gd` attachment system positions weapon origins using `grip_offset`:
  ```gdscript
  inst.position.y = -bounds.size.x * grip_offset
  ```
- For two-handed weapons of length $\approx 1.42\text{ m}$:
  - With `grip_offset = 0.11`, the weapon root is shifted downward by $\approx 0.156\text{ m}$ from the model center.
  - This precisely places the character's right hand (primary hand) inside the upper grip zone ($x = -0.35\text{ m}$ to $-0.11\text{ m}$).
  - The lower grip zone ($x = -0.60\text{ m}$ to $-0.38\text{ m}$) extends below the primary hand, providing an ideal anchor location for the off-hand during future two-handed animation integration.

### 4.3 Animation Compatibility Disclaimer
> [!IMPORTANT]
> Both `axe_2h` and `hammer_2h` conform strictly to the static bone attachment convention and bounding proportions of `greatsword`. However, full dynamic two-handed gripping depends on dedicated two-handed animation clips (idle, run, two-handed swing, recovery) and off-hand IK attachment, which remain part of future animation system updates. No claim of animated two-handed grip compatibility is made without those clips being authored.

---

## 5. Inventory Icon Specifications

Matching the standard established by `greatsword.png`, `longsword.png`, and `falchion.png`:
- **Format**: 192×192 pixels, 32-bit RGBA PNG with 100% transparent background.
- **Framing**: Rendered orthographically at an isometric 45-degree angle along the primary diagonal, orienting the weapon head toward the top-right and the butt toward the bottom-left.
- **Lighting**: Three-point studio lighting with warm key light, cool blue rim, and ambient fill to ensure high contrast and clear edge definition against dark inventory backgrounds.
- **Readability**: Both icons remain crisp and distinguishable when scaled down to standard inventory cell dimensions ($64\times 64$) or tooltip thumbnail previews ($32\times 32$).

---

## 6. Verification Results

### 6.1 Blender Procedural Asset Generation
Both models and icons were generated via `tools/blender/make_items.py`:
- `python tools/blender/make_items.py -- axe_2h hammer_2h`
- Generation completed with zero geometry errors or missing vertex colors.
- GLB file sizes:
  - `assets/models/items/axe_2h/model.glb`: $57.3\text{ KB}$
  - `assets/models/items/hammer_2h/model.glb`: $60.6\text{ KB}$
- PNG icon file sizes:
  - `assets/icons/items/axe_2h.png`: $19.2\text{ KB}$ (192×192 RGBA)
  - `assets/icons/items/hammer_2h.png`: $18.2\text{ KB}$ (192×192 RGBA)

### 6.2 Godot Headless Import & Resource Verification
Godot Engine v4.8-dev2 headless editor import was executed in `curse-gemini-audit`:
- Generated `.import` metadata files:
  - `assets/models/items/axe_2h/model.glb.import`
  - `assets/models/items/hammer_2h/model.glb.import`
  - `assets/icons/items/axe_2h.png.import`
  - `assets/icons/items/hammer_2h.png.import`
- Executed headless verification suite (`scratch/verify_twohand_weapons.gd`):
  - **`axe_2h`**: AABB size $(1.435, 0.059, 0.385)$, position $(-0.718, 0.0, -0.192)$, mesh count: 1, vertex colors: `true`, icon: $192\times 192$ -> **PASS**
  - **`hammer_2h`**: AABB size $(1.411, 0.104, 0.331)$, position $(-0.706, 0.0, -0.165)$, mesh count: 1, vertex colors: `true`, icon: $192\times 192$ -> **PASS**
  - **`greatsword`** (reference): AABB size $(1.713, 0.08, 0.359)$, position $(-0.857, 0.0, -0.18)$, mesh count: 1, vertex colors: `true`, icon: $192\times 192$ -> **PASS**

### 6.3 Godot In-Engine Rendering & Isometric Readability
- Captured Direct3D 12 Forward+ in-engine renders using Godot's live rendering pipeline:
  - `godot_twohand_preview.png`: Upright comparison on stone pedestal showcasing detailed vertex-color materials, metal specular highlights, and surface bevels under sunlight and ambient fill.
  - `godot_twohand_isometric.png`: Isometric gameplay camera perspective validating silhouette readability from elevated combat camera distances.

### 6.4 Test Suites
- Python DS2 catalog test suite (`tools/test_ds2_catalog.py`): **6 passed, 0 failed**.
- Engine self-test (`res://game/main.tscn --selftest`): Verified that adding these new assets introduces zero regressions to existing navigation, combat, hotkeys, or inventory tests.

---

## 7. Strict File Ownership & Boundaries

In accordance with task constraints:
- **Modified**:
  - `tools/blender/make_items.py` (added `build_axe_2h` and `build_hammer_2h` procedural builders and registered in `BUILDERS`)
- **New Asset Files**:
  - `assets/models/items/axe_2h/model.glb`
  - `assets/models/items/axe_2h/model.glb.import`
  - `assets/models/items/hammer_2h/model.glb`
  - `assets/models/items/hammer_2h/model.glb.import`
  - `assets/icons/items/axe_2h.png`
  - `assets/icons/items/axe_2h.png.import`
  - `assets/icons/items/hammer_2h.png`
  - `assets/icons/items/hammer_2h.png.import`
- **Documentation**:
  - `docs/TWO_HANDED_WEAPON_ASSETS.md`
- **Prohibited Files (Untouched)**:
  - No changes made to `game/`, `data/`, combat scripts, loot tables, or existing item resource definitions.
  - Claude's branch and worktree remain completely untouched.

---

## 8. Limitations & Future Integration Requirements

The assets produced in Task 3B represent production-ready 3D models and icons, but do not alter live gameplay until subsequent implementation phases are authorized:
1. **Item Resource Definitions**: Requires `.tres` definitions under `data/items/` for base two-handed axes and warhammers specifying attack speed, weapon damage ranges, attribute requirements, and stat scaling.
2. **Two-Handed Combat Animations**: In Dungeon Siege II, two-handed battle axes and warhammers feature slower, high-impact cleaving swings with distinct windup and follow-through arcs. Future tasks will integrate corresponding attack clips and two-handed hold poses into the character animation state machine.
3. **Sound FX**: High-impact blunt crushing sound effects for `hammer_2h` and heavy blade cleaving sounds for `axe_2h` should be mapped when the weapon definitions are added to combat.
4. **Loot Generation Tables**: Once item resource definitions and audio/animations are staged, `axe_2h` and `hammer_2h` will be enrolled in the rarity and zone drop tables.
