"""The project's art direction as prompt wording (see docs/ART_DIRECTION.md, which is the authority).

Every generator call (Meshy models, textures, icons, anything added later) goes through `styled()` so the style is never left
to a single prompt's memory.
"""

STYLE = ("gritty dark fantasy, worn weathered grimy materials, scratched dented metal, stained torn cloth, "
         "muted desaturated palette with warm ember accents, realistic hand-painted PBR, heavy and physical, "
         "readable silhouette, low-key dramatic lighting")

AVOID = "no cartoon, no cute, no chibi, no pristine, no shiny new, no glossy plastic, no neon, no rainbow colours, no pastel"


def styled(prompt: str) -> str:
    """The prompt with the art direction appended (once)."""
    if "gritty dark fantasy" in prompt:
        return prompt
    return "%s. %s. %s" % (prompt.rstrip(". "), STYLE, AVOID)
