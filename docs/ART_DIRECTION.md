# Art direction: gritty and versatile

This is the visual rule for everything in Curse, whatever made it: Meshy models and animations, generated icons and images,
hand-written shaders and particle effects, UI, and (in spirit) sound. If an asset does not fit this page, it is redone, not
excused. When this page and a prompt, a tool default or a convenient shortcut disagree, this page wins.

## In one line

**Dark, grounded, worn-out fantasy: everything looks handled, dirty and used. Gritty first, and versatile enough to stretch across
every enemy, prop and place without drifting out of the same world.**

## Gritty

- **Weathered, never pristine.** Scratched and dented metal, stained cloth, cracked stone, rot, soot, dried blood, mud. Nothing
  looks new, clean or toy-like.
- **Muted, desaturated palette** (earth, iron, bone, ash, sickly green and grey-blue flesh) so the few warm accents stand out:
  firelight, embers, torches, blood, magic. Saturated rainbow colour and candy gradients are out.
- **Realistic hand-painted PBR**: believable materials with roughness and wear, not flat cartoon shading and not glossy plastic.
  Dark fantasy realism, not anime and not low-poly cute.
- **Heavy and physical.** Weight, impact and consequence read in the art: blows crunch, bodies drop, ground cracks. Effects are
  dirty and dense (smoke, dust, grit, embers), not clean glitter, bokeh or neon.
- **Low-key lighting.** Dark ambient scenes with warm, directional light and deep shadow; contrast comes from light, not from
  bright flat colour.

## Versatile

- **One material language** across hero, enemies, props and environment: the same grit, the same palette rules, the same level
  of wear, so a new enemy or prop drops into the world without looking imported.
- **Readable first.** This is a fixed 3/4 camera that can pull far back: every character and prop needs a strong silhouette and
  a clear read at a distance. Detail is for up close; silhouette and value contrast do the work.
- **Range without breaking style.** Different factions, biomes and bosses vary shape, scale and accent colour (acid green
  spitters, bloated sickly bloaters, cold grey priests) while sharing the same worn, grimy treatment.
- **Systems, not one-offs.** Prefer a reusable rule (a wear/grime treatment, a palette, a particle recipe) to a one-time trick,
  so new content can be made in the same style by anyone.

## Applying it (checklist for any new asset)

1. Does it look used and weathered? Is there dirt, damage or age in the material?
2. Is the palette muted, with at most one or two warm accents?
3. Does it read as a silhouette from the far zoom-out?
4. Does it sit next to the hero and the existing enemies without standing out as a different style?
5. For effects: is it dense and physical (dust, debris, embers, smoke) rather than clean and sparkly? Is it readable at a glance
   (see Earthshatter: one clear shockwave, not a pile of overlapping effects)?
6. For UI and icons: dark, worn metal and parchment, muted with a warm accent; no bright saturated gradients.

## Prompt wording (Meshy and other generators)

`tools/art_direction.py` holds the shared wording; `tools/meshy.py` and `tools/meshy_icons.py` add it automatically. Anything
that sends a prompt to a generator must include it. Short form:

> gritty dark fantasy, worn weathered grimy materials, scratched dented metal, stained torn cloth, muted desaturated palette with
> warm ember accents, realistic hand-painted PBR, heavy and physical, readable silhouette, low-key dramatic lighting

Avoid in prompts: cartoon, cute, chibi, clean, pristine, shiny new, glossy, neon, rainbow, saturated, pastel, low-poly.

## Sound

Impacts are heavy and gritty: crunch, thud, scrape, wet and dry. Real recordings over thin synthesised bleeps; nothing cartoonish
or sparkly. (Only user-supplied sounds are in the game for now.)
