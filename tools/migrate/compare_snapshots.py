"""Diff two snapshot_api.py files, field by field.

    python compare_snapshots.py OLD.json NEW.json

Exit status 0 only if every answer is identical: same status, same body,
floats included. Numbers are compared exactly on purpose — the point of
phase 2b is that moving the data changed nothing, and "close enough" is
how a wrong number stays invisible.

Prints each difference with its path inside the answer, e.g.
`/training/status?days=730 .series[412].fitness: 41.62 != 41.63`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def diff(old, new, path: str, out: list[str]) -> None:
    if isinstance(old, dict) and isinstance(new, dict):
        for key in sorted(set(old) | set(new)):
            if key not in old:
                out.append(f"{path}.{key}: missing in old, new={new[key]!r}")
            elif key not in new:
                out.append(f"{path}.{key}: missing in new, old={old[key]!r}")
            else:
                diff(old[key], new[key], f"{path}.{key}", out)
    elif isinstance(old, list) and isinstance(new, list):
        if len(old) != len(new):
            out.append(f"{path}: {len(old)} items != {len(new)} items")
        for index, (a, b) in enumerate(zip(old, new, strict=False)):
            diff(a, b, f"{path}[{index}]", out)
    elif old != new or type(old) is not type(new):
        out.append(f"{path}: {old!r} != {new!r}")


def main() -> None:
    old = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    new = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
    differences: list[str] = []
    for request in sorted(set(old) | set(new)):
        if request not in new:
            differences.append(f"{request}: not asked of the new API")
            continue
        if request not in old:
            differences.append(f"{request}: not asked of the old API")
            continue
        diff(old[request], new[request], request, differences)
    for line in differences[:200]:
        print(line)
    print(f"{len(old)} requests compared, {len(differences)} difference(s)")
    sys.exit(1 if differences else 0)


if __name__ == "__main__":
    main()
