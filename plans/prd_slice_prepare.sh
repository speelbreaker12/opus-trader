#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PRD_FILE="${PRD_FILE:-plans/prd.json}"
PRD_SLICE="${PRD_SLICE:-}"
CONTRACT_DIGEST="${CONTRACT_DIGEST:-.context/contract_digest.json}"
PLAN_DIGEST="${PLAN_DIGEST:-.context/plan_digest.json}"
ROADMAP_DIGEST="${ROADMAP_DIGEST:-}"
OUT_PRD_SLICE="${OUT_PRD_SLICE:-.context/prd_slice.json}"
OUT_CONTRACT_DIGEST="${OUT_CONTRACT_DIGEST:-.context/contract_digest_slice.json}"
OUT_PLAN_DIGEST="${OUT_PLAN_DIGEST:-.context/plan_digest_slice.json}"
OUT_ROADMAP_DIGEST="${OUT_ROADMAP_DIGEST:-.context/roadmap_digest_slice.json}"
OUT_AUDIT_FILE="${OUT_AUDIT_FILE:-plans/prd_audit.json}"
OUT_META="${OUT_META:-.context/prd_audit_meta.json}"

if [[ -z "$PRD_SLICE" ]]; then
  echo "[prd_slice_prepare] ERROR: PRD_SLICE is required" >&2
  exit 2
fi
if [[ ! -f "$PRD_FILE" ]]; then
  echo "[prd_slice_prepare] ERROR: missing PRD file: $PRD_FILE" >&2
  exit 2
fi
if [[ ! -f "$CONTRACT_DIGEST" ]]; then
  echo "[prd_slice_prepare] ERROR: missing contract digest: $CONTRACT_DIGEST" >&2
  exit 2
fi
if [[ ! -f "$PLAN_DIGEST" ]]; then
  echo "[prd_slice_prepare] ERROR: missing plan digest: $PLAN_DIGEST" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "[prd_slice_prepare] ERROR: python3 required" >&2
  exit 2
fi

python3 - "$PRD_FILE" "$PRD_SLICE" "$CONTRACT_DIGEST" "$PLAN_DIGEST" "$ROADMAP_DIGEST" "$OUT_PRD_SLICE" "$OUT_CONTRACT_DIGEST" "$OUT_PLAN_DIGEST" "$OUT_ROADMAP_DIGEST" "$OUT_AUDIT_FILE" "$OUT_META" <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

prd_path, slice_str, contract_digest_path, plan_digest_path, roadmap_digest_path, out_prd_slice, out_contract_slice, out_plan_slice, out_roadmap_slice, out_audit_file, out_meta = sys.argv[1:]

try:
    slice_num = int(slice_str)
except ValueError:
    print(f"[prd_slice_prepare] ERROR: PRD_SLICE must be an integer (got {slice_str})", file=sys.stderr)
    raise SystemExit(2)

with open(prd_path, 'rb') as f:
    prd_bytes = f.read()
try:
    prd = json.loads(prd_bytes)
except json.JSONDecodeError:
    print(f"[prd_slice_prepare] ERROR: PRD JSON invalid: {prd_path}", file=sys.stderr)
    raise SystemExit(2)

prd_sha = hashlib.sha256(prd_bytes).hexdigest()

items = prd.get('items', [])
if not isinstance(items, list):
    print("[prd_slice_prepare] ERROR: PRD items must be an array", file=sys.stderr)
    raise SystemExit(2)

ids = []
for item in items:
    ids.append(item.get('id'))
missing_ids = [idx for idx, val in enumerate(ids) if not val]
if missing_ids:
    print(f"[prd_slice_prepare] ERROR: PRD items missing id at indices {missing_ids}", file=sys.stderr)
    raise SystemExit(2)

dupes = sorted({i for i in ids if ids.count(i) > 1})
if dupes:
    print(f"[prd_slice_prepare] ERROR: duplicate PRD ids: {', '.join(dupes)}", file=sys.stderr)
    raise SystemExit(2)

