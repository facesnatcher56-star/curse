#!/usr/bin/env python3
"""Reads Dungeon Siege II Tank archives (.ds2res) for design research.

Extracts plain-text GAS and Skrit rule files directly from Logic.ds2res:
    python tools/ds2_dump.py list
    python tools/ds2_dump.py extract OUTDIR [file1 file2 ...]
    python tools/ds2_dump.py extract-skills OUTDIR
"""
import os
import struct
import sys
import zlib

DEFAULT_GAME_RES = r"C:\Program Files (x86)\Steam\steamapps\common\Dungeon Siege 2\Resources\Logic.ds2res"

CORE_SKILL_FILES = [
    "passive_skills.gas",
    "active_skills.gas",
    "formulas.gas",
    "rules.gas",
    "rules.skrit",
    "skill_manager.skrit",
    "k_inc_skill_utils.skrit",
    "character_skills_tab.gas",
    "skills_melee_tab.gas",
    "skills_ranged_tab.gas",
    "skills_nature_tab.gas",
    "skills_combat_tab.gas",
    "skill_trainer_melee.gas",
    "skill_trainer_ranged.gas",
    "skill_trainer_nature.gas",
    "skill_trainer_combat.gas",
    "skill_trainer_store.gas",
    "skill_trainer_confirm.gas",
    "pcontent.gas",
    "pcontent_macros.gas",
    "actor_evil_melee.gas",
    "brain_monster.skrit",
    "brain_coach.skrit",
    "play_mob_attack.skrit",
    "templates.gas",
]


def open_tank(tank_path: str):
    f = open(tank_path, "rb")
    magic = f.read(8)
    if not (magic.startswith(b"DSigTank") or magic.startswith(b"DSg2Tank")):
        f.close()
        raise ValueError(f"Not a valid DS Tank file: {tank_path}")
    v1, v2 = struct.unpack("<HH", f.read(4))
    folders_off, files_off, dummy, base_off = struct.unpack("<IIII", f.read(16))
    f.seek(files_off)
    num_files = struct.unpack("<I", f.read(4))[0]
    offsets = [struct.unpack("<I", f.read(4))[0] + files_off for _ in range(num_files)]
    return f, offsets, base_off


def list_files(tank_path: str = DEFAULT_GAME_RES):
    f, offsets, base_off = open_tank(tank_path)
    entries = []
    for off in offsets:
        f.seek(off)
        folder_off, size = struct.unpack("<II", f.read(8))
        if size == 0:
            continue
        data_off, dummy, tstamp, chunked, namesz = struct.unpack("<IIQI H", f.read(22))
        namesz += 1
        name = f.read(namesz).decode("latin1").rstrip("\x00")
        entries.append((name, size))
    f.close()
    return entries


def extract_targets(out_dir: str, targets: list, tank_path: str = DEFAULT_GAME_RES):
    os.makedirs(out_dir, exist_ok=True)
    f, offsets, base_off = open_tank(tank_path)
    target_set = {t.lower(): t for t in targets}
    extracted = {}

    for off in offsets:
        f.seek(off)
        folder_off, size = struct.unpack("<II", f.read(8))
        if size == 0:
            continue
        data_off, dummy, tstamp, chunked, namesz = struct.unpack("<IIQI H", f.read(22))
        data_off += base_off
        namesz += 1
        name = f.read(namesz).decode("latin1").rstrip("\x00")
        name_lower = name.lower()

        if name_lower in target_set:
            rem = (f.tell() - off) % 4
            if rem != 0:
                f.seek(4 - rem, 1)

            if chunked == 0:
                f.seek(data_off)
                content = f.read(size)
            else:
                d1, total_chunk_sz = struct.unpack("<II", f.read(8))
                out = bytearray()
                while True:
                    c_sz, c_zsz, c_more, c_off = struct.unpack("<IIII", f.read(16))
                    pos_in_dir = f.tell()
                    f.seek(data_off + c_off)
                    if c_zsz == c_sz:
                        out.extend(f.read(c_sz))
                    else:
                        out.extend(zlib.decompress(f.read(c_zsz)))
                    if c_more > 0:
                        f.seek(data_off + c_off + c_zsz)
                        out.extend(f.read(c_more))
                    f.seek(pos_in_dir)
                    if len(out) >= size:
                        break
                content = bytes(out[:size])

            out_path = os.path.join(out_dir, name)
            with open(out_path, "wb") as out_fp:
                out_fp.write(content)
            extracted[name] = len(content)
            print(f"Extracted: {name} ({len(content):,} bytes) -> {out_path}")

    f.close()
    return extracted


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    cmd = args[0]
    if cmd == "list":
        files = list_files()
        print(f"Total files in archive: {len(files)}")
        for name, sz in files:
            print(f"  {name:40s} {sz:>10,} bytes")
    elif cmd == "extract-skills":
        out = args[1] if len(args) > 1 else "tools/ds2_reference"
        extract_targets(out, CORE_SKILL_FILES)
    elif cmd == "extract":
        if len(args) < 2:
            print("Usage: python tools/ds2_dump.py extract OUTDIR [file1 file2 ...]")
            sys.exit(1)
        out = args[1]
        targets = args[2:] if len(args) > 2 else CORE_SKILL_FILES
        extract_targets(out, targets)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
