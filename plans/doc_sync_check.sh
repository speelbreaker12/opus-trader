#!/usr/bin/env bash
# doc_sync_check.sh — Fail-closed cross-document validation gate
# Validates consistency between IMPLEMENTATION_PLAN.md, prd.json, and disk.
#
# Exit codes: 0=pass, 1=findings, 2=infrastructure error
# Kill switch: DOC_SYNC_GATE=0 → skip with warning, exit 0
set -euo pipefail
IFS=$'\n\t'

TAG="[doc_sync_check]"

if [[ "${DOC_SYNC_GATE:-1}" == "0" ]]; then
  echo "$TAG WARN: doc_sync_check skipped (DOC_SYNC_GATE=0)" >&2
  exit 0
fi

# Infrastructure guards
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "$TAG ERROR: not in a git repository" >&2
  exit 2
}
cd "$REPO_ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "$TAG ERROR: python3 required" >&2
  exit 2
fi

PRD_FILE="${PRD_FILE:-plans/prd.json}"
if [[ ! -f "$PRD_FILE" ]]; then
  echo "$TAG ERROR: PRD file missing: $PRD_FILE" >&2
  exit 2
fi

if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PRD_FILE" 2>/dev/null; then
  echo "$TAG ERROR: PRD file is not valid JSON: $PRD_FILE" >&2
  exit 2
fi

if [[ -f "specs/IMPLEMENTATION_PLAN.md" ]]; then
  IMPL_PLAN="specs/IMPLEMENTATION_PLAN.md"
elif [[ -f "IMPLEMENTATION_PLAN.md" ]]; then
  IMPL_PLAN="IMPLEMENTATION_PLAN.md"
else
  echo "$TAG ERROR: IMPLEMENTATION_PLAN.md not found" >&2
  exit 2
fi

python3 - "$PRD_FILE" "$IMPL_PLAN" "$REPO_ROOT" <<'PY'
import json
import os
import re
import sys

prd_path, impl_plan_path, repo_root = sys.argv[1:]

TAG = "[doc_sync_check]"

# ── Load data ───────────────────────────────────────────────────────
with open(prd_path, 'r', encoding='utf-8') as f:
    prd = json.load(f)

items = prd.get('items', [])
if not isinstance(items, list):
    print(f'{TAG} ERROR: PRD items must be an array', file=sys.stderr)
    raise SystemExit(2)

with open(impl_plan_path, 'r', encoding='utf-8') as f:
    impl_plan_text = f.read()

# ── Known gaps: IMPL_PLAN stories with no PRD counterpart yet ──────
# These exist in IMPL_PLAN but have no PRD items (future Phase 2+ stories).
# Only TRUE gaps belong here — stories covered by variants (S8.1a, S8.1b)
# are matched by the regex and should NOT be listed.
known_impl_plan_gaps = {"S8.11", "S8.12", "S14.2"}

# ── Path-like heuristic ────────────────────────────────────────────
KNOWN_EXTENSIONS = {'.md', '.json', '.rs', '.py', '.sh', '.yaml', '.yml', '.toml', '.txt'}

def is_path_like(entry: str) -> bool:
    """Return True if entry looks like a file path, not prose.

    Heuristic: a path-like entry is one where the ENTIRE string (after
    stripping leading/trailing whitespace) is a plausible file path.
    Prose entries that embed paths (e.g., "docs/foo.md exists with content")
    are filtered out by checking for spaces after the first path component,
    template placeholders (<...>), and common prose prefixes.
    """
    s = entry.strip()
    if not s:
        return False
    # Template placeholders are not real paths
    if '<' in s:
        return False
    # If entry contains spaces, check if the first token is path-like
    # and the rest looks like prose (e.g., "docs/foo.md exists with content")
    if ' ' in s:
        # Multi-word entries are prose descriptions, not file paths
        return False
    if '/' in s:
        return True
    _, ext = os.path.splitext(s)
    return ext.lower() in KNOWN_EXTENSIONS

def strip_test_suffix(path: str) -> str:
    """Strip ::function_name suffix from test paths."""
    if '::' in path:
        path = path[:path.index('::')]
    return path

def safe_path(repo_root: str, rel: str):  # -> Optional[str]
    """Resolve path relative to repo root; return None if it escapes."""
    joined = os.path.normpath(os.path.join(repo_root, rel))
    # Use trailing sep to prevent prefix attacks (e.g., /repo vs /repo-evil)
    root_prefix = repo_root.rstrip(os.sep) + os.sep
    if not (joined == repo_root or joined.startswith(root_prefix)):
        return None
    return joined

# ── Check A: Story ID bidirectional match ──────────────────────────
errors: list[str] = []

# Extract IMPL_PLAN story IDs from story headers only
# Matches lines like "S1.0 — Valid Story Name" or "S1.0 - Name"
impl_story_re = re.compile(r'^(S\d+\.\d+)\s+[—–\-]')
impl_story_ids: set[str] = set()
for line in impl_plan_text.splitlines():
    m = impl_story_re.match(line.strip())
    if m:
        impl_story_ids.add(m.group(1))

