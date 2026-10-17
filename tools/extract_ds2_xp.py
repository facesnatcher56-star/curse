#!/usr/bin/env python3
"""Extract the exact 100-level numeric baseline from an installed DS2 formulas.gas.
Usage: python tools/extract_ds2_xp.py PATH_TO_FORMULAS_GAS
Only the numeric gameplay table is stored, not the original game script.
"""
import json
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8-sig")
block = re.search(r"\[experience_table\]\s*\{\s*\*\s*=\s*\[\[(.*?)\]\]", source, re.S)
if block is None:
    raise SystemExit("Missing experience_table")
values = [int(value) for value in re.findall(r"\d+", block[1])][:100]
assert len(values) == 100 and values[:3] == [0, 300, 900]
assert all(a < b for a, b in zip(values, values[1:]))
out = Path(__file__).resolve().parents[1] / "data/reference/ds2_xp.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(values, indent=2) + "\n", encoding="utf-8", newline="\n")
print("wrote", out, "100 exact XP thresholds")
