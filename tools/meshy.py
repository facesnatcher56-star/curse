#!/usr/bin/env python3
"""Generate game models with the Meshy API (text-to-3D -> texture -> rig -> animations).

Usage:  python tools/meshy.py build <asset> [<asset> ...]     (assets defined in tools/assets.json)
        python tools/meshy.py balance

The API key is read from the MESHY_API_KEY env var or ~/.meshy/key. It is never stored in the project.
Task ids are saved in tools/state.json, so re-running skips finished (already paid-for) steps.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE_FILE = ROOT / "tools" / "state.json"
ASSET_FILE = ROOT / "tools" / "assets.json"
OUT_DIR = ROOT / "assets" / "models"
# Heavy intermediates (unrigged model, per-clip GLBs that each embed the full mesh) stay out of the project.
CACHE_DIR = Path.home() / ".meshy" / "cache"
API = "https://api.meshy.ai/openapi"


def api_key() -> str:
    key = os.environ.get("MESHY_API_KEY")
    if not key:
        key = (Path.home() / ".meshy" / "key").read_text().strip()
    return key


def request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", f"Bearer {api_key()}")
    req.add_header("User-Agent", "curse-asset-pipeline/1.0")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    # The free/low tiers cap how many tasks may be queued; on 429 wait for earlier ones to drain and retry.
    for attempt in range(60):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as err:
            if err.code == 429 and method == "POST":
                print(f"    queue full, waiting ({attempt + 1})")
                time.sleep(20)
                continue
            raise SystemExit(f"HTTP {err.code} on {method} {path}: {err.read().decode()[:500]}")
    raise SystemExit(f"gave up waiting for queue space on {path}")


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and dest.stat().st_size > 0:
        return
    req = urllib.request.Request(url, headers={"User-Agent": "curse-asset-pipeline/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as out:
        out.write(resp.read())
    print(f"    saved {dest} ({dest.stat().st_size // 1024} KB)")


def load_state() -> dict:
    return json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}


OWNED: set[str] = set()


def save_state(state: dict) -> None:
    """Merge only the assets this process builds, so parallel runs do not overwrite each other."""
    disk = load_state()
    for name in OWNED:
        if name in state:
            disk[name] = state[name]
    STATE_FILE.write_text(json.dumps(disk, indent=2))


def wait(path: str, label: str) -> dict:
    while True:
        task = request("GET", path)
        status = task.get("status")
        if status == "SUCCEEDED":
            print(f"    {label}: done (credits {task.get('consumed_credits', '?')})")
            return task
        if status in ("FAILED", "CANCELED"):
            raise SystemExit(f"{label} {status}: {task.get('task_error')}")
        print(f"    {label}: {status} {task.get('progress', 0)}%")
        time.sleep(12)


def build(name: str, spec: dict, state: dict) -> None:
    print(f"== {name}")
    OWNED.add(name)
    entry = state.setdefault(name, {})
    out = OUT_DIR / name
    cache = CACHE_DIR / name

    if "preview" not in entry:
        body = {
            "mode": "preview",
            "prompt": spec["prompt"],
            "ai_model": spec.get("ai_model", "latest"),
            "should_remesh": True,
            "topology": "triangle",
            "target_polycount": spec.get("polycount", 15000),
            "target_formats": ["glb"],
        }
        if spec.get("pose"):
            body["pose_mode"] = spec["pose"]
        entry["preview"] = request("POST", "/v2/text-to-3d", body)["result"]
        save_state(state)
    wait(f"/v2/text-to-3d/{entry['preview']}", "preview")

    if "refine" not in entry:
        body = {
            "mode": "refine",
            "preview_task_id": entry["preview"],
            "enable_pbr": True,
            "texture_resolution": spec.get("texture_resolution", "2k"),
            "target_formats": ["glb"],
        }
        if spec.get("texture_prompt"):
            body["texture_prompt"] = spec["texture_prompt"]
        entry["refine"] = request("POST", "/v2/text-to-3d", body)["result"]
        save_state(state)
    refined = wait(f"/v2/text-to-3d/{entry['refine']}", "texture")
    # Props use the textured model directly; rigged characters only need the rigged file in the project.
    download(refined["model_urls"]["glb"], (out if not spec.get("rig") else cache) / "model.glb")

    if not spec.get("rig"):
        return

    if "rig" not in entry:
        entry["rig"] = request("POST", "/v1/rigging", {
            "input_task_id": entry["refine"],
            "height_meters": spec.get("height", 1.8),
        })["result"]
        save_state(state)
    rigged = wait(f"/v1/rigging/{entry['rig']}", "rig")
    result = rigged["result"]
    download(result["rigged_character_glb_url"], out / "rigged.glb")
    basic = result.get("basic_animations", {})
    if basic.get("walking_glb_url"):
        download(basic["walking_glb_url"], cache / "anim_walk.glb")
    if basic.get("running_glb_url"):
        download(basic["running_glb_url"], cache / "anim_run.glb")

    anims = entry.setdefault("anims", {})
    for key, action_id in spec.get("animations", {}).items():
        if key not in anims:
            anims[key] = request("POST", "/v1/animations", {
                "rig_task_id": entry["rig"],
                "action_id": action_id,
            })["result"]
            save_state(state)
    for key, task_id in anims.items():
        done = wait(f"/v1/animations/{task_id}", f"anim {key}")
        download(done["result"]["animation_glb_url"], cache / f"anim_{key}.glb")
    print(f"    next: godot --headless --script tools/bake_anims.gd -- res://assets/models/{name} {cache.as_posix()}")


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == "balance":
        print(request("GET", "/v1/balance"))
        return
    if sys.argv[1] != "build":
        raise SystemExit(__doc__)
    assets = json.loads(ASSET_FILE.read_text(encoding="utf-8-sig"))
    state = load_state()
    names = sys.argv[2:] or list(assets)
    for name in names:
        build(name, assets[name], state)
        save_state(state)
    print("balance:", request("GET", "/v1/balance"))


if __name__ == "__main__":
    main()
