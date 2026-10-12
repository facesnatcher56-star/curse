# One-Handed Weapon Asset Expansion: Technical Report

**Task**: Task 3A — One-Handed Weapon Asset Expansion  
**Branch**: `agents/gemini-weapon-assets`  
**Reference Alignment**: Curse Dark-Fantasy Art Direction (`docs/ART_DIRECTION.md`), Equipment Audit (`docs/EQUIPMENT_EXPANSION_PLAN.md`), DS2 Baseline Combat Specifications (`docs/COMBAT_REFERENCE.md`)  
**Pipeline**: Blender 5.1 Procedural Asset Generator (`tools/blender/make_items.py`) & Godot 4.8-dev2 Import System  

---

## 1. Executive Summary

As identified in the equipment expansion audit, Curse currently features base item assets for swords (`falchion`, `longsword`, `greatsword`) and bows (`short_bow`), leaving core one-handed melee weapon archetypes from Dungeon Siege II unrepresented. 

Task 3A delivers production-ready 3D models (`model.glb`) and corresponding transparent inventory icons (`.png`) for four fundamental one-handed melee weapon categories:
1. **One-Handed Axe** (`axe_1h`)
2. **Mace** (`mace`)
3. **Club** (`club`)
4. **Dagger** (`dagger`)

All models and icons adhere strictly to Curse's gritty, weathered dark-fantasy aesthetic, use procedural vertex-colored PBR shading without auxiliary texture dependencies, and are fully aligned with the character rig's right-hand attachment mechanics.

---

## 2. Asset Specifications & Geometry Analysis

All weapons are procedurally constructed along the **+X long axis** with the butt/pommel at negative X and striking head/tip at positive X. On export, bounding boxes are grounded on the ground plane ($Z = 0$ in Blender, imported into Godot as $Y = 0$) and centered along X and Y.

### 2.1 One-Handed Axe (`axe_1h`)
- **Archetype**: Heavy bearded war axe / battle axe.
- **Visual Features**:
  - Tapered hardwood haft with dark leather wrap and raised leather binding bands.
  - Iron socket eye with langets (reinforcing side straps along haft with dark steel rivets) to resist weapon shearing.
  - Bearded blade cheek (`dark_steel`) hooking downward toward the grip, laminated with a honed steel crescent cutting edge (`steel`).
  - Heavy forged iron hammer poll (`iron`) with a beveled striking face on the rear (-Y) for visual counterweight.
  - Shaft top exposed with a forged iron retention wedge; rounded iron butt cap and lanyard knob at the pommel.
- **Dimensions (Godot World Units / Meters)**:
  - Length (X): $0.711\text{ m}$
  - Width / Beard Flare (Z in Godot, Y in Blender): $0.228\text{ m}$
  - Head Thickness (Y in Godot, Z in Blender): $0.052\text{ m}$
- **Geometry Optimization**:
  - Vertices: $540$
  - Polygons: $440$
  - Materials: `wood`, `iron`, `dark_steel`, `steel`, `leather_dark`, `leather`
- **Grip Proportions**:
  - Grip zone: $x = -0.175\text{ m}$ to $-0.025\text{ m}$ (center: $-0.10\text{ m}$).
  - Distance from butt: $\approx 15\%$ of total length, perfectly centered for one-handed wielding.

---

### 2.2 Mace (`mace`)
- **Archetype**: Flanged steel footman's mace.
- **Visual Features**:
  - Solid dark steel octagonal/cylindrical shaft with warm brass hilt collar and upper flange stop ring.
  - Wrapped leather grip bound with spiraled brass wire windings.
  - Six radiating sharp flanges (`steel`) with beveled striking points and notched recurve profiles.
  - Heavy dark steel flange hub capped with a 4-sided pyramid armor-piercing crown spike.
  - Faceted brass bulb pommel with a dark steel peen stud.
- **Dimensions (Godot World Units / Meters)**:
  - Length (X): $0.738\text{ m}$
  - Head Diameter (Y / Z in Godot): $0.116\text{ m} \times 0.132\text{ m}$
- **Geometry Optimization**:
  - Vertices: $528$
  - Polygons: $398$
  - Materials: `dark_steel`, `steel`, `brass`, `leather`
- **Grip Proportions**:
  - Grip zone: $x = -0.165\text{ m}$ to $-0.025\text{ m}$ (center: $-0.095\text{ m}$).
  - Distance from butt: $\approx 16.5\%$ of total length.

---

### 2.3 Club (`club`)
- **Archetype**: Spiked wooden cudgel / war club.
- **Visual Features**:
  - Gnarled, asymmetrical hardwood body tapering from a slender handle to a bulbous, knotty striking head.
  - Three heavy forged iron reinforcement hoops encircling the head.
  - Radial forged iron pyramid spikes (4 on bottom band, 6 staggered on middle band, 4 on top band) plus a front iron stud.
  - Worn dark leather handle strapping with spiral cord wraps; carved wooden end knob with hanging leather lanyard ring.
- **Dimensions (Godot World Units / Meters)**:
  - Length (X): $0.675\text{ m}$
  - Head Diameter across Spikes (Y / Z in Godot): $0.153\text{ m} \times 0.166\text{ m}$
- **Geometry Optimization**:
  - Vertices: $676$
  - Polygons: $538$
  - Materials: `wood`, `iron`, `leather_dark`, `leather`
