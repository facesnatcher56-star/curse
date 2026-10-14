# Art direction: Geometric Low-Poly Dark Fantasy

This is the visual rule for everything in Curse, whatever made it: Meshy models and animations, generated icons and images,
hand-written shaders and particle effects, UI, and (in spirit) sound. If an asset does not fit this page, it is redone, not
excused. When this page and a prompt, a tool default or a convenient shortcut disagree, this page wins.

The asset pipeline rules (Blender export, skeleton, naming, materials and triangle budgets) are in
[art/PIPELINE.md](art/PIPELINE.md). The humanoid standard is the live knight2 game skeleton
(`assets/models/knight2/rigged.glb`), not the experimental Blender rig. Independent monster rigs are allowed where justified.

## In one line

**Dark, grounded, worn-out fantasy built from clearly faceted low-poly geometry: everything looks handled, dirty and used, and
it reads from far away. Gritty first, and versatile enough to stretch across every enemy, prop and place without drifting out
of the same world.**

## Approved direction: Geometric Low-Poly Dark Fantasy

Geometric low-poly dark fantasy. Character and environment geometry takes its cue from PS2-era games, combined with modern
lighting, materials, shadows, fog and atmospheric effects. This is not exact PS2 technical limits and not deliberately ugly
graphics.

- **Believable humanoid proportions.** Characters read as people in armour and cloth, not blocks or toys.
- **Clearly faceted polygonal geometry.** The facets are visible on purpose. Detail comes from silhouette, value and
  material wear, not from high-poly surface detail.
- **Stylized armour, clothing, buildings, enemies, foliage and weapons** that share the same faceted language.
- **Strong silhouettes readable from an elevated camera.** The fixed 3/4 camera pulls far back; the shape must read first.
- **Palette:** muted steel, charcoal, leather, burgundy, brown, bone and moss. Restrained fire and magic: warm embers and
  glows are accents, not the scene.
- **Worn, weathered materials** that keep the dark-fantasy atmosphere: scratches, dents, stains, soot, rot, moss and grime.

## Gritty

- **Weathered, never pristine.** Scratched and dented metal, stained cloth, cracked stone, rot, soot, dried blood, mud. Nothing
  looks new, clean or toy-like.
- **Muted palette** (steel, charcoal, leather, burgundy, brown, bone, moss, ash) so the few warm accents stand out: firelight,
  embers, torches, blood, magic. Saturated rainbow colour and candy gradients are out.
- **Modern materials, faceted forms.** Roughness and wear are part of the read, and the surfaces are matte. Nothing glossy or
  plastic-shiny. Textures are simple and worn, not excessively realistic.
- **Heavy and physical.** Weight, impact and consequence read in the art: blows crunch, bodies drop, ground cracks. Effects are
  dirty and dense (smoke, dust, grit, embers), not clean glitter, bokeh or neon.
- **Low-key lighting with atmosphere.** Dark ambient scenes with warm, directional light, deep shadow, fog and haze; contrast
  comes from light, not from bright flat colour.

## Versatile

- **One material language** across hero, enemies, props and environment: the same grit, the same palette rules, the same level
  of wear, so a new enemy or prop drops into the world without looking imported.
- **Readable first.** This is a fixed 3/4 camera that can pull far back: every character and prop needs a strong silhouette and
  a clear read at a distance. Detail is for up close; silhouette and value contrast do the work.
- **Range without breaking style.** Different factions, biomes and bosses vary shape, scale and accent colour (acid green
  spitters, bloated sickly bloaters, cold grey priests) while sharing the same faceted, worn, grimy treatment.
- **Systems, not one-offs.** Prefer a reusable rule (a wear/grime treatment, a palette, a particle recipe) to a one-time trick,
  so new content can be made in the same style by anyone.

## Applying it (checklist for any new asset)

1. Does it look used and weathered? Is there dirt, damage or age in the material?
2. Is the geometry clearly faceted with believable humanoid proportions (no cube-like characters, no chibi or cartoon
   proportions)?
3. Is the palette muted, with at most one or two warm accents?
4. Does it read as a silhouette from the far zoom-out?
5. Does it sit next to the hero and the existing enemies without standing out as a different style?
6. For effects: is it dense and physical (dust, debris, embers, smoke) rather than clean and sparkly? Is it readable at a glance
   (see Earthshatter: one clear shockwave, not a pile of overlapping effects)?
7. For UI and icons: dark, worn metal and parchment, muted with a warm accent; no bright saturated gradients.

## Prompt wording (Meshy and other generators)

`tools/art_direction.py` holds the shared wording, in two helpers. `styled_3d()` is for models, textures and environment pieces
(`tools/meshy.py` uses it). `styled_2d()` is for ability icons, inventory icons and UI art (`tools/meshy_icons.py` uses it).
Do not put 3D modelling wording into 2D prompts. Each helper appends its direction unless the exact text is already present.
Anything that sends a prompt to a generator must go through one of them. Short form (3D):

> gritty dark fantasy, geometric low-poly PS2-era-inspired geometry with clearly faceted forms and believable humanoid
> proportions, modern lighting, soft shadows and fog, worn weathered grimy materials, muted palette of steel, charcoal, leather,
> burgundy, brown, bone and moss with restrained ember accents, strong silhouette readable from an elevated camera

Avoid in prompts: photorealism, extremely detailed high-poly models, excessively realistic textures, cube-like characters,
cartoon or chibi proportions, cute, pristine, shiny new, glossy, shiny plastic, neon, rainbow, saturated, pastel.

## Sound

Impacts are heavy and gritty: crunch, thud, scrape, wet and dry. Real recordings over thin synthesised bleeps; nothing cartoonish
or sparkly. (Only user-supplied sounds are in the game for now.)
