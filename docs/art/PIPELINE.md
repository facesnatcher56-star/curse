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

## Humanoid skeleton standard

The reference is the Knight rig, `assets/models/knight2/rigged.glb`, read directly from its skin. It has **24 joints** and one
armature object, `Armature`, under which `Hips` sits. There is **no `Root` bone**: `Hips` is the top bone, and the armature
object is the root node. Every humanoid (heroes, NPCs, humanoid enemies) uses this same 24-bone set, with these names and
parents, so animation clips and the Godot code (`game/character_model.gd`) find the same bones on every character.

| Bone | Parent | Notes |
| --- | --- | --- |
| `Hips` | none (top bone) | Pelvis; drives the body. |
| `Spine02`, `Spine01`, `Spine` | `Hips`, then the one above | Spine chain; `Spine` is the chest. |
| `neck` | `Spine` | Lowercase, as in the Knight. |
| `Head` | `neck` | |
| `head_end`, `headfront` | `Head` | Helper bones present in the Knight; keep them for compatibility. Their deformation role is not verified. |
| `LeftShoulder`, `LeftArm`, `LeftForeArm`, `LeftHand` | `Spine` | Shoulder to hand. |
| `RightShoulder`, `RightArm`, `RightForeArm`, `RightHand` | `Spine` | Mirror of the left side. |
| `LeftUpLeg`, `LeftLeg`, `LeftFoot`, `LeftToeBase` | `Hips` | Leg chain. |
| `RightUpLeg`, `RightLeg`, `RightFoot`, `RightToeBase` | `Hips` | Mirror of the left side. |

- **Rest pose: A-pose**, as the Knight's animation clips are built on it (owner direction). Do not use a T-pose rest.
- No finger bones. Hands are a single grip shape (the Knight's hands have no finger rig, and the code relies on that).
- Weapons attach to `RightHand` (or `LeftHand` for off-hand items). Do not add extra attachment bones.
- One shared armature per humanoid type; new characters reuse this bone set rather than a new rig.

## Naming conventions

- **Files:** lowercase snake_case, prefixed by class: `char_knight_hero.glb`, `enemy_zombie_walker.glb`, `prop_barrel_wood.glb`,
  `env_house_small.glb`. Existing folders keep their `model.glb` names until they are next re-exported.
- **Objects and meshes:** PascalCase with a role: `Body`, `Head`, `ArmorPauldronL`, `ArmorPauldronR`, `Sword`.
- **Armatures:** `Armature` for humanoid rigs, matching the Knight; `Rig_<Name>` for any other rig.
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

Counts are triangles after triangulation, for the asset as it is rendered.

| Asset class | Target | Examples |
| --- | --- | --- |
| Character (hero, fully equipped) | 5,000 to 12,000 | The Knight with armour, weapons and shield equipped. |
| Enemy | 2,500 (cap) | Standard zombies, ghouls, spitters. |
| Enemy, elite or boss | 6,000 (cap) | Named monsters, bosses. |
| NPC | 3,000 (cap) | Townsfolk, vendors, companions. |
| Prop | 1,000 (cap) | Barrels, crates, weapons, small items. Tiny props (under 0.5 m) target 300. |
| Environment piece | 2,000 (cap) | Building, wall section, gate, large rock or tree. |

- **Hero range.** The hero target is a range, not a hard limit, because the number of equipped pieces varies. Going above
  12,000 needs a performance reason and owner agreement; record the reason in the asset's commit.
- **Hidden geometry.** Do not ship geometry that is never seen. Remove interior faces that sit inside armour or clothing, and
  hide (or remove from the export) equipment that is not worn, so the renderer does not draw it. Count only what is visible
  in the normal equipped state.
- Foliage and very small pieces should stay well under these caps. Reduce the mesh first when an asset is over its budget.

## Checks before an asset is accepted

1. Triangle count is within its class target or cap, with hidden geometry removed.
2. Origin at the feet (or the base for props), scale in metres, transforms applied.
3. Humanoids use the 24-bone skeleton table above, rest pose A-pose, under one armature.
4. Names follow the conventions above; at most 4 materials and at most one atlas.
5. Reads as a silhouette from the far zoom-out, and matches the look in ART_DIRECTION.md.

## Open issues

- The current Knight (`assets/models/knight2/rigged.glb`) is **22,845 triangles** with no equipment, which is above the hero
  range. Reduce it, or record an agreed performance exception. Owner decision needed.
