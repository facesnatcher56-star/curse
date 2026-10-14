"""The project's art direction as prompt wording (see docs/ART_DIRECTION.md, which is the authority).

Approved direction: Geometric Low-Poly Dark Fantasy. Two helpers, because 3D modelling words do not belong in 2D prompts:

- styled_3d(prompt): models, textures and environment pieces (Meshy text-to-3D and its texture prompts).
- styled_2d(prompt): ability icons, inventory icons and UI art (Meshy text-to-image).

Both append their style and avoid text unless that exact style text is already in the prompt, so re-running a prompt never
doubles the wording and a prompt never ends up without the direction.
"""

# 3D: polygonal geometry, strong silhouettes, stylized matte surfaces.
STYLE_3D = ("gritty dark fantasy, geometric low-poly PS2-era-inspired polygonal geometry, clearly faceted forms, believable "
            "humanoid proportions, stylized matte surfaces with simple worn textures, scratched dented metal, stained torn cloth, "
            "muted steel, charcoal, leather, burgundy, brown, bone and moss with restrained ember accents, modern lighting "
            "with soft shadows and fog, strong silhouette readable from an elevated camera")
AVOID_3D = ("no photorealism, no extremely detailed high-poly models, no excessively realistic textures, no cube-like characters, "
            "no cartoon or chibi proportions, no shiny plastic, no pristine, no neon, no rainbow colours, no pastel")

# 2D: readable composition and material identity, no 3D modelling terms.
STYLE_2D = ("gritty dark fantasy game art, one recognizable subject, readable composition, clear material identity (worn steel, "
            "leather, bone, cloth), muted palette of charcoal, burgundy, brown, bone and moss with restrained ember accents, "
            "dark atmospheric background with fog, strong value contrast, clear at small sizes")
AVOID_2D = ("no photorealism, no text, no border, no frame, no cute, no cartoon, no pristine, no shiny new, no glossy plastic, "
            "no neon, no rainbow colours, no pastel, no clutter")


def _apply(prompt: str, style: str, avoid: str) -> str:
    """The prompt with the style and avoid text appended, unless that style text is already there."""
    if style in prompt:
        return prompt
    return "%s. %s. %s" % (prompt.rstrip(". "), style, avoid)


def styled_3d(prompt: str) -> str:
    """Prompt for a 3D model, texture or environment piece, with the approved 3D direction."""
    return _apply(prompt, STYLE_3D, AVOID_3D)


def styled_2d(prompt: str) -> str:
    """Prompt for an icon or UI image, with the approved 2D direction (no 3D modelling terms)."""
    return _apply(prompt, STYLE_2D, AVOID_2D)


def styled(prompt: str) -> str:
    """Backward-compatible name for styled_3d (models and their texture prompts)."""
    return styled_3d(prompt)
