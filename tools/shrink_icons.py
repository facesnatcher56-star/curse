#!/usr/bin/env python3
"""Crop generated icons to their subject and shrink them to HUD size.

Meshy returns 1024 px images with a lot of empty margin. This trims to the visible subject, pads to a square
and saves a 192 px version in place. Originals move to ~/.meshy/cache/icons. Safe to re-run (skips small files).
"""
from pathlib import Path

from PIL import Image

ICONS = Path(__file__).resolve().parent.parent / "assets" / "icons"
CACHE = Path.home() / ".meshy" / "cache" / "icons"
SIZE = 192
MARGIN = 0.06


def main() -> None:
    CACHE.mkdir(parents=True, exist_ok=True)
    for path in sorted(ICONS.glob("*.png")):
        image = Image.open(path).convert("RGBA")
        if image.width <= 256:
            continue
        image.save(CACHE / path.name)
        bbox = image.getchannel("A").point(lambda a: 255 if a > 24 else 0).getbbox()
        if bbox:
            image = image.crop(bbox)
        side = int(max(image.size) * (1.0 + MARGIN * 2))
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
        square.resize((SIZE, SIZE), Image.LANCZOS).save(path)
        print(f"{path.name}: {SIZE}px")


if __name__ == "__main__":
    main()
