#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PRD_FILE="${PRD_FILE:-${1:-plans/prd.json}}"

if [[ -z "$PRD_FILE" || ! -f "$PRD_FILE" ]]; then
  echo "[prd_ref_check] ERROR: missing PRD file: $PRD_FILE" >&2
  exit 2
fi

CONTRACT_FILE="specs/CONTRACT.md"

if [[ -f "specs/IMPLEMENTATION_PLAN.md" ]]; then
  PLAN_FILE="specs/IMPLEMENTATION_PLAN.md"
else
  PLAN_FILE="IMPLEMENTATION_PLAN.md"
fi

if [[ ! -f "$CONTRACT_FILE" ]]; then
  echo "[prd_ref_check] ERROR: contract file missing: specs/CONTRACT.md" >&2
  exit 2
fi

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "[prd_ref_check] ERROR: implementation plan missing: $PLAN_FILE" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[prd_ref_check] ERROR: python3 required" >&2
  exit 2
fi

EXTRA_CONTRACT_FILES=()
if [[ -f "docs/architecture/contract_anchors.md" ]]; then
  EXTRA_CONTRACT_FILES+=("docs/architecture/contract_anchors.md")
fi
if [[ -f "docs/architecture/validation_rules.md" ]]; then
  EXTRA_CONTRACT_FILES+=("docs/architecture/validation_rules.md")
fi
if [[ -f "docs/contract_kernel.json" ]]; then
  EXTRA_CONTRACT_FILES+=("docs/contract_kernel.json")
fi

python3 - "$PRD_FILE" "$CONTRACT_FILE" "$PLAN_FILE" "${EXTRA_CONTRACT_FILES[@]}" <<'PY'
import json
import os
import re
import sys

prd_path, contract_path, plan_path, *extra_contract_paths = sys.argv[1:]

with open(prd_path, 'r', encoding='utf-8') as f:
    prd = json.load(f)

items = prd.get('items', [])
if not isinstance(items, list):
    print('[prd_ref_check] ERROR: PRD items must be an array', file=sys.stderr)
    raise SystemExit(2)

with open(contract_path, 'r', encoding='utf-8') as f:
    contract_text = f.read()
for extra_path in extra_contract_paths:
    if not extra_path:
        continue
    if not os.path.isfile(extra_path):
        continue
    with open(extra_path, 'r', encoding='utf-8') as f:
        contract_text += "\n" + f.read()
with open(plan_path, 'r', encoding='utf-8') as f:
    plan_text = f.read()

heading_re = re.compile(r'^#{1,6}\s+')
bullet_re = re.compile(r'^[-*+]\s+')
number_re = re.compile(r'^\d+[\).]\s+')


def normalize(text: str) -> str:
    s = text.strip()
    if not s:
        return ''
    s = s.replace('§', '')
    s = s.replace('\\', '')
    s = s.replace('`', '')
    s = s.replace('*', '')
    s = s.replace('_', '')
    s = re.sub(r'[–—]', '-', s)
    s = re.sub(r'\s+', ' ', s)
    return s.strip().lower()


def build_haystack(text: str) -> str:
    lines = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        line = heading_re.sub('', line)
        line = bullet_re.sub('', line)
        line = number_re.sub('', line)
        lines.append(line)
    return normalize(' '.join(lines))


def strip_prefix(ref: str) -> str:
    s = ref.strip()
    s = re.sub(r'^(?:specs/)?CONTRACT\.md\s*', '', s, flags=re.IGNORECASE)
    s = re.sub(r'^(?:specs/)?IMPLEMENTATION_PLAN\.md\s*', '', s, flags=re.IGNORECASE)
    s = s.lstrip(':').strip()
    s = s.lstrip('§').strip()
    return s


def variants(text: str):
    base = normalize(text)
    if not base:
        return []
    out = {base}
    if base.endswith(':'):
        out.add(base[:-1].strip())
    out.add(re.sub(r'\s*\([^)]*\)\s*$', '', base).strip())
    out.add(re.sub(r'\s+MUST implement:?$', '', base, flags=re.IGNORECASE).strip())
    out = {v for v in out if v}
    return list(out)


section_id_re = re.compile(r'^([0-9]+(?:\.[0-9A-Z]+)*)\s+(.*)$', re.IGNORECASE)


def split_segments(ref: str):
    s = strip_prefix(ref)
    if not s:
        return []
    parts = [p.strip() for p in s.split('/') if p.strip()]
    if not parts:
        parts = [s]
    expanded = []
    for part in parts:
        m = section_id_re.match(part)
        if m:
            expanded.append(m.group(1))
            tail = m.group(2).strip()
            if tail:
                expanded.append(tail)
        else:
            expanded.append(part)
    return expanded


