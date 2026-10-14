# Art asset pipeline

The visual rules are in [../ART_DIRECTION.md](../ART_DIRECTION.md): geometric low-poly dark fantasy. This page sets the
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

## Humanoid skeleton standard

All humanoid characters (heroes, NPCs, humanoid enemies) use **one shared armature**, `Rig_Humanoid`. Do not make a new rig per
character. Bone names follow the Mixamo-style names the Knight rig already uses, because the Godot code finds bones by these names
(`game/character_model.gd`).

| Bone | Parent | Notes |
| --- | --- | --- |
| `Root` | none | At the feet, origin of the model. |
| `Hips` | `Root` | Pelvis; drives the body. |
| `Spine`, `Spine1`, `Spine2` | `Hips` | Chest is `Spine2`. |
| `Neck`, `Head` | `Spine2` | |
| `LeftShoulder`, `LeftArm`, `LeftForeArm`, `LeftHand` | `Spine2` | Shoulder to hand. |
| `RightShoulder`, `RightArm`, `RightForeArm`, `RightHand` | `Spine2` | Mirror of the left side. |
| `LeftUpLeg`, `LeftLeg`, `LeftFoot`, `LeftToeBase` | `Hips` | `LeftToeBase` optional. |
| `RightUpLeg`, `RightLeg`, `RightFoot`, `RightToeBase` | `Hips` | Mirror of the left side. |

- No finger bones. Hands are a single grip shape (the Knight's hands have no finger rig, and the code relies on that).
- Bind pose: arms straight out in a T-pose, so weapons and clothing fit before animation.
- Weapons attach to `RightHand` (or `LeftHand` for off-hand items). Do not add extra attachment bones.

## Naming conventions

- **Files:** lowercase snake_case, prefixed by class: `char_knight_hero.glb`, `enemy_zombie_walker.glb`, `prop_barrel_wood.glb`,
  `env_house_small.glb`. Existing folders keep their `model.glb` names until they are next re-exported.
- **Objects and meshes:** PascalCase with a role: `Body`, `Head`, `ArmorPauldronL`, `ArmorPauldronR`, `Sword`.
- **Armatures:** `Rig_Humanoid` for characters; `Rig_<Name>` for any other rig.
- **Bones:** exactly the names in the skeleton table above.
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

These are the caps per exported asset (triangles, after triangulation). Aim below the cap; do not go over without asking.

| Asset class | Budget | Examples |
| --- | --- | --- |
| Character (hero) | 5,000 | The Knight, the player-controlled hero. |
| Enemy | 2,500 | Standard zombies, ghouls, spitters. |
| Enemy, elite or boss | 6,000 | Named monsters, bosses. |
| NPC | 3,000 | Townsfolk, vendors, companions. |
| Prop | 1,000 | Barrels, crates, weapons, small items. Tiny props (under 0.5 m) target 300. |
| Environment piece | 2,000 | Building, wall section, gate, large rock or tree. |

Foliage and very small pieces should stay well under these caps. If an asset needs more than its budget, reduce the mesh first;
ask the owner before raising a budget.

## Checks before an asset is accepted

1. Triangle count is within its class budget.
2. Origin at the feet (or the base for props), scale in metres, transforms applied.
3. Skeleton (humanoids only) uses `Rig_Humanoid` with the standard bone names.
4. Names follow the conventions above; at most 4 materials and at most one atlas.
5. Reads as a silhouette from the far zoom-out, and matches the look in ART_DIRECTION.md.
