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

After exporting, Godot must import the new GLB.
