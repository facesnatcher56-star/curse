# Wood elf (Cutter) build (Blender, through the Blender MCP)

Sources in `assets/art_staging/elf/source/`: `elf_mpfb_editable.blend` (the MPFB2 body, hair, eyes, briefs and rig, before
posing; edit the character here), `elf.blend` (the finished game rig), `elven_bow.blend`, the painted textures and the
position/normal bakes.

1. With `elf_mpfb_editable.blend` open: `paint_skin.py` (freckles, leaf marks by the eyes, the forearm vine), then
   `build.py` (runs the shared `../hero/` steps: pose to the knight2 rest, 54-bone skeleton, ground; exports
   `assets/models/elf/rigged.glb`).
2. On an empty scene: `make_elven_bow.py` builds the bow to the game's bow contract (see its header) and its textures;
   export it to `assets/models/elf/items/elven_bow.glb`. It is listed in `data/appearance/equipment_visuals.json`
   (`rigs` → elf → `item_models` → `short_bow`), so the archer code shows it, strung.

3. On an empty scene: `make_elven_arrow_quiver.py` builds the arrow (0.92 m, point up) and the quiver (0.78 m with the
   arrows standing in it) and exports both to `assets/models/elf/items/`. They are listed with the bow (`arrow`,
   `quiver`): the archer nocks and shoots that arrow, and the quiver rides on his back.

After exporting, Godot must import the new GLBs.

4. Joints: with `elf.blend` open, `../hero/joint_quality.py` (MESHES = body_skin, clt_briefs) adds the twist and joint-helper
   bones and re-blends the joint weights, then `../hero/ground_and_export.py` re-exports `rigged.glb` (63 bones).
5. Bow clips: `elf_bow_anims.blend` holds the IK control rig and the clips; `bow_anims.py` keys, checks, bakes and previews them
   (`build_clip`, `check_clip`, `ring`, `preview_action`). Export the three clips (bow_idle, bow_draw, bow_release, one NLA
   track each) to `assets/art_staging/elf/bow_clips.glb`, then `godot --headless --path . --script tools/build_elf_anims.gd`.
   The latest clips (whole-body stance) live in `elf_stylized.blend`, which also holds the trial ranger outfit
   (`stylized_outfit.py`; not in the game).