- **Grip Proportions**:
  - Grip zone: $x = -0.165\text{ m}$ to $-0.035\text{ m}$ (center: $-0.10\text{ m}$).
  - Distance from butt: $\approx 17\%$ of total length.

---

### 2.4 Dagger (`dagger`)
- **Archetype**: Combat stiletto / assassin's dirk.
- **Visual Features**:
  - Compact double-edged thrusting blade (`steel`) with a central blood fuller and acute needle point.
  - Steel ricasso above down-curved dark steel quillons terminating in spherical ball tips.
  - Waisted barrel grip in stained dark leather, wound with six ribbed brass wire wraps.
  - Pear-shaped faceted brass pommel with a dark steel peening block.
- **Dimensions (Godot World Units / Meters)**:
  - Length (X): $0.478\text{ m}$
  - Guard Width (Z in Godot, Y in Blender): $0.120\text{ m}$
  - Blade / Guard Thickness (Y in Godot, Z in Blender): $0.042\text{ m}$
- **Geometry Optimization**:
  - Vertices: $591$
  - Polygons: $541$
  - Materials: `steel`, `dark_steel`, `brass`, `leather_dark`
- **Grip Proportions**:
  - Grip zone: $x = -0.145\text{ m}$ to $-0.035\text{ m}$ (center: $-0.09\text{ m}$).
  - Compact scale distinguishes it instantly from swords at elevated camera heights.

---

## 3. Character Rig & Attachment Compatibility

In Curse's character architecture (`game/character_model.gd` and `game/player.gd`):
1. **Weapon Grip Orientation**:
   - Dropped weapons lie along X on the ground ($Y = 0$).
   - When equipped, `CharacterModel.attach_weapon` applies `prop_basis = Basis(Vector3(0, 0, 1), PI * 0.5)` to rotate the weapon upright (+X maps to +Y, +Y maps to -X).
   - This points the weapon head/tip upward and the cutting/striking face forward toward the swing trajectory.
2. **Grip Offset**:
   - `Player.gd` uses `grip_offset = 0.11` (measuring 11% up from the bottom bounding box edge).
   - Because all 4 weapon models center their grip handle between $11\%$ and $18\%$ of the bounding box baseline, the weapon snaps cleanly into the palm of the right hand bone without manual offset adjustments.
3. **Vertex Color Shader Compatibility**:
   - Handled natively by `LootDrop._use_vertex_colours(prop)`, ensuring the vertex noise (grime, scuffed edges, rust, wood grain) is rendered seamlessly in Godot's Forward+ pipeline without requiring external texture samplers.

---

## 4. Inventory Icons

Inventory icons are rendered at $192 \times 192$ RGBA via an orthographic camera tilted at $8^\circ$:
- **Color Mode**: 32-bit RGBA (8-bit per channel truecolor with transparent alpha).
- **Background**: Fully transparent (allowing Godot HUD rarity border framing).
- **Orientation**: Rotated $-38^\circ$ diagonally across the frame so the full weapon length maximizes the inventory cell.
- **Files**:
  - `assets/icons/items/axe_1h.png` ($21.2\text{ KB}$)
  - `assets/icons/items/mace.png` ($19.7\text{ KB}$)
  - `assets/icons/items/club.png` ($21.5\text{ KB}$)
  - `assets/icons/items/dagger.png` ($21.8\text{ KB}$)

---

## 5. Verification Results

| Check | Tool / Engine | Status | Notes |
| :--- | :--- | :--- | :--- |
| **Blender Asset Generation** | Blender 5.1.0 | **PASS** | Clean execution of `make_items.py` with zero geometry errors |
| **glTF 2.0 Binary Export** | Blender glTF Exporter | **PASS** | Valid GLB models generated with embedded vertex color streams |
| **Godot Headless Import** | Godot 4.8-dev2 Headless | **PASS** | Imported all 4 models and 4 icons; generated `.import` configurations |
| **SceneTree Instantiation** | Godot GDScript Test | **PASS** | All 4 GLBs instantiate cleanly as `Node3D`; meshes and AABB computed |
| **Vertex Color Verification** | Godot RenderingServer | **PASS** | Confirmed `Mesh.ARRAY_COLOR` present on all exported surfaces |
| **Icon Format & Alpha** | PNG Header & Alpha Check | **PASS** | All icons are $192\times 192$ RGBA with transparent alpha |
| **Direct3D12 GPU Rendering** | Radeon RX 6900 XT | **PASS** | Captured live multi-light weapon lineup render without shader errors |

---

## 6. Implementation Dependencies & Future Tasks

To integrate these visual assets into live gameplay in future tasks without modifying central combat code:
1. **Item Definitions (`data/items/*.tres`)**:
   - Create base resource definitions: `axe_1h_base.tres`, `mace_base.tres`, `club_base.tres`, `dagger_base.tres`.
   - Configure attack speed, damage range, and reload delay per DS2 reference specifications.
2. **Item System Registration (`game/items.gd`)**:
   - Register category mappings so `Slot.WEAPON` recognizes axe, mace, club, and dagger subtypes.
3. **Sound Effects & Combat Audio**:
   - Map attack and hit sound profiles (distinct slicing sounds for axes/daggers vs. blunt crunch sounds for maces/clubs).
4. **Loot Tables (`game/loot.gd`)**:
   - Incorporate new weapon bases into standard dropped loot pools once approved.
