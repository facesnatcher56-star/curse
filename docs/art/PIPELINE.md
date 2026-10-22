# Art asset pipeline

The art direction is not decided yet (see [../ART_DIRECTION.md](../ART_DIRECTION.md)). This page sets the practical rules for
making models: export, rig, names, materials and budgets.

## Blender export (shared settings)

Blender is the source for hand-built models (`tools/blender/`). Every export uses these settings:

- **Format:** glTF Binary, `.glb` (`export_format="GLB"`).
- **Y-up:** on (`export_yup=True`). Godot reads glTF in Y-up.
- **Units and scale:** 1 Blender unit = 1 metre. A standard adult human is 1.8 m tall (matches `height_meters` in `tools/meshy.py`).
- **Apply transforms:** before export, apply scale and rotation on every exported object, and apply modifiers
  (`export_apply=True`). Origin sits at the feet, centred on the model.
- **Triangulate:** triangulate faces before export (Beauty method) and check the triangle count against the budgets below.
  Export the triangulated mesh; do not rely on the exporter's split.
- **Vertex colours and materials:** `export_vertex_color="ACTIVE"`, `export_materials="EXPORT"`. If vertex colours come out
  white on a joined mesh (Blender 5.2 exporter issue, see `tools/blender/make_crypt_props.py`), split the object by material and
  export each piece alone.

## Humanoid skeleton standard: the detailed hero skeleton (owner rule, 2026-10-22)

**Every playable character uses this skeleton, now and from now on** (owner, project-wide): the 54-bone detailed humanoid
rig first built for the barbarian hero, `assets/models/barbarian/rigged.glb` (source
`assets/art_staging/barbarian/source/barbarian.blend`). A new playable character is rigged to it from the start; do not ship
a playable character on a reduced skeleton (no fingers, no toes) or on its own bone names.

It is the knight2 game skeleton (24 bones, the names, parents and **rest rotations** the game clips and code use) plus
**three joints per finger** with Mixamo names, so Mixamo-style animations retarget onto it and hands can open, close and grip.
One armature object, `Armature`, bones in centimetres with the object scaled 0.01 (as knight2), `Hips` the top bone (no `Root`).

| Bone | Parent | Notes |
| --- | --- | --- |
| `Hips` | none (top bone) | Pelvis; drives the body. Clips key its position. |
| `Spine02`, `Spine01`, `Spine` | `Hips`, then the one above | Spine chain; `Spine` is the chest. |
| `neck` | `Spine` | Lowercase, as in the Knight. |
| `Head` | `neck` | |
| `head_end`, `headfront` | `Head` | Top of the head and the face direction (helpers; no skin weights). |
| `LeftShoulder`, `LeftArm`, `LeftForeArm`, `LeftHand` | `Spine` | Collarbone, upper arm, forearm, wrist. |
| `RightShoulder`, `RightArm`, `RightForeArm`, `RightHand` | `Spine` | Mirror of the left side. |
| `LeftHandThumb1..3`, `LeftHandIndex1..3`, `LeftHandMiddle1..3`, `LeftHandRing1..3`, `LeftHandPinky1..3` | `LeftHand`, then the joint before | 15 finger joints per hand. |
| `RightHandThumb1..3` ... `RightHandPinky1..3` | `RightHand`, then the joint before | Mirror of the left side. |
| `LeftUpLeg`, `LeftLeg`, `LeftFoot`, `LeftToeBase` | `Hips` | Hip, knee, ankle, toes. |
| `RightUpLeg`, `RightLeg`, `RightFoot`, `RightToeBase` | `Hips` | Mirror of the left side. |

- **Rest pose:** the 24 core bones keep knight2's rest rotations exactly (checked to within 0.1 degree), so the game clips play
  on any character built to the standard; only joint positions follow the character's own proportions. The arms are in the
  knight's A-pose (elbows bent forward). Fingers rest **closed in the weapon grip**: no game clip keys them yet, so they hold
  that grip, and an animation that does key them can open the hand.
- **Feet on the ground:** the lowest sole vertex at height 0 in the rest pose.
- **Clips from a rig with other proportions:** `CharacterModel.ANIM_SOURCE` borrows another rig's clips; the hips track is
  moved by the difference of the two rests and other position tracks are dropped (`CharacterModel._borrowed`).
- Weapons attach to `RightHand` (or `LeftHand` for off-hand items). Do not add extra attachment bones.
- Equipment is made to fit the character, never the character to the equipment (owner). Pieces are skinned to these bone
  names. The barbarian has no item models yet (new weapons, armour and animations are to be built for him), so he shows
  none: `equipment_pieces: false` in `data/appearance/equipment_visuals.json`.
- The old knight2 rig (`assets/models/knight2`, 24 bones, no fingers, hands replaced by gauntlet fists) is the clip source and
  the reference for the rest rotations; it is no longer the target for new playable characters.

## Enemy rigs

