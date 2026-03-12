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

if [[ -f "docs/ROADMAP.md" ]]; then
  ROADMAP_FILE="docs/ROADMAP.md"
elif [[ -f "ROADMAP.md" ]]; then
  ROADMAP_FILE="ROADMAP.md"
else
  ROADMAP_FILE=""
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

python3 - "$PRD_FILE" "$CONTRACT_FILE" "$PLAN_FILE" "$ROADMAP_FILE" "${EXTRA_CONTRACT_FILES[@]}" <<'PY'
import json
import os
import re
import sys

prd_path, contract_path, plan_path, roadmap_path, *extra_contract_paths = sys.argv[1:]

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
roadmap_text = ''
if roadmap_path and os.path.isfile(roadmap_path):
    with open(roadmap_path, 'r', encoding='utf-8') as f:
        roadmap_text = f.read()

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
    s = re.sub(r'^(?:docs/)?ROADMAP\.md\s*', '', s, flags=re.IGNORECASE)
    s = s.lstrip(':').strip()
    s = s.lstrip('§').strip()
    return s


def variants(text: str):
    base = normalize(text)
    if not base:
        return []
    out = {base}
    out.add(normalize(number_re.sub('', text.strip())))
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
roadmap_haystack = build_haystack(roadmap_text)

roadmap_categories = {'policy', 'infra'}
roadmap_anchor_re = re.compile(r'^P\d+-[A-Z]\b', re.IGNORECASE)
explicit_roadmap_ref_re = re.compile(r'^(?:docs/)?ROADMAP\.md\b', re.IGNORECASE)


def is_explicit_roadmap_ref(ref: str) -> bool:
    return bool(explicit_roadmap_ref_re.match(str(ref).strip()))


def is_roadmap_anchor_ref(ref: str) -> bool:
    return bool(roadmap_anchor_re.match(strip_prefix(ref)))


def should_resolve_against_roadmap(item: dict, ref: str, default_haystack: str) -> bool:
    ref_text = str(ref)
    if not ref_text.strip():
        return False
    item_category = str(item.get('category', '')).strip().lower()
    if item_category not in roadmap_categories:
        return False
    if is_explicit_roadmap_ref(ref_text):
        return True
    if not is_roadmap_anchor_ref(ref_text):
        return False
    return not resolve_ref(ref_text, default_haystack)

unresolved = []
invalid_roadmap_category = []

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
        ref_text = str(ref)
        if is_explicit_roadmap_ref(ref_text) and str(item.get('category', '')).strip().lower() not in roadmap_categories:
            invalid_roadmap_category.append((item_id, 'contract', ref))
            continue
        if should_resolve_against_roadmap(item, ref_text, contract_haystack):
            if not resolve_ref(ref_text, roadmap_haystack):
                unresolved.append((item_id, 'roadmap', ref))
            continue
        if not resolve_ref(ref_text, contract_haystack):
            unresolved.append((item_id, 'contract', ref))
    for ref in plan_refs:
        if not ref:
            continue
        ref_text = str(ref)
        if is_explicit_roadmap_ref(ref_text) and str(item.get('category', '')).strip().lower() not in roadmap_categories:
            invalid_roadmap_category.append((item_id, 'plan', ref))
            continue
        if should_resolve_against_roadmap(item, ref_text, plan_haystack):
            if not resolve_ref(ref_text, roadmap_haystack):
                unresolved.append((item_id, 'roadmap', ref))
            continue
        if not resolve_ref(ref_text, plan_haystack):
            unresolved.append((item_id, 'plan', ref))

if invalid_roadmap_category:
    for item_id, kind, ref in invalid_roadmap_category:
        print(
            f'[prd_ref_check] ERROR: {item_id} uses ROADMAP ref in {kind}_refs but roadmap refs are only allowed for policy/infra items: {ref}',
            file=sys.stderr,
        )
    raise SystemExit(1)

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

