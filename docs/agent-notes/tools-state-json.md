# Note for agents: tools/state.json

`tools/state.json` is the local record of Meshy task IDs (rig, animation, preview and refine
tasks for each asset). `tools/meshy.py` reads it so a re-run skips steps that are already
paid for. Do not delete or rewrite it without checking first: deleting it means paying for
the same Meshy work again.

Current state (2026-10-16): the only difference from the committed file is line endings
(CRLF on this PC, LF in the repo). The content is identical, so nothing is lost either way.
