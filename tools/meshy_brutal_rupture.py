"""One resumable Meshy geometry generation for Brutal Attack's crimson rupture.

The preview geometry is shaded in Godot; no paid texture/rig/animation pass.
Task ID and prompt are retained beside the asset, separate from tools/state.json.
"""
import json
from pathlib import Path
import art_direction
import meshy

DEST = Path(__file__).resolve().parent.parent / "assets/fx/brutal_crimson_rupture.glb"
MANIFEST = DEST.with_suffix(".json")
PROMPT = (
    "Jagged crescent shard, five swept obsidian serrations, tapered ends. "
    "Open silhouette. No hilt or pedestal. Crimson impact VFX geometry"
)

def main():
    DEST.parent.mkdir(parents=True, exist_ok=True)
    data = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    if "task_id" not in data:
        data = {"prompt": art_direction.styled_3d(PROMPT), "target_polycount": 1000}
        data["task_id"] = meshy.request("POST", "/v2/text-to-3d", {
            "mode": "preview", "prompt": data["prompt"], "ai_model": "latest",
            "should_remesh": True, "topology": "triangle", "target_polycount": 1000,
            "target_formats": ["glb"],
        })["result"]
        MANIFEST.write_text(json.dumps(data, indent=2))
    result = meshy.wait("/v2/text-to-3d/" + data["task_id"], "crimson rupture")
    data["consumed_credits"] = result.get("consumed_credits")
    MANIFEST.write_text(json.dumps(data, indent=2))
    meshy.download(result["model_urls"]["glb"], DEST)

if __name__ == "__main__":
    main()