# ── Partial coverage notes check ───────────────────────────────────
# Warn when an AT is in enforcing_contract_ats AND partial_coverage_notes.
# This is not an error — it's a traceability signal that the AT is only
# partially proven by this story. The authoritative tracker is
# docs/reconcile/slices_0_6_reconciliation.md § Deferred ATs table.
for item in items:
    item_id = item.get('id', 'unknown')
    partial = item.get('partial_coverage_notes', {})
    if not isinstance(partial, dict):
        continue
    enforcing = set(item.get('enforcing_contract_ats', []))
    primary = set(item.get('primary_owner_for', []))
    for at_key in sorted(partial.keys()):
        if at_key in enforcing:
            if at_key in primary:
                print(f'[prd_ref_check] WARN: {item_id} has {at_key} in BOTH primary_owner_for AND partial_coverage_notes — remove from primary_owner_for or resolve the partial coverage', file=sys.stderr)
            else:
                print(f'[prd_ref_check] INFO: {item_id} has {at_key} partially covered (see partial_coverage_notes)', file=sys.stderr)

# ── P0 prerequisite check ──────────────────────────────────────────
p0_re = re.compile(r'\bP0-[A-F]\b')
contract_p0 = sorted(set(p0_re.findall(contract_md_text)))

if not contract_p0:
    print('[prd_ref_check] INFO: no P0-[A-F] anchors found in CONTRACT.md (P0 prereq check skipped)', file=sys.stderr)
else:
    prd_p0: set[str] = set()
    for item in items:
        sr = item.get('story_ref')
        if isinstance(sr, str):
            m = re.match(r'^(P0-[A-F])\b', sr.strip())
            if m:
                prd_p0.add(m.group(1))
    missing_p0 = sorted(set(contract_p0) - prd_p0)
    if missing_p0:
        for p in missing_p0:
            print(f'[prd_ref_check] ERROR: Phase-0 prereq {p} required by CONTRACT.md but missing from PRD story_refs', file=sys.stderr)
        raise SystemExit(1)

# ── Endpoint required-key validation (warn-only) ────────────────────
def extract_health_keys(text: str) -> list[str]:
    # Searches for AT-022 block and extracts required /health keys from
    # the "Then:" line (800-char window assumes AT-022 block is compact).
    idx = text.find('AT-022')
    if idx == -1:
        return []
    window = text[idx:idx+800]
    for line in window.splitlines():
        if 'Then:' in line and 'keys' in line:
            return [t for t in re.findall(r'`([a-zA-Z0-9_]+)`', line)
                    if not t.isupper() and '|' not in t and not t.isdigit()]
    return []

def extract_status_csp_keys(text: str) -> list[str]:
    # Marker must match CONTRACT.md verbatim (including ** bold syntax).
    # If the contract reformats this header, extraction returns [] and
    # the caller logs INFO (fail-open, warn-only check).
    marker = '**/status response MUST include (CSP minimum):**'
    idx = text.find(marker)
    if idx == -1:
        return []
    keys = []
    for line in text[idx:idx+2000].splitlines()[1:]:
        if not line.strip():
            break
        if line.lstrip().startswith('-'):
            for t in re.findall(r'`([a-zA-Z0-9_]+)`', line):
                if not t.isupper() and '|' not in t and not t.isdigit() and t not in keys:
                    keys.append(t)
        if line.startswith('AT-') or line.startswith('####') or line.startswith('**'):
            break
    return keys

health_keys = extract_health_keys(contract_md_text)
status_keys = extract_status_csp_keys(contract_md_text)
foundation_status_lite_keys = [
    'service_up',
    'build_id',
    'contract_version',
    'dispatch_enabled',
    'phase',
]
compact_csp_status_markers = (
    'csp minimum key set required by at-023/at-405/at-419/at-907/at-927/at-1117',
    'schema/profile/mode/risk fields',
    'policy freshness fields',
    'certification fields',
    '5m rate-limit counters',
    'durability-queue counters',
    'open-permission fields',
)


