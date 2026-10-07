#!/usr/bin/env python3
"""Writes res://data/zones/*.tres (ZoneDef): what each stretch of the Crypt Road is stocked with where the hand-placed encounters leave
a gap. Edit the tables and re-run. The structure is Zombasite's area description (docs/zombasite-world-and-npcs.md, section 6)."""
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "data" / "zones"

Z, G, S, B, P, R = "zombie", "ghoul", "spitter", "bloater", "priest", "brute"

ZONES = {
    "road_in": dict(display_name="The Road In", from_m=0, to_m=64, base_threat=1.25, density=1.0, groups=[
        {"weight": 70, "members": [Z, Z]}, {"weight": 30, "members": [Z, Z, Z]}]),
    "graveyard": dict(display_name="The Graveyard Stretch", from_m=64, to_m=134, base_threat=1.3, density=1.0, groups=[
        {"weight": 50, "members": [Z, Z, G]}, {"weight": 20, "members": [Z, Z, S]}, {"weight": 30, "members": [Z, G]}]),
    "wood": dict(display_name="The Wood", from_m=134, to_m=214, base_threat=1.4, density=1.0, groups=[
        {"weight": 45, "members": [Z, G, G]}, {"weight": 20, "members": [B, Z]}, {"weight": 35, "members": [Z, Z, G]}]),
    "crypt_approach": dict(display_name="The Crypt Approach", from_m=214, to_m=400, base_threat=1.5, density=1.0, groups=[
        {"weight": 40, "members": [Z, G, S]}, {"weight": 15, "members": [R, Z]}, {"weight": 10, "members": [P, Z, Z]},
        {"weight": 35, "members": [Z, G, G]}]),
}


def fmt(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"%s"' % v
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, (list, tuple)):
        return "[%s]" % ", ".join(fmt(x) for x in v)
    if isinstance(v, dict):
        return "{\n%s\n}" % ",\n".join("%s: %s" % (fmt(k), fmt(x)) for k, x in v.items())
    raise TypeError(v)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    keep = {"%s.tres" % z for z in ZONES}
    for old in OUT.glob("*.tres"):
        if old.name not in keep:
            old.unlink()
    for zid, z in ZONES.items():
        lines = ['[gd_resource type="Resource" script_class="ZoneDef" load_steps=2 format=3]', "",
                 '[ext_resource type="Script" path="res://game/data/zone_def.gd" id="1"]', "", "[resource]",
                 'script = ExtResource("1")', 'id = "%s"' % zid, "display_name = %s" % fmt(z["display_name"]),
                 "from_m = %s" % repr(float(z["from_m"])), "to_m = %s" % repr(float(z["to_m"])),
                 "base_threat = %s" % repr(float(z["base_threat"])), "density = %s" % repr(float(z["density"])),
                 "groups = %s" % fmt(z["groups"])]
        (OUT / ("%s.tres" % zid)).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("wrote", len(ZONES), "zones")


if __name__ == "__main__":
    main()