last_slice = None
for item in items:
    slice_val = item.get('slice')
    if not isinstance(slice_val, int):
        print(f"[prd_slice_prepare] ERROR: invalid slice value for {item.get('id')}: {slice_val}", file=sys.stderr)
        raise SystemExit(2)
    if last_slice is not None and slice_val < last_slice:
        print(f"[prd_slice_prepare] ERROR: PRD slices out of order (found {slice_val} after {last_slice})", file=sys.stderr)
        raise SystemExit(2)
    last_slice = slice_val

id_to_slice = {item['id']: item['slice'] for item in items}

for item in items:
    deps = item.get('dependencies', []) or []
    if not isinstance(deps, list):
        print(f"[prd_slice_prepare] ERROR: dependencies must be an array for {item.get('id')}", file=sys.stderr)
        raise SystemExit(2)
    for dep in deps:
        if dep not in id_to_slice:
            print(f"[prd_slice_prepare] ERROR: dependency {dep} not found (item {item.get('id')})", file=sys.stderr)
            raise SystemExit(2)
        if id_to_slice[dep] > item['slice']:
            print(f"[prd_slice_prepare] ERROR: dependency {dep} in higher slice ({id_to_slice[dep]} > {item['slice']})", file=sys.stderr)
            raise SystemExit(2)

# Cycle detection
adj = {item['id']: list(item.get('dependencies', []) or []) for item in items}
visiting = set()
visited = set()

def has_cycle(node: str) -> bool:
    if node in visited:
        return False
    if node in visiting:
        return True
    visiting.add(node)
    for dep in adj.get(node, []):
        if has_cycle(dep):
            return True
    visiting.remove(node)
    visited.add(node)
    return False

for node in adj:
    if has_cycle(node):
        print(f"[prd_slice_prepare] ERROR: dependency cycle detected starting at {node}", file=sys.stderr)
        raise SystemExit(2)

slice_items = [item for item in items if item.get('slice') == slice_num]
if not slice_items:
    print(f"[prd_slice_prepare] ERROR: no items found for slice {slice_num}", file=sys.stderr)
    raise SystemExit(2)

with open(contract_digest_path, 'r', encoding='utf-8') as f:
    contract_digest = json.load(f)
with open(plan_digest_path, 'r', encoding='utf-8') as f:
    plan_digest = json.load(f)

for label, digest in (('contract', contract_digest), ('plan', plan_digest)):
    if 'sections' not in digest or not isinstance(digest['sections'], list):
        print(f"[prd_slice_prepare] ERROR: {label} digest missing sections", file=sys.stderr)
        raise SystemExit(2)

bullet_re = re.compile(r'^[\-\*\u2022]\s+')
number_re = re.compile(r'^[0-9]+[\).]\s+')

def normalize(value: str) -> str:
    s = value.strip()
    s = bullet_re.sub('', s)
    s = number_re.sub('', s)
    if s.startswith('§'):
        s = s[1:].lstrip()
    s = s.replace('§', '')
    s = s.replace('\\', '')
    s = s.replace('`', '')
    s = s.replace('*', '')
    s = s.replace('_', '')
    s = re.sub(r'\s+', ' ', s)
    s = s.strip()
    # Strip trailing colon/punctuation for matching
    s = re.sub(r'[:;,\.]+$', '', s).strip()
    return s

