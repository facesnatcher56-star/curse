#!/usr/bin/env python3
"""Validate a Godot self-test log and the process that produced it."""
import argparse
import re
import sys

BAD = re.compile(r"^(?:SCRIPT ERROR|ERROR:|USER ERROR|.*Parse Error|.*\[FAIL\]|.*SELFTEST FAILED).*$")
COMPLETION = "SELFTEST done"
TIMEOUT_EXIT_CODES = {124, 137}
KNOWN_SHUTDOWN_LEAKS = (
    re.compile(r"^WARNING: ObjectDB instances leaked at exit \(run with --verbose for details\)\.$"),
    re.compile(r"^ERROR: [1-9][0-9]* resources still in use at exit \(run with --verbose for details\)\.$"),
    re.compile(r"^ERROR: [1-9][0-9]* RID allocations of type '.+' were leaked at exit\.$"),
)

def _known_shutdown_leak(line: str) -> bool:
    return any(pattern.fullmatch(line.strip()) for pattern in KNOWN_SHUTDOWN_LEAKS)


def check_log_text(text: str, exit_code: int, expected_suite: str | None = None) -> list[str]:
    """Return failures in the complete log, process status, and optional suite marker."""
    lines = text.splitlines()
    completion_index = next((i for i, line in enumerate(lines) if line.strip() == COMPLETION), None)
    problems: list[str] = []
    if completion_index is None:
        problems.append("the self-test never printed 'SELFTEST done' (crash, hang or timeout)")
    if exit_code in TIMEOUT_EXIT_CODES:
        problems.append(f"Godot timed out (process exit code {exit_code})")
    elif exit_code != 0:
        problems.append(f"Godot exited with nonzero process exit code {exit_code}")
    if expected_suite is not None:
        marker = f"SELFTEST suite done: {expected_suite}"
        if marker not in (line.strip() for line in lines):
            problems.append(f"focused suite '{expected_suite}' did not report execution completion")
    for index, line in enumerate(lines):
        if completion_index is not None and index > completion_index and _known_shutdown_leak(line):
            continue
        if BAD.search(line):
            problems.append(line.strip())
    return problems


def check_log_file(path: str, exit_code: int, expected_suite: str | None = None) -> list[str]:
    try:
        with open(path, encoding="utf-8", errors="replace") as log_file:
            text = log_file.read()
    except OSError as exc:
        return [f"cannot read {path}: {exc}"]
    return check_log_text(text, exit_code, expected_suite)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log_path")
    parser.add_argument("--exit-code", required=True, type=int, help="exit code from the Godot/timeout process")
    parser.add_argument("--expected-suite", help="require this exact focused-suite completion marker")
    args = parser.parse_args()
    problems = check_log_file(args.log_path, args.exit_code, args.expected_suite)
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