Enemy rigs are **independent** unless a shared clip set requires compatibility. Independent monster rigs are allowed where
justified, for example the staging zombie and warden. An enemy does not have to use the humanoid standard, and the player's
bone table does not bind enemies. Enemy clips are keyed by the names in `game/data/enemy_def.gd` (`clips`, default `idle`,
`walk`, `attack`, `hit`, `death`, and `attack_clip`), so an enemy rig must provide clips under those names to work with its
definition.

**Open item (owner and Lane B):** Lane B's zombie and warden prototypes use the experiment knight skeleton. Whether they stay on
that rig or move to a shared enemy skeleton is not decided here. Decide that with the owner before any further enemy rig is
built. Until then, prototype enemies keep their current rig and their clips must match the `enemy_def.gd` names.

## Naming conventions

- **Files:** lowercase snake_case, prefixed by class: `char_knight_hero.glb`, `enemy_zombie_walker.glb`, `prop_barrel_wood.glb`,
  `env_house_small.glb`. Existing folders keep their `model.glb` names until they are next re-exported.
- **Objects and meshes:** PascalCase with a role: `Body`, `Head`, `ArmorPauldronL`, `ArmorPauldronR`, `Sword`.
- **Armatures:** `Armature` for player rigs, matching knight2; `Rig_<Name>` for enemy and other rigs.
- **Bones:** the names in the player skeleton table above for player equipment; enemy rigs name their own bones.
- **Materials:** lowercase snake_case, no prefix: `iron`, `dark_steel`, `leather_dark`, `wood`, `bone`, `moss`.
- **Textures:** `<asset>_<map>.png`, for example `barbarian_basecolor.png`, `barbarian_normal.png`.

## Materials

- **No fixed limit on materials or textures** (owner, 2026-10-22). Use as many materials and texture maps (base colour,
  normal, roughness, metallic, and so on) at whatever resolution the asset needs to look right.
- **Matte by default.** Roughness is high (about 0.7 to 1.0) for cloth, leather, stone, wood and moss. Metals use a high
  roughness with a worn look (about 0.4 to 0.6); no mirror-polished chrome. Metallic is 1.0 only on steel and iron parts.
- **Palette:** muted steel, charcoal, leather, burgundy, brown, bone and moss. One or two warm accents at most (embers, torches,
  magic glow).

## Triangle budgets

Counts are triangles after triangulation, for the visible geometry of the asset in its normal state. These are **guidelines**,
not substitutes for artistic judgment. They match the `POLYCOUNT` table in `tools/meshy.py`, which sets Meshy's target per
category.

| Asset class | Guideline | Meshy target (`POLYCOUNT`) | Examples |
| --- | --- | --- | --- |
| Character (hero, fully equipped) | 5,000 to 12,000 | 8,000 | The main character with armour, weapons and shield. |
| Enemy, standard | 1,500 to 2,500 | 2,000 | Zombies, ghouls, spitters. |
| Enemy, elite or boss | 3,000 to 6,000 | 4,500 | Named monsters, bosses. |
| NPC, standard | 2,000 to 4,000 | 3,000 | Townsfolk, vendors, companions. |
| Prop, small | hundreds (about 300 to 900) | 500 | Barrels, crates, weapons, small items. |
| Environment piece, large | by visible scale | 3,000 (placeholder) | Building, wall section, gate, large rock or tree. Set per asset from its visible size. |

- **Hero is a preferred target, not a rejection threshold.** Measure the visible geometry for representative equipment
  combinations (for example, light and heavy armour, one-handed and two-handed weapon), not the sum of every alternative item.
  A modest overage is acceptable when silhouette, deformation and performance justify it. Record the reason in the commit.
- **Hidden geometry.** Do not render geometry that is never seen. Remove interior faces that sit inside armour or clothing, and
  hide (or remove from the export) equipment that is not worn. Count only what is visible in the normal equipped state.
- Foliage and very small pieces should stay well under their class guideline. Reduce the mesh first when an asset is over.

## Checks before an asset is accepted

1. Visible triangle count is within its class guideline, or the overage is justified in the commit.
2. Origin at the feet (or the base for props), scale in metres, transforms applied.
3. Player characters and equipment follow the humanoid skeleton standard above (54 bones, rest pose as described), under one armature. Enemy rigs follow the Enemy rigs section.
4. Names follow the conventions above.
5. Reads as a silhouette from the far zoom-out.

## Open items

- **Enemy rig decision (owner and Lane B):** whether Lane B's zombie and warden prototypes stay on the experiment knight skeleton or
  move to a shared enemy skeleton. Not decided here.
- **Experiment rig:** differs from knight2 in bone names and rest pose. Lane A retargets its kit onto knight2 (a05f2ac).
- **knight2** (`assets/models/knight2/rigged.glb`, 22,845 triangles unequipped) is being replaced. Do not optimise it.
- **Environment budget:** no fixed number yet; set per asset from visible scale.
