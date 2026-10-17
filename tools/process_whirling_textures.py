"""Builds the contrast-graded textures Whirling Strike's ground effect uses, from the Meshy art in assets/fx/whirling/ (no paid call):

  ground_sigil_albedo.png    the sigil with its metal pushed darker, the centre darkest and the trailing side of each blade shaded
  ground_sigil_emission.png  what glows: hot-steel cutting edges on the leading side of every blade, and only the engraved runes, in crimson
  ground_sigil_molten.png    the same runes in molten orange, faded in over the crimson as the rage builds
  crescent_wind_hollow.png   the dust vortex with its middle faded out, so the hero and the weapon stay readable

    python tools/process_whirling_textures.py [--flip]

The blades turn toward +yaw (counter-clockwise from above). In the texture that is TURN = +1; pass --flip if the leading edge lights on the
wrong side after a change to how the decal is turned.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

DIR = Path(__file__).resolve().parent.parent / "assets/fx/whirling"
FLIP = "--flip" in sys.argv


def blur(arr: np.ndarray, radius: float) -> np.ndarray:
    return np.asarray(Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius)), dtype=np.float32) / 255.0


def sigil() -> None:
    img = np.asarray(Image.open(DIR / "ground_sigil.png").convert("RGBA"), dtype=np.float32) / 255.0
    h, w = img.shape[:2]
    rgb, alpha = img[..., :3], img[..., 3]
    mask = blur((alpha > 0.5).astype(np.float32), 2.0)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    dx, dy = xx - cx, yy - cy
    radius = np.sqrt(dx * dx + dy * dy) / (w / 2)
    # Which way is "leading": the direction the blades travel. Image y points down, so +yaw (ccw from above) is (dy, -dx) up to the flip.
    turn = -1.0 if FLIP else 1.0
    tx, ty = turn * dy / (radius * w / 2 + 1e-3), -turn * dx / (radius * w / 2 + 1e-3)
    gy, gx = np.gradient(blur(mask, 1.5))   # points into the blade
    inward = gx * tx + gy * ty              # > 0: moving along the turn goes into the blade (a leading edge faces the turn)
    rim = np.clip(np.hypot(gx, gy) * 14.0, 0, 1)
    lead = np.clip(-inward * 18.0, 0, 1) * rim * (alpha > 0.05)
    trail = np.clip(inward * 18.0, 0, 1) * rim * (alpha > 0.05)
    lead = np.maximum(lead, blur(lead, 1.2))
    # The outer ring is the frame, not a cutting edge: keep its rims dim so no bright circle reads as a range indicator.
    lead *= 1.0 - 0.8 * np.clip((radius - 0.84) / 0.06, 0.0, 1.0)
    trail *= 1.0 - 0.8 * np.clip((radius - 0.84) / 0.06, 0.0, 1.0)

    # Selective glow: the ember-orange runes only.
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    runes = np.clip((r - 1.35 * g) * 5.0, 0, 1) * np.clip((r - 1.8 * b) * 4.0, 0, 1) * (r > 0.38)
    runes = np.maximum(runes, blur(runes, 1.0) * 0.8)
    # Warrior palette (game/skills/warrior_palette.gd): blackened iron, blood crimson, ember orange, hot steel. Two emission maps: the runes
    # in dull crimson with the hot-steel leading edges, and the same runes in molten orange. The effect fades the molten one in as the
    # rage builds, so the engravings go from crimson to molten.
    hot_steel = np.array([1.0, 0.86, 0.66], np.float32)
    crimson = np.array([0.78, 0.06, 0.05], np.float32)
    molten = np.array([1.0, 0.5, 0.1], np.float32)
    edges = lead[..., None] * hot_steel + trail[..., None] * np.array([0.5, 0.2, 0.15], np.float32) * 0.3
    quiet = 0.78 + 0.22 * np.clip((radius - 0.3) / 0.5, 0.0, 1.0)   # the innermost layers sit ~20% quieter so the hero and weapon stay readable
    for name, rune_colour, with_edges in (("ground_sigil_emission.png", crimson, True), ("ground_sigil_molten.png", molten, False)):
        emission = runes[..., None] * rune_colour
        if with_edges:
            emission = emission + edges
        emission = emission * quiet[..., None]
        Image.fromarray((np.clip(emission, 0, 1) * 255).astype(np.uint8)).save(DIR / name)

    # Albedo: harder contrast, a dark core so the hero reads, the trailing side of every blade in shadow.
    graded = np.power(rgb, 1.1) * 1.0
    shade = 1.0 - 0.3 * blur(trail, 6.0) * 3.0
    core = np.clip(radius / 0.34, 0.0, 1.0)
    graded *= np.clip(shade, 0.6, 1.0)[..., None] * (0.55 + 0.45 * core)[..., None] * quiet[..., None]
    out = np.dstack([np.clip(graded, 0, 1), alpha])
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(DIR / "ground_sigil_albedo.png")


def vortex() -> None:
    img = np.asarray(Image.open(DIR / "crescent_wind.png").convert("RGBA"), dtype=np.float32) / 255.0
    h, w = img.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # The swirl's own centre and size (its ellipse fills about 0.78 x 0.73 of the image).
    nx = (xx / w - 0.5) / 0.39
    ny = (yy / h - 0.5) / 0.365
    r = np.sqrt(nx * nx + ny * ny)
    hole = np.clip((r - 0.28) / 0.35, 0.0, 1.0)
    rim = 1.0 - np.clip((r - 0.7) / 0.3, 0.0, 1.0)   # no pale perimeter: the swirl dies away before its edge
    img[..., 3] *= hole * rim
    img[..., :3] *= (0.8 + 0.2 * hole)[..., None]
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(DIR / "crescent_wind_hollow.png")


if __name__ == "__main__":
    sigil()
    vortex()
    print("wrote", [p.name for p in sorted(DIR.glob("*_*.png"))])