def section_keys(section, source_prefix):
    keys = []

    def add_key(value: str):
        value = normalize(value)
        if not value:
            return
        keys.append(value)
        if source_prefix:
            keys.append(f"{source_prefix} {value}")
            prefix_norm = normalize(source_prefix)
            if prefix_norm and prefix_norm != source_prefix:
                keys.append(f"{prefix_norm} {value}")

    def add_variants(value: str):
        base = normalize(value)
        if not base:
            return
        variants = {base}
        if base.endswith(':'):
            variants.add(base[:-1].rstrip())
        variants.add(re.sub(r'\s+[—-]\s+MUST implement:?', '', base, flags=re.IGNORECASE).rstrip())
        variants.add(re.sub(r'\s+MUST implement:?', '', base, flags=re.IGNORECASE).rstrip())
        variants.add(re.sub(r'\s*\([^)]*\)\s*(?:[\.:])?\s*$', '', base).rstrip())
        if ' & ' in base:
            variants.add(base.split(' & ', 1)[0].rstrip())
        for variant in list(variants):
            if variant:
                add_key(variant)

    section_id = normalize(str(section.get('id', '')))
    title = normalize(str(section.get('title', '')))
    if section_id:
        add_key(section_id)
    if title:
        add_key(title)
    if section_id and title:
        add_key(f"{section_id} {title}")
        add_variants(f"{section_id} {title}")
    if title:
        add_variants(title)
    text = section.get('text', '') or ''
    for line in text.splitlines():
        raw = line.strip()
        if not raw:
            continue
        if raw.startswith('|') or raw.endswith('|'):
            continue
        if set(raw) <= set('-| '):
            continue
        line_norm = normalize(raw)
        if not line_norm:
            continue
        add_variants(line_norm)
        if ':' in line_norm:
            prefix = line_norm.split(':', 1)[0].rstrip()
            add_variants(prefix)
    return keys

def build_key_map(digest):
    # Use pre-computed key_map from digest if available (optimization)
    if 'key_map' in digest and digest['key_map']:
        key_map = digest['key_map']
        ambiguous = set(digest.get('ambiguous_keys', []))
        return key_map, ambiguous

    # Fallback: build key_map from scratch (for old digests without key_map)
    key_map = {}
    key_sig = {}
    ambiguous = set()
    source_prefix = os.path.basename(digest.get('source_path', '') or '')
    for idx, section in enumerate(digest['sections']):
        sig = (
            normalize(str(section.get('id', ''))),
            normalize(str(section.get('title', '')))
        )
        for key in section_keys(section, source_prefix):
            if not key:
                continue
            if key in ambiguous:
                continue
            if key in key_map and key_map[key] != idx:
                if key_sig.get(key) == sig:
                    continue
                ambiguous.add(key)
                key_map[key] = None
            else:
                key_map[key] = idx
                key_sig[key] = sig

    # Add anchors (AT-###, CSP-###, VR-###) from the digest
    anchors = digest.get('anchors', {})
    for anchor_id, section_indices in anchors.items():
        if not section_indices:
            continue
        # Use first section where anchor appears
        idx = section_indices[0]
        anchor_norm = normalize(anchor_id)
        if anchor_norm and anchor_norm not in key_map:
            key_map[anchor_norm] = idx
        # Also add with source prefix
        if source_prefix:
            prefixed = f"{normalize(source_prefix)} {anchor_norm}"
            if prefixed not in key_map:
                key_map[prefixed] = idx

    return key_map, ambiguous

def resolve_refs(refs, key_map, ambiguous_keys):
    missing = []
    ambiguous = []
    resolved = set()

    def resolve_single(ref):
        norm = normalize(ref)
        if norm in ambiguous_keys:
            return None, 'ambiguous'
        idx = key_map.get(norm)
        if idx is None:
            if norm in key_map:
                return None, 'ambiguous'
            return None, 'missing'
        return idx, None

    for ref in refs:
        if not isinstance(ref, str):
            missing.append(str(ref))
            continue
        parts = [p.strip() for p in re.split(r'\s+/\s+', ref) if p.strip()]
        if len(parts) <= 1:
            idx, err = resolve_single(ref)
            if err == 'missing':
                missing.append(ref)
            elif err == 'ambiguous':
                ambiguous.append(ref)
            elif idx is not None:
                resolved.add(idx)
            continue
        failed = False
        for part in parts:
            idx, err = resolve_single(part)
            if err == 'missing':
                missing.append(ref)
                failed = True
                break
            if err == 'ambiguous':
                ambiguous.append(ref)
                failed = True
                break
            if idx is not None:
                resolved.add(idx)
        if failed:
            continue
    return resolved, missing, ambiguous

contract_key_map, contract_ambiguous = build_key_map(contract_digest)
plan_key_map, plan_ambiguous = build_key_map(plan_digest)