# Extract PRD story_ref base IDs (S\d+.\d+ prefix, allowing optional letter suffix)
# Examples: "S8.1 Foo" -> S8.1, "S8.1a Foo" -> S8.1, "S8.10 Bar" -> S8.10
# Requires a real separator after the ID+suffix (space, end, or dash) to reject
# malformed refs like "S8.1aFoo" (no separator).
prd_story_ref_re = re.compile(r'^(S\d+\.\d+)(?:[a-z])?(?=\s|$|[—–\-])')
prd_story_refs: dict[str, list[str]] = {}  # impl_plan_id -> [prd_item_ids]
prd_variant_refs: dict[str, list[str]] = {}  # impl_plan_id -> [prd_item_ids that used a/b/c suffix]
skipped_refs: list[str] = []

for item in items:
    item_id = item.get('id', 'unknown')
    story_ref = item.get('story_ref', '')
    if not isinstance(story_ref, str) or not story_ref.strip():
        continue
    first_token = story_ref.strip().split()[0]
    m = prd_story_ref_re.match(first_token)
    if m:
        sid = m.group(1)
        prd_story_refs.setdefault(sid, []).append(item_id)
        # Track whether this was a variant ref (has letter suffix)
        suffix_after = first_token[m.end(1):]
        if suffix_after and suffix_after[0].isalpha():
            prd_variant_refs.setdefault(sid, []).append(item_id)
    else:
        skipped_refs.append(f"{item_id} ({first_token})")

if skipped_refs:
    print(f'{TAG} INFO: skipped {len(skipped_refs)} non-S-dot-notation story_refs: {", ".join(skipped_refs[:5])}{"..." if len(skipped_refs) > 5 else ""}', file=sys.stderr)

# Check: IMPL_PLAN stories not referenced by any PRD item
for sid in sorted(impl_story_ids):
    if sid in known_impl_plan_gaps:
        print(f'{TAG} INFO: TRUE_GAP — {sid} in IMPL_PLAN has no PRD counterpart (expected)', file=sys.stderr)
        continue
    if sid not in prd_story_refs:
        errors.append(f'IMPL_PLAN story {sid} not referenced by any PRD item')
    elif sid in prd_variant_refs and sid not in (
        set(prd_story_refs.keys()) - set(prd_variant_refs.keys())
    ):
        # All PRD refs for this story use variant suffixes (a/b/c), none use the bare ID
        only_variants = all(item_id in prd_variant_refs.get(sid, []) for item_id in prd_story_refs[sid])
        if only_variants:
            variants = ', '.join(prd_variant_refs[sid])
            print(f'{TAG} INFO: COVERED_BY_VARIANTS — {sid} has PRD items via variants only ({variants})', file=sys.stderr)

# Check: PRD items referencing non-existent IMPL_PLAN stories
all_referenced = set(prd_story_refs.keys())
for sid in sorted(all_referenced):
    if sid not in impl_story_ids:
        referencing = ', '.join(prd_story_refs[sid])
        errors.append(f'PRD items ({referencing}) reference IMPL_PLAN story {sid} which does not exist')

# Staleness check: warn if a known gap now has PRD coverage (gap closed)
for sid in sorted(known_impl_plan_gaps):
    if sid in prd_story_refs:
        print(f'{TAG} WARN: known gap {sid} now has PRD coverage — remove from known_impl_plan_gaps', file=sys.stderr)

# ── Check B: Evidence file existence (passes=true only) ────────────
for item in items:
    if not item.get('passes', False):
        continue
    item_id = item.get('id', 'unknown')
    evidence = item.get('evidence', [])
    if not isinstance(evidence, list):
        continue
    for ev in evidence:
        if not isinstance(ev, str) or not ev.strip():
            continue
        if not is_path_like(ev):
            continue  # Skip prose entries silently
        resolved = safe_path(repo_root, ev)
        if resolved is None:
            errors.append(f'{item_id}: evidence path escapes repo root: {ev}')
            continue
        if not os.path.exists(resolved):
            errors.append(f'{item_id}: evidence file missing: {ev}')

# ── Check C: Test file existence (passes=true only) ────────────────
for item in items:
    if not item.get('passes', False):
        continue
    item_id = item.get('id', 'unknown')
    tests = item.get('implementation_tests', [])
    if not isinstance(tests, list):
        continue
    for t in tests:
        if not isinstance(t, str) or not t.strip():
            continue
        cleaned = strip_test_suffix(t)
        if not is_path_like(cleaned):
            continue  # Skip bare identifiers like "RiskState::Degraded"
        resolved = safe_path(repo_root, cleaned)
        if resolved is None:
            errors.append(f'{item_id}: test path escapes repo root: {cleaned}')
            continue
        if not os.path.exists(resolved):
            errors.append(f'{item_id}: test file missing: {cleaned}')

# ── Report ──────────────────────────────────────────────────────────
if errors:
    for e in errors:
        print(f'{TAG} ERROR: {e}', file=sys.stderr)
    print(f'{TAG} FAIL: {len(errors)} finding(s)', file=sys.stderr)
    raise SystemExit(1)

print(f'{TAG} PASS: all cross-document checks passed', file=sys.stderr)
raise SystemExit(0)
PY
