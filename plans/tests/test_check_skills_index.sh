#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

mkdir -p "$TMP_DIR/docs/skills" "$TMP_DIR/plans/prompts" "$TMP_DIR/scripts" "$TMP_DIR/SKILLS"
python3 - <<'PY' "$ROOT" "$TMP_DIR"
from pathlib import Path
import re
import shutil
import sys

root = Path(sys.argv[1])
tmp_dir = Path(sys.argv[2])
index_path = root / "docs/skills/index.md"
paths = set(re.findall(r"`((?:SKILLS|plans/prompts|scripts)/[^`]+)`", index_path.read_text(encoding="utf-8")))
paths.update(
    {
        "scripts/check_skills_index.py",
        "docs/skills/index.md",
        "plans/prompts/review-stack.md",
    }
)
for rel_path in sorted(paths):
    source = root / rel_path
    if not source.is_file():
        raise SystemExit(f"missing source path in repo fixture setup: {rel_path}")
    dest = tmp_dir / rel_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, dest)
PY

(cd "$TMP_DIR" && python3 scripts/check_skills_index.py >/dev/null) || fail "checker should pass on copied repo state"

python3 - <<'PY' "$TMP_DIR/docs/skills/index.md"
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = "| 7-Skill Review Stack | `plans/prompts/review-stack.md` | All 7 review skills in sequence |"
new = "| 6-Skill Review Stack | `plans/prompts/review-stack.md` | All 6 review skills in sequence |"
if old not in text:
    raise SystemExit("expected review-stack row missing")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

if (cd "$TMP_DIR" && python3 scripts/check_skills_index.py >/dev/null 2>&1); then
  fail "checker should fail on drifted review-stack metadata"
fi

echo "PASS: check_skills_index"
