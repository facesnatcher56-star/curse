# Barbarian hero build (Blender, through the Blender MCP)

How `assets/models/barbarian/rigged.glb` was made; rerun these to rebuild or to make the next playable character on the
detailed humanoid skeleton (docs/art/PIPELINE.md, "Humanoid skeleton standard"). Run each file inside Blender
(`exec(open(path).read(), ns)` through the Blender MCP).

Sources in `assets/art_staging/barbarian/source/`:
- `barbarian_mpfb_editable.blend`: the MPFB2 body (MakeHuman shape targets still live), skin, hair, eyes, beard, briefs
  and the MPFB game-engine rig, before posing. Edit the character here.
- `barbarian.blend`: the finished game rig and meshes (what is exported).
- `bake_pos.exr`, `bake_nrm.exr`: the body's object-space position and normal baked into its UV layout; the skin painter
  reads them to place paint in 3D.

Scripts:
1. `paint_skin.py`: tan, beard shadow, woad war paint, tattoos and the scar, written into `barbarian_basecolor.png`;
   also the beard strand texture `barbarian_beard.png`.
2. With `barbarian_mpfb_editable.blend` open, `rebuild_after_open.py` runs the rest:
   - `pose_to_knight.py`: pose the MPFB rig so every limb points as the knight2 bone does, and close the hands in the grip.
   - `build_game_rig.py`: freeze the meshes in that pose and build the game skeleton: knight2 names and rest rotations,
     these joint positions, three Mixamo-named joints per finger; weights moved over.
   - `export_prep.py`: plain image materials glTF can carry (hair tint baked, leather briefs), mouth parts reduced.
   - joins the head parts into `body_skin`, names the base pieces, exports, saves `barbarian.blend`.
3. `ground_and_export.py` (with `barbarian.blend` open): stands the rig on the ground (lowest sole at 0) and exports.

After exporting, Godot must import the new GLB (focus the editor, or a headless `--import`).
