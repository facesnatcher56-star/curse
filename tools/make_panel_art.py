"""Derives the stretch-safe panel plate (#49) from the owner-approved assets/ui/ornate/metal.png.

Why: the metal nine-slice used TILE_FIT, so its midpoint studs and edge knotwork repeated along every long bar and window.
The derived plate keeps the four ornate corners exactly as drawn, removes the midpoint stud from each rail by copying a
stud-free stretch of the same rail, and replaces the edge bands and the centre with a seamless low-feature leather fill
(texture-bombed from the quiet centre with random flips and soft blends, plus a large-scale grime variation). The theme
stretches this plate instead of tiling it, so no ornament repeats.

Usage: python tools/make_panel_art.py   (writes assets/ui/ornate/metal_panel.png; metal.png itself is untouched)
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCE = os.path.join(ROOT, "assets", "ui", "ornate", "metal.png")
TARGET = os.path.join(ROOT, "assets", "ui", "ornate", "metal_panel.png")

SIZE = 1024
CORNER = 96           # corner cell in source px (24 logical px at 4 px per logical px): the ornament must fit it, or it stretches along the edge
RAIL = 62             # rows/columns of the gold rail and groove kept from the source edge
RAIL_COPY = (300, 386)  # stud-free stretch of the same rail, copied over the stud
QUIET = (340, 684)    # the centre of the source plate: quiet leather with faint cracks


def feather(size: int) -> np.ndarray:
    ramp = np.minimum(np.arange(size), size - 1 - np.arange(size)) / (0.35 * size)
    ramp = np.clip(ramp, 0.0, 1.0)
    return np.outer(ramp, ramp)[..., None].astype(np.float32)


def bombed_fill(quiet: np.ndarray, size: int, rng: np.random.Generator) -> np.ndarray:
    """Texture bombing: overlapping patches from the quiet source, randomly flipped, softly blended."""
    out = np.zeros((size, size, 3), np.float32)
    weight = np.zeros((size, size, 1), np.float32)
    step = 72
    for gy in range(-1, size // step + 2):
        for gx in range(-1, size // step + 2):
            cs = int(rng.integers(112, 176))
            x0 = gx * step + int(rng.integers(-20, 21))
            y0 = gy * step + int(rng.integers(-20, 21))
            ox = int(rng.integers(0, quiet.shape[1] - cs))
            oy = int(rng.integers(0, quiet.shape[0] - cs))
            patch = quiet[oy:oy + cs, ox:ox + cs]
            if rng.random() < 0.5:
                patch = patch[:, ::-1]
            if rng.random() < 0.5:
                patch = patch[::-1]
            if rng.random() < 0.5:
                patch = np.transpose(patch, (1, 0, 2))
            mask = feather(cs)
            sx0, sy0 = max(0, x0), max(0, y0)
            sx1, sy1 = min(size, x0 + cs), min(size, y0 + cs)
            if sx1 <= sx0 or sy1 <= sy0:
                continue
            px0, py0 = sx0 - x0, sy0 - y0
            px1, py1 = px0 + (sx1 - sx0), py0 + (sy1 - sy0)
            out[sy0:sy1, sx0:sx1] += patch[py0:py1, px0:px1] * mask[py0:py1, px0:px1]
            weight[sy0:sy1, sx0:sx1] += mask[py0:py1, px0:px1]
    out /= np.maximum(weight, 1e-4)
    # Large-scale grime: a low-frequency field so no two stretches look alike.
    coarse = rng.random((size // 96 + 2, size // 96 + 2)).astype(np.float32)
    field = np.asarray(Image.fromarray(coarse).resize((size, size), Image.BICUBIC), np.float32)
    field = (field - field.mean()) / max(field.std(), 1e-4)
    out *= (1.0 + 0.07 * field)[..., None]
    return np.clip(out, 0, 255)


def main() -> None:
    source = np.asarray(Image.open(SOURCE).convert("RGB"), np.float32)
    assert source.shape == (SIZE, SIZE, 3), source.shape
    rng = np.random.default_rng(49)
    quiet = source[QUIET[0]:QUIET[1], QUIET[0]:QUIET[1]]
    plate = bombed_fill(quiet, SIZE, rng)
    keep = source.copy()

    # The bombed leather fills the centre and the knotwork bands. Each rail becomes a uniform profile taken from a stud-free
    # stretch of the same rail (the studs and the corner scrolls that spill past the corner cell would otherwise smear when
    # stretched). The corner squares keep the original ornament exactly.
    result = plate.copy()
    c, d = RAIL_COPY
    top = keep[0:RAIL, c:d].mean(axis=1)                 # (RAIL, 3): rows of the top rail
    bottom = keep[SIZE - RAIL:SIZE, c:d].mean(axis=1)    # bottom rail
    left = keep[c:d, 0:RAIL].mean(axis=0)                # (RAIL, 3): columns of the left rail
    right = keep[c:d, SIZE - RAIL:SIZE].mean(axis=0)     # right rail
    span = slice(CORNER, SIZE - CORNER)
    result[0:RAIL, span] = top[:, None, :]
    result[SIZE - RAIL:SIZE, span] = bottom[:, None, :]
    result[span, 0:RAIL] = left[None, :, :]
    result[span, SIZE - RAIL:SIZE] = right[None, :, :]
    for ys in [slice(0, CORNER), slice(SIZE - CORNER, SIZE)]:
        for xs in [slice(0, CORNER), slice(SIZE - CORNER, SIZE)]:
            result[ys, xs] = keep[ys, xs]

    image = Image.fromarray(np.clip(result, 0, 255).astype(np.uint8), "RGB")
    image.save(TARGET, optimize=True)
    print("wrote", os.path.normpath(TARGET), image.size)


if __name__ == "__main__":
    main()