def has_compact_csp_status_markers(acc_blob: str, text_blob: str) -> bool:
    return ('status_mode=compact_csp_status_markers' in text_blob) and all(marker in acc_blob for marker in compact_csp_status_markers)

def classify_status_story_mode(item: dict, acc_blob: str, story_ref_lower: str) -> tuple[str, str | None]:
    if '/status' not in acc_blob and '/api/v1/status' not in acc_blob and '/status' not in story_ref_lower:
        return ('non_status_story', None)
    text_blob = ' '.join(
        str(x) for x in (
            item.get('acceptance', [])
            + item.get('verify', [])
            + item.get('contract_refs', [])
            + item.get('plan_refs', [])
            + [item.get('story_ref', '')]
        )
    ).lower()
    has_mode_marker = 'status_mode=foundation_status_lite' in text_blob
    has_phase_marker = ('phase == foundation' in text_blob) or ('phase=foundation' in text_blob)
    has_dispatch_marker = 'dispatch_enabled=false' in text_blob
    has_legacy_hint = ('status-lite' in text_blob) or ('foundation /status' in text_blob)
    has_foundation_marker = has_mode_marker or has_phase_marker or has_dispatch_marker or has_legacy_hint

    if not has_foundation_marker:
        return ('csp', None)

    missing_markers = []
    if not has_phase_marker:
        missing_markers.append('phase marker (`phase == foundation` or `phase=foundation`)')
    if not has_dispatch_marker:
        missing_markers.append('dispatch marker (`dispatch_enabled=false`)')
    if missing_markers:
        return (
            'malformed_foundation_status_lite',
            'malformed foundation status-lite markers: missing ' + ', '.join(missing_markers),
        )
    return ('foundation_status_lite', None)

if not health_keys:
    print('[prd_ref_check] INFO: no /health required keys extracted from contract (AT-022)', file=sys.stderr)
if not status_keys:
    print('[prd_ref_check] INFO: no /status CSP required keys extracted from contract', file=sys.stderr)

status_mode_errors = 0
for item in items:
    sid = item.get('id', 'unknown')
    acc_blob = ' '.join(str(x) for x in (item.get('acceptance', []) + item.get('verify', []))).lower()
    story_ref_lower = str(item.get('story_ref', '')).lower()
    if '/health' in acc_blob or '/api/v1/health' in acc_blob or '/health' in story_ref_lower:
        for k in health_keys:
            if k.lower() not in acc_blob:
                print(f'[prd_ref_check] WARN: {sid} references /health but acceptance missing required key "{k}"', file=sys.stderr)
    if '/status' in acc_blob or '/api/v1/status' in acc_blob or '/status' in story_ref_lower:
        mode, marker_error = classify_status_story_mode(item, acc_blob, story_ref_lower)
        if mode == 'malformed_foundation_status_lite':
            status_mode_errors += 1
            print(f'[prd_ref_check] ERROR: {sid} {marker_error}', file=sys.stderr)
            continue
        if mode == 'foundation_status_lite':
            for k in foundation_status_lite_keys:
                if k.lower() not in acc_blob:
                    print(
                        f'[prd_ref_check] WARN: {sid} references /status foundation status-lite but acceptance missing required key "{k}"',
                        file=sys.stderr,
                    )
        else:
            if has_compact_csp_status_markers(acc_blob, ' '.join(
                str(x) for x in (
                    item.get('acceptance', [])
                    + item.get('verify', [])
                    + item.get('contract_refs', [])
                    + item.get('plan_refs', [])
                    + [item.get('story_ref', '')]
                )
            ).lower()):
                continue
            for k in status_keys:
                if k.lower() not in acc_blob:
                    print(f'[prd_ref_check] WARN: {sid} references /status but acceptance missing required CSP key "{k}"', file=sys.stderr)

if status_mode_errors:
    raise SystemExit(1)

raise SystemExit(0)
PY