# Load ROADMAP digest if provided (optional, supports slice 0 policy/infra items)
roadmap_digest = None
roadmap_key_map = {}
roadmap_ambiguous = set()
if roadmap_digest_path and Path(roadmap_digest_path).exists():
    try:
        roadmap_digest = json.loads(Path(roadmap_digest_path).read_text())
        if 'sections' in roadmap_digest:
            roadmap_key_map, roadmap_ambiguous = build_key_map(roadmap_digest)
    except (json.JSONDecodeError, IOError) as e:
        print(f"[prd_slice_prepare] WARN: could not load ROADMAP digest: {e}", file=sys.stderr)

contract_refs = []
plan_refs = []
roadmap_refs_by_item = {}
for item in slice_items:
    item_contract_refs = item.get('contract_refs', []) or []
    item_plan_refs = item.get('plan_refs', []) or []

    # Check for ROADMAP refs (items with category policy/infra may reference ROADMAP.md)
    # Also detect P0-*, P1-* style refs which are ROADMAP phase anchors
    roadmap_anchor_re = re.compile(r'^P\d+-[A-Z]$')
    roadmap_refs = []
    other_contract_refs = []
    for ref in item_contract_refs:
        if isinstance(ref, str) and ('ROADMAP' in ref.upper() or roadmap_anchor_re.match(ref)):
            roadmap_refs.append(ref)
        else:
            other_contract_refs.append(ref)

    # Also check plan_refs for ROADMAP anchors
    roadmap_plan_refs = []
    other_plan_refs = []
    for ref in item_plan_refs:
        if isinstance(ref, str) and ('ROADMAP' in ref.upper() or roadmap_anchor_re.match(ref)):
            roadmap_plan_refs.append(ref)
        else:
            other_plan_refs.append(ref)

    if roadmap_refs or roadmap_plan_refs:
        roadmap_refs_by_item[item['id']] = roadmap_refs + roadmap_plan_refs

    contract_refs.extend(other_contract_refs)
    plan_refs.extend(other_plan_refs)

contract_indices, contract_missing, contract_ambig = resolve_refs(contract_refs, contract_key_map, contract_ambiguous)
plan_indices, plan_missing, plan_ambig = resolve_refs(plan_refs, plan_key_map, plan_ambiguous)

# Resolve ROADMAP refs
all_roadmap_refs = []
for refs in roadmap_refs_by_item.values():
    all_roadmap_refs.extend(refs)

roadmap_indices = set()
roadmap_missing = []
roadmap_ambig = []
if all_roadmap_refs and roadmap_digest:
    roadmap_indices, roadmap_missing, roadmap_ambig = resolve_refs(all_roadmap_refs, roadmap_key_map, roadmap_ambiguous)
elif all_roadmap_refs and not roadmap_digest:
    roadmap_missing = all_roadmap_refs
    print(f"[prd_slice_prepare] WARN: ROADMAP refs found but no ROADMAP digest provided: {all_roadmap_refs}", file=sys.stderr)

# Warn on unresolved refs but continue (auditor will mark as BLOCKED)
if contract_missing or contract_ambig:
    if contract_missing:
        print(f"[prd_slice_prepare] WARN: unresolved contract_refs (auditor will BLOCK): {contract_missing}", file=sys.stderr)
    if contract_ambig:
        print(f"[prd_slice_prepare] WARN: ambiguous contract_refs (auditor will BLOCK): {contract_ambig}", file=sys.stderr)

if plan_missing or plan_ambig:
    if plan_missing:
        print(f"[prd_slice_prepare] WARN: unresolved plan_refs (auditor will BLOCK): {plan_missing}", file=sys.stderr)
    if plan_ambig:
        print(f"[prd_slice_prepare] WARN: ambiguous plan_refs (auditor will BLOCK): {plan_ambig}", file=sys.stderr)

if roadmap_missing or roadmap_ambig:
    if roadmap_missing:
        print(f"[prd_slice_prepare] WARN: unresolved ROADMAP refs (auditor will BLOCK): {roadmap_missing}", file=sys.stderr)
    if roadmap_ambig:
        print(f"[prd_slice_prepare] WARN: ambiguous ROADMAP refs (auditor will BLOCK): {roadmap_ambig}", file=sys.stderr)

