# Notes for agents

Read [docs/DEVELOPMENT_RULES.md](docs/DEVELOPMENT_RULES.md) before accepting development tasks. It is the
shared engineering and multi-agent policy. The owner's standing instructions below still apply.

Read [CLAUDE.md](CLAUDE.md) first. Its required checks and ask-when-uncertain rule apply to
every agent working on this project. Check the whole gameplay context and equivalent uses
of a mechanic, not just the edited component.

Visual verification is risk-based, as set out in CLAUDE.md, docs/UI_THEME.md and
docs/DEVELOPMENT_RULES.md. Minor localized UI changes need one representative inspection;
significant layout changes need representative resolutions and scale boundaries; only global
display, scaling or layout-system changes need the complete matrix. Screenshot inspection is
required when appearance changes and a display is available. Disclose any deferred visual check.

Standing visual direction for all new or revised art and gameplay effects: build in deliberate
contrast so the subject reads and pops against its actual gameplay surroundings. Use clear
value and color separation, a strong silhouette, and controlled highlights; avoid muddy,
washed-out, or low-contrast results that blend into the player, ground, or background. Judge
the effect in its real gameplay context, not just on an isolated preview, and keep the contrast
coherent with the established art direction.

Standing owner instruction, including future tasks: whenever uncertainty remains, ask the
owner before implementing the uncertain part. Do not guess. This applies to all agents.

Dungeon Siege II combat is the baseline; follow [docs/COMBAT_REFERENCE.md](docs/COMBAT_REFERENCE.md).
