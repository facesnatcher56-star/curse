#!/usr/bin/env python3
"""Reads Zombasite's data files (for design research; see docs/zombasite-world-and-npcs.md).

The game's pack files are plain zip files (assets001..004.zip). Later packs override earlier ones. Inside, `Database/*.gdb`
are text definitions (`Name { Base X  Key Value ... }`) and `Loc/English/*.trn` are the display strings the definitions refer
to as `$$Tag$$`. Nothing from the game is stored in this repository: point GAME at your own install and extract to a scratch
folder.

    python tools/zombasite_dump.py extract OUTDIR       # unpack Database, Loc, Names, Programs, Text from all packs
    python tools/zombasite_dump.py show OUTDIR FILE NAME   # print one definition with its strings resolved
"""
import os
import re
import sys
import zipfile

GAME = r"C:\Program Files (x86)\Steam\steamapps\common\Zombasite\Assets"
PACKS = ["assets001.zip", "assets002.zip", "assets003.zip", "assets004.zip"]
KEEP = ("Database/", "Loc/", "Names/", "Programs/", "Text/", "Levels/")


def extract(out: str) -> None:
    for pack in PACKS:
        z = zipfile.ZipFile(os.path.join(GAME, pack))
        for name in z.namelist():
            if name.startswith(KEEP) and not name.endswith("/"):
                z.extract(name, os.path.join(out, pack[:-4]))


def layers(out: str) -> list:
    """Pack folders, earliest first (later ones override)."""
    return [os.path.join(out, p[:-4]) for p in PACKS if os.path.isdir(os.path.join(out, p[:-4]))]


def read(out: str, rel: str) -> str:
    """The latest version of a file across the packs."""
    for folder in reversed(layers(out)):
        path = os.path.join(folder, rel)
        if os.path.exists(path):
            return open(path, encoding="latin-1").read()
    return ""


def strings(out: str) -> dict:
    """Every `Key "text"` line of every .trn file (latest wins)."""
    table = {}
    for folder in layers(out):
        loc = os.path.join(folder, "Loc", "English")
        if not os.path.isdir(loc):
            continue
        for fn in os.listdir(loc):
            if fn.endswith(".trn"):
                text = open(os.path.join(loc, fn), encoding="latin-1").read()
                for m in re.finditer(r'^([A-Za-z0-9_]+)\s+"(.*?)"\s*$', text, re.M | re.S):
                    table[m.group(1)] = m.group(2)
    return table


def parse_gdb(text: str) -> dict:
    """name -> {"Base": str, "fields": [(key, value)]} in file order."""
    defs = {}
    name = None
    body = None
    for raw in text.splitlines():
        line = raw.split("//")[0].rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped == "{":
            body = []
            continue
        if stripped == "}":
            if name is not None and body is not None:
                base = ""
                fields = []
                for key, value in body:
                    if key == "Base":
                        base = value
                    else:
                        fields.append((key, value))
                defs[name] = {"Base": base, "fields": fields}
            name, body = None, None
            continue
        if body is None:
            name = stripped
        else:
            parts = stripped.split(None, 1)
            body.append((parts[0], parts[1].strip() if len(parts) > 1 else ""))
    return defs


def load_db(out: str, rel: str) -> dict:
    return parse_gdb(read(out, rel))


def resolve(value: str, table: dict) -> str:
    return re.sub(r"\$\$(\w+)\$\$", lambda m: '"%s"' % table.get(m.group(1), m.group(1)), value)


def expand(value: str, table: dict, depth: int = 0) -> str:
    r"""Resolves `$$Tag$$` references recursively (descriptions nest other descriptions), drops colour codes and turns the
    two-character `\n` into a space."""
    value = value.strip().strip('"').replace("\\n", " ")
    value = re.sub(r"\^c\d{3}", "", value)
    if depth > 4:
        return value
    return re.sub(r"\$\$(\w+)\$\$", lambda m: expand(table[m.group(1)], table, depth + 1) if m.group(1) in table else m.group(1), value)


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "extract":
        extract(sys.argv[2])
    elif len(sys.argv) >= 5 and sys.argv[1] == "show":
        out, rel, name = sys.argv[2], sys.argv[3], sys.argv[4]
        table = strings(out)
        db = load_db(out, rel)
        entry = db.get(name)
        if entry is None:
            print("not found; some names:", list(db)[:20])
            return
        print(name, "(base %s)" % entry["Base"])
        for key, value in entry["fields"]:
            print("  %-28s %s" % (key, resolve(value, table)))
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
