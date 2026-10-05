#!/usr/bin/env python3
"""Fails CI when the headless self-test did not finish cleanly.

Looks at the captured Godot log for: a missing "SELFTEST done" line, engine/script errors, and explicit failures
reported by the test code ("[FAIL]" lines or "SELFTEST FAILED").
"""
import re
import sys

BAD = re.compile(r"^(SCRIPT ERROR|ERROR:|USER ERROR|.*Parse Error|.*\[FAIL\]|SELFTEST FAILED)", re.M)


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "selftest.log"
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        print(f"cannot read {path}: {exc}")
        return 1
    problems = [m.group(0) for m in BAD.finditer(text)]
    if "SELFTEST done" not in text:
        problems.append("the self-test never printed 'SELFTEST done' (crash, hang or timeout)")
    if problems:
        print("Self-test FAILED:")
        for line in problems[:40]:
            print("  -", line.strip())
            # A workflow annotation, so the failure is readable on the run page without signing in to see the log.
            print("::error title=Self-test::" + " ".join(line.strip().replace("%", "%25").split()))
        return 1
    print("Self-test passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
