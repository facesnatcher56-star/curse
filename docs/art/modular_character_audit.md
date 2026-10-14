# Modular character audit (Lane A)

Source: `Curse_Knight_Experiment/Curse_Knight.blend` (preserved copy, read-only). Measured with Blender 5.1 Python.

## 1. Knight as found

| Object | Tris | Notes |
|---|---:|---|
| KN_Arms | 3112 | pauldrons, arm plates, gauntlets: 30 loose parts |
| KN_Body | 612 | single-material cloth under-suit (sleeves, trousers); no head, hands or feet skin |
| KN_Helmet | 980 | closed great helm, 1 vertex group (Head, rigid) |
| KN_Legs | 2880 | cuisses, greaves, sabatons: 36 loose parts |
| KN_Shield | 1286 | rigid, LeftHandProp |
| KN_Sword | 404 | rigid, RightHandProp |
| KN_Torso | 1968 | cuirass, gorget, tassets, cloth skirt |
| **Total** | **11242** | evaluated (post-modifier) count is identical |

- Armature `Knight_Rig`: 24 bones, humanoid, A-pose rest. Root, Hips, Spine, Chest, Neck, Head; Left/Right Shoulder, UpperArm, LowerArm, Hand, HandProp; Left/Right UpperLeg, LowerLeg, Foot, Toes. Front is -Y, character Left is +X.
- Skinning: every mesh has an Armature modifier, 0 unweighted vertices. Armor limbs are weighted per loose part (rigid plates), body cloth is smoothly weighted.
- Actions (30 fps, all with NLA tracks): Idle_Combat 121f, Walk_Forward 37, Run_Forward 23, Attack_Sword_Light 34, Attack_Sword_Heavy 48, Block_Shield 40, Hit_Reaction_Front/Left/Right 26, Death 90.
- Equipment present: full plate (helm, cuirass, pauldrons, arms, gauntlets, legs, sabatons), kite shield, sword. No bow, no skin body, no other clothing.
- Findings: the body is NOT neutral (cloth only, no skin) and everything is merged per limb, so armor is not separable by slot as shipped. 11 materials (M_DarkIron, M_AgedTrim, M_Steel, M_Leather, M_Cloth, ...), no textures.

## 2. Modular kit (`tools/art/modular_build.py`)

Rig renamed `Character_Rig`; bone names and all 10 actions unchanged. Armor was split by loose part using the dominant bone (hands to GLV_, foot/toes to BTS_). New meshes are procedural lofts, skinned to the same bones, flat-shaded.

Naming: `SLOT_Style` where slot is BODY, CLT, TOR, ARM, GLV, LEG, BTS, HLM, SHD, WPN.

| Mesh | Tris | Origin |
|---|---:|---|
| BODY_Skin | 582 | new neutral skin body (head, neck, torso, limbs, hands, feet) |
| CLT_Gambeson | 612 | reused KN_Body |
| TOR_Plate / ARM_Plate / LEG_Plate | 1968 / 2480 / 1568 | knight split |
| GLV_Plate / BTS_Plate | 632 / 1312 | knight split |
| HLM_Great | 980 | reused KN_Helmet |
| SHD_Kite / WPN_Sword | 1286 / 404 | reused, rigid to Left/RightHandProp |
| TOR_Leather, GLV_Leather, BTS_Leather | 222, 94, 150 | new |
| ROBE_Mage (robe + sleeves) | 308 | new, skirt weighted to hips/upper legs by side |
| HLM_Kettle, HLM_Hood | 128, 116 | new |
| WPN_Bow | 150 | new, rigid to LeftHandProp, modelled upright for the idle pose |

Kit total 12992 tris; one worn loadout is far lower (leather fighter 2192, mage 1156, plate knight 11824 (incl. unseen skin and gambeson under armor)).

## 3. Outputs

- `assets/art_staging/knight/knight_baseline.glb`: unmodified knight.
- `assets/art_staging/knight/curse_modular.glb` and `Curse_Modular.blend`: the kit.
- `assets/art_staging/knight/modular_demo.tscn`: one skinned character, presets and per-slot swapping by mesh visibility (keys in the script header). Not wired into the live player.
- `docs/art/renders/godot_*.png`: Godot renders (Forward+, D3D12) of 4 loadouts in idle front/back, run, attack, plus hit, death and walk. These are Godot renders, not Blender previews; no Blender previews were made.

## 4. Known gaps

- Mage robe: at the highest knee lift of the run, the skin thigh pokes through the robe front. Walk, idle, attack are clean.
- Leather fighter and archer legs show the grey gambeson trousers; the face is plain, with a minimal nose and brow.
- Bow orientation is tuned for Idle_Combat only; it tilts in other animations. Sword and shield keep the knight's original hand fit.
- Weapons are skinned at weight 1.0 to the prop bones, not Godot BoneAttachment nodes.
- Death was captured with the shared camera, so the body lies partly off frame.
- Not verified: gameplay-camera readability, 1080p/1440p, controller/UI, performance, other resolutions, the Blender side beyond the export script, equipment combinations beyond the four presets.