contract_sections = [section for idx, section in enumerate(contract_digest['sections']) if idx in contract_indices]
plan_sections = [section for idx, section in enumerate(plan_digest['sections']) if idx in plan_indices]
roadmap_sections = []
if roadmap_digest and 'sections' in roadmap_digest:
    roadmap_sections = [section for idx, section in enumerate(roadmap_digest['sections']) if idx in roadmap_indices]

# Filter anchors to only include those referencing included sections
def filter_anchors(anchors, included_indices):
    """Filter anchors dict to only include those mapping to included section indices."""
    filtered = {}
    for anchor_id, section_indices in anchors.items():
        relevant = [idx for idx in section_indices if idx in included_indices]
        if relevant:
            filtered[anchor_id] = relevant
    return filtered

contract_anchors = filter_anchors(contract_digest.get('anchors', {}), contract_indices)
plan_anchors = filter_anchors(plan_digest.get('anchors', {}), plan_indices)
roadmap_anchors = {}
if roadmap_digest:
    roadmap_anchors = filter_anchors(roadmap_digest.get('anchors', {}), roadmap_indices)

os.makedirs(os.path.dirname(out_prd_slice) or '.', exist_ok=True)
with open(out_prd_slice, 'w', encoding='utf-8') as f:
    json.dump({
        'project': prd.get('project'),
        'source': prd.get('source'),
        'rules': prd.get('rules'),
        'items': slice_items
    }, f, ensure_ascii=True, indent=2)
    f.write('\n')

now = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

with open(out_contract_slice, 'w', encoding='utf-8') as f:
    json.dump({
        'source_path': contract_digest.get('source_path'),
        'source_sha256': contract_digest.get('source_sha256'),
        'generated_at': now,
        'filtered_from': contract_digest_path,
        'anchor_count': len(contract_anchors),
        'anchors': contract_anchors,
        'sections': contract_sections
    }, f, ensure_ascii=True, indent=2)
    f.write('\n')

with open(out_plan_slice, 'w', encoding='utf-8') as f:
    json.dump({
        'source_path': plan_digest.get('source_path'),
        'source_sha256': plan_digest.get('source_sha256'),
        'generated_at': now,
        'filtered_from': plan_digest_path,
        'anchor_count': len(plan_anchors),
        'anchors': plan_anchors,
        'sections': plan_sections
    }, f, ensure_ascii=True, indent=2)
    f.write('\n')

# Write ROADMAP slice digest if available
if roadmap_digest and out_roadmap_slice:
    os.makedirs(os.path.dirname(out_roadmap_slice) or '.', exist_ok=True)
    with open(out_roadmap_slice, 'w', encoding='utf-8') as f:
        json.dump({
            'source_path': roadmap_digest.get('source_path'),
            'source_sha256': roadmap_digest.get('source_sha256'),
            'generated_at': now,
            'filtered_from': roadmap_digest_path,
            'anchor_count': len(roadmap_anchors),
            'anchors': roadmap_anchors,
            'sections': roadmap_sections
        }, f, ensure_ascii=True, indent=2)
        f.write('\n')

os.makedirs(os.path.dirname(out_meta) or '.', exist_ok=True)
meta = {
    'audit_scope': 'slice',
    'slice': slice_num,
    'prd_sha256': prd_sha,
    'prd_file': prd_path,
    'prd_slice_file': out_prd_slice,
    'contract_digest': contract_digest_path,
    'plan_digest': plan_digest_path,
    'contract_digest_slice': out_contract_slice,
    'plan_digest_slice': out_plan_slice,
    'output_file': out_audit_file,
    'generated_at': now
}
if roadmap_digest_path and Path(roadmap_digest_path).exists():
    meta['roadmap_digest'] = roadmap_digest_path
    meta['roadmap_digest_slice'] = out_roadmap_slice
with open(out_meta, 'w', encoding='utf-8') as f:
    json.dump(meta, f, ensure_ascii=True, indent=2)
    f.write('\n')
PY
