"""The project's art direction as prompt wording (see docs/ART_DIRECTION.md, which is the authority).

Every generator call (Meshy models, textures, icons, anything added later) goes through `styled()` so the style is never left
to a single prompt's memory.
"""

# Approved direction: Geometric Low-Poly Dark Fantasy (docs/ART_DIRECTION.md).
STYLE = ("gritty dark fantasy, geometric low-poly PS2-era-inspired geometry with clearly faceted forms and believable "
         "humanoid proportions, modern lighting, soft shadows and fog, worn weathered grimy materials, scratched dented metal, "
         "stained torn cloth, muted palette of steel, charcoal, leather, burgundy, brown, bone and moss with restrained ember "
         "accents, heavy and physical, strong silhouette readable from an elevated camera")

AVOID = ("no photorealism, no extremely detailed high-poly models, no excessively realistic textures, no cube-like characters, "
         "no cartoon or chibi proportions, no cute, no pristine, no shiny new, no shiny plastic, no glossy finish, no neon, "
         "no rainbow colours, no pastel")


def styled(prompt: str) -> str:
    """The prompt with the art direction appended (once)."""
    if "gritty dark fantasy" in prompt:
        return prompt
    return "%s. %s. %s" % (prompt.rstrip(". "), STYLE, AVOID)
