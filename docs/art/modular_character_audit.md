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
- `assets/art_staging/knight/curse_modular.glb` and `source/Curse_Modular.blend` (Blender source, `.gdignore`d so Godot never imports it): the kit.
- `assets/art_staging/knight/modular_demo.tscn`: one skinned character, presets and per-slot swapping by mesh visibility (keys in the script header). Not wired into the live player.
- `docs/art/renders/godot_*.png`: Godot renders (Forward+, D3D12) of 4 loadouts in idle front/back, run, attack, plus hit, death and walk. These are Godot renders, not Blender previews; no Blender previews were made.

## 4. Known gaps

- Mage robe: at the highest knee lift of the run, the skin thigh pokes through the robe front. Walk, idle, attack are clean.
- Leather fighter and archer legs show the grey gambeson trousers; the face is plain, with a minimal nose and brow.
- Bow orientation is tuned for Idle_Combat only; it tilts in other animations. Sword and shield keep the knight's original hand fit.
- Weapons are skinned at weight 1.0 to the prop bones, not Godot BoneAttachment nodes.
- Death was captured with the shared camera, so the body lies partly off frame.
- Not verified: gameplay-camera readability, 1080p/1440p, controller/UI, performance, other resolutions, the Blender side beyond the export script, equipment combinations beyond the four presets.

## 5. Rig compatibility with the live game rig (knight2), measured

The experiment rig and `assets/models/knight2/rigged.glb` both have 24 bones but are **not interchangeable**.

| | Experiment rig (Knight_Rig) | Game rig (Meshy, knight2) |
|---|---|---|
| Units / scale | metres, 1.88 m | centimetres under an Armature scaled 0.01, 1.77 m |
| Spine | Hips, Spine, Chest, Neck | Hips, Spine02, Spine01, Spine, neck (lower case) |
| Head | Head | Head, plus head_end and headfront helper bones |
| Arms | Shoulder, UpperArm, LowerArm, Hand, HandProp | Shoulder, Arm, ForeArm, Hand (no prop bone) |
| Legs | UpperLeg, LowerLeg, Foot, Toes | UpLeg, Leg, Foot, ToeBase |
| Extra | Root, LeftHandProp, RightHandProp | none (props attach to the hand through CharacterModel mounts) |
| Rest pose | arms straight, 45 degrees down | arms bent forward, hands in front of the hips |
| Clips | 10 (Idle_Combat, Walk_Forward, Run_Forward, 2 attacks, block, 3 hits, Death) | 36 (Player.CLIPS) used by Player, BowAttack, BodyRecoil, hit reaction, knockdown |

Global rest-orientation difference for the 13 bones that map one to one (degrees, from `game/dev/modular_rig_demo.gd`): Hips 2, Spine 4, Chest 2, Neck 2, Head 2, **Shoulder 90, Arm 41, ForeArm 53, Hand 62, UpLeg 174, Leg 178, Foot 146**, ToeBase 20. Roll conventions differ on every limb bone, so a rename adapter alone would give wrong poses: local rotation tracks authored for one rest orientation are wrong on the other.

Game code that is keyed on game-rig bone names: `CharacterModel` (RightHand/LeftHand mounts, `spine`/`leftupleg`/`neck`/`head` name matching in the hit reaction, RightUpLeg leg raise), `BowAttack` (Spine02, LeftArm, LeftForeArm, LeftHand, RightArm, RightForeArm, RightHand aim chains), `CharacterPresentation.share_combat_clips` (remaps clip tracks by bone name).

### Options

- (a) Keep the experiment rig: needs all 36 clips retargeted onto it (only 10 exist there, none for kick, roll, leap, bow draw, throw...) and the name keyed code above changed or duplicated. High cost, and every future clip repeats it.
- (b) Retarget the modular model onto the game rig: the kit meshes are bind-pose retargeted once (per-bone rotation and length scale, linear blend skinning, `tools/art/modular_export.py`) and bound at runtime to the real skeleton (`game/modular_appearance.gd`). All 36 clips, bow aim chains, hit reaction and mounts work unchanged.

**Chosen: (b).** Evidence from `game/dev/modular_rig_demo.gd` (headless, live path `CharacterModel.build` + `share_combat_clips`, plate set + kite shield, sword mounted exactly as `Player.refresh_weapon_model` does). Peak bone travel from rest pose in metres, sampled at 13 points per clip (hand R / hand L / foot R / head):
idle_alert 0.25/0.27/0.17/0.10, walk 0.41/0.41/0.44/0.04, run 0.35/0.41/0.64/0.13, atk_slash 1.16/0.73/0.49/0.70, atk_thrust 0.75/0.34/0.62/0.34, slash 1.02/0.62/0.70/0.64, hit 0.51/0.83/0.30/0.20, death 1.28/0.99/0.71/1.33.
The sword stayed within 0.0 cm of a constant offset from RightHand and the shield centre within 0.0 cm of a constant offset from LeftForeArm in every clip; BodyRecoil still tipped the spine. This proves attachment and clip playback work, and Godot renders (`docs/art/renders3/RIGDEMO_*.png`) show them in the right hands. It does not prove pose quality of every vertex in every clip.

