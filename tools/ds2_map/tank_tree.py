"""Reads a DS2 Tank archive with its folder structure and extracts files with their full paths.
usage: tank_tree.py TANK OUTDIR [substring-filter ...]   (no filter: only lists the paths into OUTDIR/_index.txt)
"""
import os
import struct
import sys
import zlib


def read_tank(path):
    f = open(path, "rb")
    f.read(12)
    folders_off, files_off, _dummy, base_off = struct.unpack("<IIII", f.read(16))
    f.seek(folders_off)
    n = struct.unpack("<I", f.read(4))[0]
    offs = [struct.unpack("<I", f.read(4))[0] for _ in range(n)]
    folders = {}
    for o in offs:
        f.seek(folders_off + o)
        parent, count = struct.unpack("<II", f.read(8))
        f.read(8)
        (ln,) = struct.unpack("<H", f.read(2))
        name = f.read(ln + 1).decode("latin1").rstrip("\x00")
        folders[o] = (parent, name)

    def folder_path(o):
        parts = []
        seen = 0
        while o in folders and seen < 64:
            parent, name = folders[o]
            parts.append(name)
            if parent == o or parent not in folders:
                break
            o = parent
            seen += 1
        return "/".join(reversed(parts))

    f.seek(files_off)
    nf = struct.unpack("<I", f.read(4))[0]
    foffs = [struct.unpack("<I", f.read(4))[0] + files_off for _ in range(nf)]
    files = []
    for off in foffs:
        f.seek(off)
        folder_off, size = struct.unpack("<II", f.read(8))
        if size == 0:
            continue
        data_off, _d, _t, chunked, namesz = struct.unpack("<IIQI H", f.read(22))
        name = f.read(namesz + 1).decode("latin1").rstrip("\x00")
        rem = (f.tell() - off) % 4
        if rem:
            f.seek(4 - rem, 1)
        files.append({"path": folder_path(folder_off) + "/" + name, "size": size, "data": data_off + base_off, "chunked": chunked, "table": f.tell()})
    return f, files


def read_data(f, entry):
    size = entry["size"]
    if not entry["chunked"]:
        f.seek(entry["data"])
        return f.read(size)
    f.seek(entry["table"])
    f.read(8)
    out = bytearray()
    while True:
        c_sz, c_zsz, c_more, c_off = struct.unpack("<IIII", f.read(16))
        here = f.tell()
        f.seek(entry["data"] + c_off)
        if c_zsz == c_sz:
            out.extend(f.read(c_sz))
        else:
            out.extend(zlib.decompress(f.read(c_zsz)))
        if c_more > 0:
            f.seek(entry["data"] + c_off + c_zsz)
            out.extend(f.read(c_more))
        f.seek(here)
        if len(out) >= size:
            break
    return bytes(out[:size])


if __name__ == "__main__":
    tank, out = sys.argv[1], sys.argv[2]
    filters = [s.lower() for s in sys.argv[3:]]
    f, files = read_tank(tank)
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "_index.txt"), "w", encoding="utf-8") as idx:
        for e in files:
            idx.write("%9d  %s\n" % (e["size"], e["path"]))
    wrote = 0
    for e in files:
        if filters and any(s in e["path"].lower() for s in filters):
            dest = os.path.join(out, e["path"].lstrip("/"))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as w:
                w.write(read_data(f, e))
            wrote += 1
    print("files", len(files), "extracted", wrote)
