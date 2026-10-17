"""Two Meshy text-to-image textures for Whirling Strike's effect (transparent PNGs in assets/fx/whirling/): the ground sigil that opens
at the power's radius, and the crescent blade-wind that sweeps round the hero. Task ids and prompts are kept in manifest.json.
    python tools/meshy_whirling_fx.py
"""
import json
from pathlib import Path
import art_direction
import meshy

OUT = Path(__file__).resolve().parent.parent / "assets/fx/whirling"
ASSETS = {
    "ground_sigil": (
        "Top-down circular war sigil seen from directly above, filling the whole square image edge to edge: a heavy outer ring of worn "
        "dark steel with eight swept curved blade-shaped spokes spiralling in one direction, engraved rune notches, a smaller inner ring, "
        "glowing molten ember-orange inlay in the grooves, scratched and soot-stained metal, strong contrast, symmetrical, "
        "transparent background, no character, no floor, no text"),
    "crescent_wind": (
        "A single sweeping crescent slash of cutting wind and dust, long tapered horizontal arc like a blade-shaped gust, pale ash-white "
        "and steel-grey core fading to transparent smoky streaks, a few ember sparks along the edge, side view, wide image, "
        "transparent background, no character, no hand, no weapon, no text"),
}
ASPECT = {"ground_sigil": "1:1", "crescent_wind": "16:9"}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    for name, prompt in ASSETS.items():
        dest = OUT / f"{name}.png"
        if dest.exists():
            print("==", name, "already exists")
            continue
        styled = art_direction.styled_2d(prompt)
        task_id = meshy.request("POST", "/v1/text-to-image", {
            "ai_model": "nano-banana-2", "prompt": styled, "aspect_ratio": ASPECT[name], "remove_background": True})["result"]
        task = meshy.wait(f"/v1/text-to-image/{task_id}", name)
        meshy.download(task["image_urls"][0], dest)
        manifest[name] = {"task_id": task_id, "prompt": styled, "aspect_ratio": ASPECT[name]}
        manifest_path.write_text(json.dumps(manifest, indent=2))
    print("balance:", meshy.request("GET", "/v1/balance"))


if __name__ == "__main__":
    main()