Not verified: Cutter/other rigs, quality of deformation at extreme clips for the new leather and robe pieces, and the BowAttack aim pose with the kit bow in an actual draw (the bow uses the same prop convention and mount as the game's own bow).

## 6. Equipment visuals (opt-in, `-- --modular`)

`data/appearance/equipment_visuals.json` maps item def ids to separate GLBs in `assets/models/modular/` (one piece per file); `game/modular_appearance.gd` binds them to the game skeleton. `game/dev/modular_check.gd` checks equip, unequip, mixed sets, save/restore and clip availability. The default presentation is unchanged: the opt-in changes in `player.gd`, `player_stats.gd`, `actor.gd`, `character_model.gd` and `bow_attack.gd` are inert without `--modular`.

Triangles per worn build (hair/beard hidden when a helm covers them): plate knight 11,942, leather archer 3,546, mage 3,178. Mage and archer are under the 5,000 budget floor and are not yet at the knight's level.

## 7. Placeholder item visuals (reused meshes, NOT finished art)

These items show another item's mesh until they get their own GLB (rows marked `"placeholder": true` in `data/appearance/equipment_visuals.json`). Do not treat them as final.

| Item | Currently shows | Needs |
|---|---|---|
| mail_hauberk, chain_mail | plate cuirass + plate arms (tor_plate, arm_plate) | mail hauberk with sleeves, ring texture/silhouette |
| carved_tunic | leather jerkin (tor_leather) | its own tunic |
| dragon_helm | great helm (hlm_great) | dragon crest helm |
| carved_cap | leather cap (hlm_cap) | its own cap |
| studded_gloves | leather gloves (glv_leather) | studded gauntlets |
| heater_shield, buckler | kite shield (shd_kite) | heater and buckler shapes (the buckler is also much smaller) |

Finished-for-now visuals: plate_cuirass, leather_jerkin, apprentice_robe (robe + mantle), iron_helm, leather_cap, woven_hood, iron_gauntlets, leather_gloves, iron_greaves, leather_boots, sorcerer_boots, kite_shield, short_bow. Items with no row (weapons other than the bow, rings, amulets) change nothing on the body; swords and other weapons still use the game's existing held models.

## 8. Flag-off review (default presentation)

Changes to live files, all inert without `-- --modular` (verified by `modular_check.gd` without the flag: no appearance, fused knight mesh present, gauntlet fists mounted, equipping armour changes nothing):

- `character_model.gd`: `build(folder, clips, fists = true)`; default still builds the fists.
- `actor.gd`: `_build_model(..., fists = true)` passes it through.
- `player.gd`: `appearance` var (null by default), `refresh_appearance()` (no-op when null), `ModularAppearance.enabled_for(member_id)` is false without the flag; `_build_model` receives `fists = not modular`, i.e. true.
- `player_stats.gd`: three `p.refresh_appearance()` calls after equipment changes (no-op by default).
- `bow_attack.gd`: bow path picks the kit bow only when `p.appearance` has one; default still `BOW_MODEL`.
- `modular_appearance.gd` is a new class; it is only instantiated with the flag. Loading the script itself runs no code (static table is lazy).
Only effect when flag-off: one extra static call and an `OS.get_cmdline_user_args()` scan at hero creation.

Launch: `godot --path <repo> -- --modular` (hero uses the modular pieces; Cutter and every other actor keep the default look).

## 9. Verification run for the integration candidate

Godot renders (Forward+, 1280x720, only one screen available on the test machine):
- `docs/art/renders2/GAMEPLAY_*` real gameplay camera and character scale; `CLOSE_*` inspection camera (front/back/side, run, hit, death, atk_slash) for plate, leather, mage, mixed, archer.
- `docs/art/renders3/RIGDEMO_*` sword and shield on the live rig.
- `docs/art/renders4/BOW_*` draw, full draw, release, arrow in flight (live BowAttack and CompanionArrow).
No Blender previews are included.

Checks (all headless or windowed, none part of --selftest): `game/dev/modular_check.gd` (with and without `-- --modular`: equip, unequip, mixed sets, helm hiding hair/beard, hood hiding hair, robe hiding the gambeson, save and JSON restore, control switch hero/cutter, a fresh game scene rebuilt from a save), `game/dev/modular_bow_check.gd` (draw, release, arrow leaves the bow, both hands), `game/dev/modular_rig_demo.gd` (clips, sword, shield).
Known visual gaps: Mage and archer faces are plain (small nose, brow, eyes); hands are blocky; cloth has no physics; the robe hem can still clip a boot at extreme leg poses; leather and robe pieces were not inspected at 1080p or 1440p or with the controller; weapons other than the bow still use the game's held models.
