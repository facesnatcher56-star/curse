"""Turns the Blender renders (assets/ui/busts/raw_*.png) into the HUD busts: a single bronze-stone tone (so the two lights read as form, not as
two colours), a faint grain, a dark halo, and a fade into the dark at the bottom. Run after make_busts.py:  python tools/blender/finish_busts.py"""
import os
import numpy as np
from PIL import Image, ImageFilter

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "ui", "busts")
# (shadow, mid, light, glint) per bust: the knight is warm gilt bronze, the hooded figure verdigris-green copper, so the pair is not one tone.
PALETTES = {
    "knight": ([0.035, 0.022, 0.016], [0.34, 0.20, 0.08], [0.66, 0.46, 0.20], [0.95, 0.87, 0.70]),
    "priest": ([0.016, 0.034, 0.034], [0.10, 0.25, 0.23], [0.34, 0.54, 0.46], [0.82, 0.93, 0.87]),
}
rng = np.random.default_rng(11)
for name in ("knight", "priest"):
    SHADOW, MID, LIGHT, SILVER = (np.array(c) for c in PALETTES[name])
    im = Image.open(os.path.join(DIR, "raw_%s.png" % name)).convert("RGBA")
    a = np.array(im.split()[3], dtype=float) / 255
    g = np.array(im.convert("L"), dtype=float) / 255
    m = a > 0.5
    lo, hi = np.percentile(g[m], [2, 99])
    g = np.clip((g - lo) / (hi - lo), 0, 1) ** 1.45
    grain = np.array(Image.fromarray((rng.normal(0, 1, g.shape) * 38 + 128).clip(0, 255).astype("uint8")).filter(ImageFilter.GaussianBlur(0.9)), dtype=float) / 255 - 0.5
    g = np.clip(g + grain * 0.14, 0, 1)
    t = g[..., None]
    rgb = np.where(t < 0.5, SHADOW + (MID - SHADOW) * (t / 0.5), MID + (LIGHT - MID) * ((t - 0.5) / 0.5))
    glint = np.clip((t - 0.80) / 0.20, 0, 1) ** 1.5
    rgb = rgb * (1 - glint) + SILVER * glint
    h, w = g.shape
    y = np.linspace(0, 1, h)[:, None]
    fade = np.clip((1 - y) / 0.30, 0, 1) ** 1.2
    ai = Image.fromarray((a * 255).astype("uint8"))
    halo = np.array(ai.filter(ImageFilter.GaussianBlur(16)), dtype=float) / 255 * 0.7 * fade
    af = a * fade
    col = np.where(af[..., None] > 0.02, rgb, np.array([0.02, 0.02, 0.025]))
    out = np.dstack([col, np.clip(np.maximum(af, halo), 0, 1)])
    Image.fromarray((out * 255).astype("uint8"), "RGBA").save(os.path.join(DIR, "%s.png" % name))
    print("BUST", name)
