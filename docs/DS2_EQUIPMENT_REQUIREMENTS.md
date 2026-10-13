# DS2 equipment requirements

`EquipmentRequirement` parses the requirement strings preserved in
`data/reference/ds2_equipment_catalog.json`. `Items.hero_can_wear` uses the same
evaluator before the live `PlayerStats.equip` mutation; town purchases and item
comparisons use that result and render the actual unmet values.

Supported catalog syntax:

- Dynamic `#item_level` thresholds with the catalog's signed numeric offset, and fixed numeric thresholds.
- Class skills: `melee`, `ranged`, `combat magic`, and `nature magic`; `uber` is character level.
- Attributes: strength, dexterity and intelligence. Eligibility uses effective values including worn item and set bonuses.
- Passive ranks from actual acquired skills. The source key `aegis` maps to Curse's Barricade. A catalog passive that Curse has not implemented remains explicitly unavailable and cannot satisfy a requirement.
- Comma-only AND expressions and pipe-only OR expressions.

Unknown keys, malformed terms and unavailable character values fail closed. Strings
containing both comma and pipe are explicitly rejected: the 768-template catalog
contains no such string, and the traced source notes do not establish precedence.
Do not infer conventional precedence until DS2's behavior is verified. The source
catalog has 60 distinct non-empty strings; all 768 template rows (including rows
with no requirement) are covered by the parser regression test. One template has
a dynamic item-level requirement but no source item-level variant, so a concrete
eligibility decision for that template still needs an actual item level.

Eleven current Curse base definitions have direct source-template requirement
strings. Other legacy Curse-authored bases retain their existing documented
class/item-level rule through this evaluator; this does not claim those bases are
one-for-one DS2 imports. Existing equipped gear is not revalidated or removed on
load, preserving save compatibility.