def resolve_ref(ref: str, haystack: str) -> bool:
    for segment in split_segments(ref):
        ok = False
        for candidate in variants(segment):
            if candidate and candidate in haystack:
                ok = True
                break
        if not ok:
            return False
    return True


contract_haystack = build_haystack(contract_text)
plan_haystack = build_haystack(plan_text)

unresolved = []

for item in items:
    item_id = item.get('id', 'unknown')
    contract_refs = item.get('contract_refs', []) or []
    plan_refs = item.get('plan_refs', []) or []
    if not isinstance(contract_refs, list):
        print(f'[prd_ref_check] ERROR: contract_refs must be an array for {item_id}', file=sys.stderr)
        raise SystemExit(2)
    if not isinstance(plan_refs, list):
        print(f'[prd_ref_check] ERROR: plan_refs must be an array for {item_id}', file=sys.stderr)
        raise SystemExit(2)

    for ref in contract_refs:
        if not ref:
            continue
        if not resolve_ref(str(ref), contract_haystack):
            unresolved.append((item_id, 'contract', ref))
    for ref in plan_refs:
        if not ref:
            continue
        if not resolve_ref(str(ref), plan_haystack):
            unresolved.append((item_id, 'plan', ref))

if unresolved:
    for item_id, kind, ref in unresolved:
        print(f'[prd_ref_check] ERROR: unresolved {kind}_ref for {item_id}: {ref}', file=sys.stderr)
    raise SystemExit(1)

# ── AT-reference integrity ──────────────────────────────────────────
# Every AT-* in PRD enforcing_contract_ats must exist in CONTRACT.md.
# ATs listed in specs/contract_deferred_ats.yml are exempt from the
# uncovered-contract-AT warning, but they still must exist in CONTRACT.md.

at_re = re.compile(r'AT-\d+')
# Extract ATs from CONTRACT.md only — extra files are used for reference
# resolution but must not inflate the contract AT inventory.
with open(contract_path, 'r', encoding='utf-8') as f:
    contract_md_text = f.read()
contract_ats = set(at_re.findall(contract_md_text))

prd_ats: dict[str, list[str]] = {}  # AT -> [item_ids]
for item in items:
    item_id = item.get('id', 'unknown')
    for ref in item.get('enforcing_contract_ats', []):
        for m in at_re.findall(str(ref)):
            prd_ats.setdefault(m, []).append(item_id)

# Load deferred allowlist (optional)
deferred_ats: set[str] = set()
deferred_meta: dict[str, set[str]] = {}
required_meta_fields = ('owner', 'reason', 'target_phase')
deferred_path = os.path.join(os.path.dirname(contract_path), 'contract_deferred_ats.yml')
if os.path.isfile(deferred_path):
    # Minimal YAML-free parsing: top-level keys matching AT-\d+
    # and required metadata fields (owner, reason, target_phase).
    current_at: str | None = None
    with open(deferred_path, 'r', encoding='utf-8') as f:
        for line in f:
            at_match = re.match(r'^(AT-\d+)\s*:', line)
            if at_match:
                current_at = at_match.group(1)
                deferred_ats.add(current_at)
                deferred_meta.setdefault(current_at, set())
                continue
            # Indented metadata under the current AT
            if current_at and re.match(r'^\s+\S', line):
                meta_match = re.match(r'^\s+(owner|reason|target_phase)\s*:', line)
                if meta_match:
                    deferred_meta[current_at].add(meta_match.group(1))

    # Validate that each deferred AT has all required metadata fields.
    for at in sorted(deferred_ats, key=lambda x: int(x.split('-')[1])):
        present = deferred_meta.get(at, set())
        missing = [f for f in required_meta_fields if f not in present]
        if missing:
            print(
                f'[prd_ref_check] ERROR: deferred AT {at} is missing required metadata field(s): {", ".join(missing)}',
                file=sys.stderr,
            )
            raise SystemExit(2)

dangling = sorted(set(prd_ats) - contract_ats, key=lambda x: int(x.split('-')[1]))
if dangling:
    for at in dangling:
        stories = ', '.join(prd_ats[at])
        print(f'[prd_ref_check] ERROR: PRD references {at} (stories: {stories}) but it does not exist in CONTRACT.md', file=sys.stderr)
    raise SystemExit(1)

uncovered = sorted(contract_ats - set(prd_ats) - deferred_ats, key=lambda x: int(x.split('-')[1]))
if uncovered:
    print(f'[prd_ref_check] WARN: {len(uncovered)} contract AT(s) not covered by PRD and not deferred: {", ".join(uncovered[:10])}{"..." if len(uncovered) > 10 else ""}', file=sys.stderr)

raise SystemExit(0)
PY
