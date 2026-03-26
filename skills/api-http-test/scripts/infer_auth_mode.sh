#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${1:-${HTTP_PROJECT_ROOT:-${DB_PROJECT_ROOT:-$PWD}}}"
export PROJECT_ROOT

python3 - <<'PY'
import os
import re
from pathlib import Path

project_root = Path(os.environ["PROJECT_ROOT"])
if not project_root.is_dir():
    print("mode=auto")
    print("confidence=low")
    print("reason=project root not found")
    raise SystemExit(0)

ignore_dirs = {".git", "node_modules", ".cursor", ".skills", "dist", "build"}
max_file_size = 1_000_000

patterns = {
    "bearer": re.compile(r"authorization[^\n]{0,40}bearer|jwt|access[_-]?token|refresh[_-]?token", re.I),
    "basic": re.compile(r"authorization[^\n]{0,40}basic|basic auth", re.I),
    "api_key": re.compile(r"x-api-key|api[_-]?key|apikey", re.I),
}
hits = {"bearer": 0, "basic": 0, "api_key": 0}

for path in project_root.rglob("*"):
    if not path.is_file():
        continue
    if any(part in ignore_dirs for part in path.parts):
        continue
    try:
        if path.stat().st_size > max_file_size:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    for key, rx in patterns.items():
        hits[key] += len(rx.findall(text))

mode = "auto"
confidence = "low"
reason = "no clear auth pattern"

bearer_hits = hits["bearer"]
basic_hits = hits["basic"]
apikey_hits = hits["api_key"]

if bearer_hits > basic_hits and bearer_hits > apikey_hits and bearer_hits > 0:
    mode, confidence, reason = "bearer", "high", f"bearer/jwt patterns found ({bearer_hits})"
elif basic_hits > bearer_hits and basic_hits > apikey_hits and basic_hits > 0:
    mode, confidence, reason = "basic", "high", f"basic auth patterns found ({basic_hits})"
elif apikey_hits > bearer_hits and apikey_hits > basic_hits and apikey_hits > 0:
    mode, confidence, reason = "api_key", "high", f"api key patterns found ({apikey_hits})"
elif bearer_hits > 0 or basic_hits > 0 or apikey_hits > 0:
    top = max(hits, key=hits.get)
    mode = top
    confidence = "medium"
    reason = f"mixed auth patterns (bearer={bearer_hits}, basic={basic_hits}, api_key={apikey_hits})"

print(f"mode={mode}")
print(f"confidence={confidence}")
print(f"reason={reason}")
PY
