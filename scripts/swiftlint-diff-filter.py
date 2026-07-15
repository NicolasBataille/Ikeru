#!/usr/bin/env python3
"""Filter SwiftLint JSON output down to violations on lines a PR actually touched.

Usage:
    swiftlint lint --reporter json <files...> | \
        python3 scripts/swiftlint-diff-filter.py <base-ref>

Reads SwiftLint's JSON report on stdin, computes the added/modified line
ranges of `git diff -U0 <base-ref>...HEAD`, and re-emits (and fails on) only
the violations that fall inside those ranges. File-level violations with no
meaningful line anchor (file_length, type_body_length) are attributed to the
diff only when the file is entirely new in this PR — pre-existing bloat in a
lightly-touched legacy file must not block an unrelated change (that backlog
is surfaced by the whole-repo non-strict pass and tracked for refactoring).

Exit codes: 0 = no violations on touched lines; 1 = at least one.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

FILE_LEVEL_RULES = {"file_length", "type_body_length"}


def changed_ranges(base_ref: str) -> dict[str, list[range]]:
    """Map repo-relative path -> list of added-line ranges in HEAD."""
    diff = subprocess.run(
        ["git", "diff", "-U0", "--diff-filter=ACMR", f"{base_ref}...HEAD", "--", "*.swift"],
        capture_output=True, text=True, check=True,
    ).stdout
    ranges: dict[str, list[range]] = {}
    current: str | None = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
            ranges.setdefault(current, [])
        elif line.startswith("@@") and current:
            match = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if match:
                start = int(match.group(1))
                count = int(match.group(2)) if match.group(2) is not None else 1
                if count > 0:
                    ranges[current].append(range(start, start + count))
    return ranges


def new_files(base_ref: str) -> set[str]:
    out = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=A", f"{base_ref}...HEAD", "--", "*.swift"],
        capture_output=True, text=True, check=True,
    ).stdout
    return {line.strip() for line in out.splitlines() if line.strip()}


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: swiftlint-diff-filter.py <base-ref>", file=sys.stderr)
        return 2
    base_ref = sys.argv[1]

    raw = sys.stdin.read().strip()
    violations = json.loads(raw) if raw else []
    ranges = changed_ranges(base_ref)
    added = new_files(base_ref)
    repo_root = Path(
        subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True)
        .stdout.strip()
    )

    blocking = []
    for violation in violations:
        rel = str(Path(violation["file"]).resolve().relative_to(repo_root))
        rule = violation.get("rule_id", "")
        line = violation.get("line") or 0
        if rule in FILE_LEVEL_RULES:
            if rel in added:
                blocking.append((rel, violation))
            continue
        if any(line in r for r in ranges.get(rel, [])):
            blocking.append((rel, violation))

    skipped = len(violations) - len(blocking)
    if skipped:
        print(f"ℹ️  {skipped} violation(s) on untouched lines ignored (pre-existing; see the non-strict pass).")
    for rel, violation in blocking:
        print(
            f"::error file={rel},line={violation.get('line', 1)}::"
            f"{violation.get('rule_id')}: {violation.get('reason')}"
        )
    if blocking:
        print(f"✖ {len(blocking)} violation(s) on lines this PR touched — fix them.")
        return 1
    print("✓ No SwiftLint violations on touched lines.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
