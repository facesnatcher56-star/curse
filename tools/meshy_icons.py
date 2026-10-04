#!/usr/bin/env python3
"""Generate the hotbar ability icons with Meshy text-to-image (transparent PNGs in assets/icons/).

Usage: python tools/meshy_icons.py [name ...]     (re-running skips icons that already exist)
"""
import sys
from pathlib import Path

import meshy  # same folder; reuses key handling, retry-on-429 and downloads

OUT = meshy.ROOT / "assets" / "icons"
STYLE = ("Fantasy RPG ability icon, bold stylized painterly game icon, single centered subject, "
         "strong readable silhouette, rich saturated colors, dramatic lighting, no text, no border, no frame. ")

ICONS = {
    "basic": "a steel longsword caught mid-slash with a bright white curved slash arc",
    "power": "a heavy overhead sword strike smashing downward with a burst of glowing orange impact shards",
    "cleave": "a spinning sword sweep, a wide crescent arc of steel-blue light circling around a blade",
    "fireball": "a blazing fireball with trailing orange flames and flying sparks",
    "potion": "a round glass health potion flask filled with glowing red liquid, sealed with a cork",
    "dodge": "an armored knight tumbling in a dodge roll with motion streaks and kicked-up dust",
    "leap": "an armored knight leaping through the air high above the ground, gripping a longsword with both hands pointed straight down, about to stab a fallen enemy, dust ring and motion streaks",
    "skewer": "an armored knight charging forward with a long sword thrust through three enemies lined up on the blade, motion streaks and sparks",
    "earthshatter": "an armored knight on one knee driving a longsword deep into cracked ground, a huge glowing orange shockwave and fissures bursting outward, rocks and enemies flung into the air",
}


def main() -> None:
    names = sys.argv[1:] or list(ICONS)
    for name in names:
        dest = OUT / f"{name}.png"
        if dest.exists():
            print(f"== {name}: already exists")
            continue
        print(f"== {name}")
        task_id = meshy.request("POST", "/v1/text-to-image", {
            "ai_model": "nano-banana-2",
            "prompt": STYLE + ICONS[name],
            "aspect_ratio": "1:1",
            "remove_background": True,
        })["result"]
        task = meshy.wait(f"/v1/text-to-image/{task_id}", "icon")
        meshy.download(task["image_urls"][0], dest)
    print("balance:", meshy.request("GET", "/v1/balance"))


if __name__ == "__main__":
    main()
