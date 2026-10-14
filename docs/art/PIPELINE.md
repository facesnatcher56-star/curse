# Art asset pipeline

The visual rules are in [../ART_DIRECTION.md](../ART_DIRECTION.md): Geometric Low-Poly Dark Fantasy. This page sets the
practical rules for making models: export, rig, names, materials and budgets. Where the two disagree, ART_DIRECTION wins.

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

## Player skeleton standard (knight2 game rig)

The live knight2 game skeleton, `assets/models/knight2/rigged.glb`, is the **target for modular player equipment**. Lane A has
demonstrated the live-game path: its equipment kit is retargeted onto knight2 (commit a05f2ac). The table below is verified
against that rig, read directly from its skin. It has **24 joints** under one armature object, `Armature`, with `Hips` under it.
There is **no `Root` bone**: `Hips` is the top bone.

The experiment rig is **not interchangeable** with knight2. It differs in bone names and rest pose, so animation clips, bone
attachments and the Godot code (`game/character_model.gd`) cannot be assumed to carry over. Do not build player equipment to the
experiment rig.

| Bone | Parent | Notes |
| --- | --- | --- |
| `Hips` | none (top bone) | Pelvis; drives the body. |
| `Spine02`, `Spine01`, `Spine` | `Hips`, then the one above | Spine chain; `Spine` is the chest. |
| `neck` | `Spine` | Lowercase, as in the Knight. |
| `Head` | `neck` | |
| `head_end`, `headfront` | `Head` | Helper bones present in the Knight; kept for compatibility. Their deformation role is not verified. |
| `LeftShoulder`, `LeftArm`, `LeftForeArm`, `LeftHand` | `Spine` | Shoulder to hand. |
| `RightShoulder`, `RightArm`, `RightForeArm`, `RightHand` | `Spine` | Mirror of the left side. |
| `LeftUpLeg`, `LeftLeg`, `LeftFoot`, `LeftToeBase` | `Hips` | Leg chain. |
| `RightUpLeg`, `RightLeg`, `RightFoot`, `RightToeBase` | `Hips` | Mirror of the left side. |

- **Rest pose: A-pose**, as the Knight's animation clips are built on it (owner direction). Do not use a T-pose rest.
- No finger bones. Hands are a single grip shape (the Knight's hands have no finger rig, and the code relies on that).
- Weapons attach to `RightHand` (or `LeftHand` for off-hand items). Do not add extra attachment bones.

## Enemy rigs

Enemy rigs are **independent** unless a shared clip set requires compatibility. An enemy does not have to use the player's
skeleton, and the player's bone table does not bind enemies. Enemy clips are keyed by the names in `game/data/enemy_def.gd`
(`clips`, default `idle`, `walk`, `attack`, `hit`, `death`, and `attack_clip`), so an enemy rig must provide clips under those
names to work with its definition.

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
- **Textures (only if used):** `<asset>_atlas.png`, one per asset.

## Materials

- **Flat or limited palette.** Prefer flat colours and vertex colours. Use at most **4 materials** per asset.
- **One texture atlas at most** per asset, at 1024 px or 512 px, only when a vertex-colour look cannot carry the detail. Do not add
  separate normal, roughness or metallic maps; roughness and metallic are set per material as flat values.
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
3. Player equipment follows the player skeleton table above, rest pose A-pose, under one armature. Enemy rigs follow the Enemy rigs section.
4. Names follow the conventions above; at most 4 materials and at most one atlas.
5. Reads as a silhouette from the far zoom-out, and matches the look in ART_DIRECTION.md.

## Open items

- **Enemy rig decision (owner and Lane B):** whether Lane B's zombie and warden prototypes stay on the experiment knight skeleton or
  move to a shared enemy skeleton. Not decided here.
- **Experiment rig:** differs from knight2 in bone names and rest pose. Lane A retargets its kit onto knight2 (a05f2ac).
- **knight2** (`assets/models/knight2/rigged.glb`, 22,845 triangles unequipped) is being replaced. Do not optimise it.
- **Environment budget:** no fixed number yet; set per asset from visible scale.
