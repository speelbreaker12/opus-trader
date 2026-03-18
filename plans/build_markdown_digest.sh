#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SOURCE_FILE="${SOURCE_FILE:-${1:-}}"
OUTPUT_FILE="${OUTPUT_FILE:-${2:-}}"
# DIGEST_MODE: full (default) includes section text, slim includes only metadata
DIGEST_MODE="${DIGEST_MODE:-full}"

if [[ -z "$SOURCE_FILE" || ! -f "$SOURCE_FILE" ]]; then
  echo "[digest] ERROR: source markdown file missing: $SOURCE_FILE" >&2
  exit 2
fi
if [[ -z "$OUTPUT_FILE" ]]; then
  echo "[digest] ERROR: output file not set" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "[digest] ERROR: python3 required" >&2
  exit 2
fi

export DIGEST_MODE

python3 - "$SOURCE_FILE" "$OUTPUT_FILE" <<'PY'
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

source_path = sys.argv[1]
out_path = sys.argv[2]
digest_mode = os.environ.get('DIGEST_MODE', 'full')  # 'full' or 'slim'

with open(source_path, 'rb') as f:
    data = f.read()
source_sha = hashlib.sha256(data).hexdigest()

if os.path.exists(out_path):
    try:
        with open(out_path, 'r', encoding='utf-8') as f:
            existing = json.load(f)
        # Cache valid if: same source SHA, same mode, and sections exist
        if (existing.get('source_sha256') == source_sha and
            existing.get('digest_mode', 'full') == digest_mode and
            isinstance(existing.get('sections'), list) and
            len(existing.get('sections')) > 0):
            raise SystemExit(0)
    except json.JSONDecodeError:
        pass

text = data.decode('utf-8', errors='replace')

heading_re = re.compile(r'^(#{1,6})\s+(.*)$')
pseudo_heading_re = re.compile(r'^(?:\d+\)|\d+\.|[A-Z]\)|Slice\s+\d+\s+—|S\d+\.\d+\s+—|Phase\s+\d+\s+—|PHASE\s+\d+\s+—|Global\s+Non)', re.IGNORECASE)
# Bold pseudo-headings like **OrderSize struct (MUST implement):** or **Dispatcher Rules:**
bold_heading_re = re.compile(r'^\*\*([^*]+(?:\([^)]+\))?)\s*(?:—[^:]+)?:\*\*\s*$')

sections = []
current = None

def strip_emphasis(value: str) -> str:
    s = value.strip()
    for marker in ("**", "__"):
        if s.startswith(marker) and s.endswith(marker) and len(s) >= len(marker) * 2:
            s = s[len(marker):-len(marker)].strip()
    return s

def parse_heading(raw: str):
    title = strip_emphasis(raw)
    title = title.strip()
    if title.startswith("§"):
        title = title[1:].lstrip()
    m = re.match(r'^([0-9]+(?:\.[0-9A-Z]+)*)\s+(.*)$', title)
    if m:
        return m.group(1), m.group(2).strip()
    return "", title

def make_section(section_id, title, level):
    """Create a section dict, with or without text field based on digest_mode."""
    if digest_mode == 'slim':
        return {
            "id": section_id,
            "title": title,
            "level": level
        }
    else:
        return {
            "id": section_id,
            "title": title,
            "level": level,
            "text": ""
        }

def finalize_section(section):
    """Finalize a section before appending to list."""
    if section is None:
        return
    if digest_mode != 'slim' and "text" in section:
        section["text"] = section["text"].rstrip()

lines = text.splitlines()
for line in lines:
    match = heading_re.match(line)
    if match:
        level = len(match.group(1))
        raw_title = match.group(2).strip()
        section_id, title = parse_heading(raw_title)
        if current is not None:
            finalize_section(current)
            sections.append(current)
        current = make_section(section_id, title, level)
    elif pseudo_heading_re.match(line) and '|' not in line:
        raw_title = strip_emphasis(line.strip())
        if current is not None:
            finalize_section(current)
            sections.append(current)
        current = make_section("", raw_title, 2)
    elif bold_heading_re.match(line):
        # Bold pseudo-heading like **OrderSize struct (MUST implement):**
        bold_match = bold_heading_re.match(line)
        raw_title = bold_match.group(1).strip()
        if current is not None:
            finalize_section(current)
            sections.append(current)
        current = make_section("", raw_title, 3)
    else:
        if current is not None and digest_mode != 'slim':
            current["text"] += line + "\n"

if current is not None:
    finalize_section(current)
    sections.append(current)

# Extract anchors (AT-###, CSP-###, P0-X, etc.) from the full text
# Maps anchor ID -> list of section indices where it appears
anchor_re = re.compile(r'\b(AT-\d{3,4}|CSP-\d{3}|VR-\d{3}[a-z]?)\b')
# Also extract P0-A through P0-Z style anchors (ROADMAP phase items)
phase_anchor_re = re.compile(r'\b(P\d+-[A-Z])\b')
anchors = {}

# Scan full text to find anchors and map to sections
current_section_idx = -1
for line in lines:
    # Check if this line starts a new section
    if heading_re.match(line) or (pseudo_heading_re.match(line) and '|' not in line) or bold_heading_re.match(line):
        current_section_idx += 1

    # Find all anchors in this line
    for match in anchor_re.finditer(line):
        anchor_id = match.group(1)
        if anchor_id not in anchors:
            anchors[anchor_id] = []
        if current_section_idx >= 0 and current_section_idx not in anchors[anchor_id]:
            anchors[anchor_id].append(current_section_idx)

    # Find phase anchors (P0-A, P1-B, etc.) - common in ROADMAP
    for match in phase_anchor_re.finditer(line):
        anchor_id = match.group(1)
        if anchor_id not in anchors:
            anchors[anchor_id] = []
        if current_section_idx >= 0 and current_section_idx not in anchors[anchor_id]:
            anchors[anchor_id].append(current_section_idx)

# Pre-compute key_map for fast ref resolution in slice_prepare
# This avoids rebuilding the expensive regex-based key_map for each slice
bullet_re = re.compile(r'^[\-\*\u2022]\s+')
number_re = re.compile(r'^[0-9]+[\).]\s+')

def normalize(value: str) -> str:
    s = value.strip()
    s = bullet_re.sub('', s)
    s = number_re.sub('', s)
    if s.startswith('§'):
        s = s[1:].lstrip()
    s = s.replace('§', '').replace('\\', '').replace('`', '').replace('*', '').replace('_', '')
    s = re.sub(r'\s+', ' ', s).strip()
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
        if not raw or raw.startswith('|') or raw.endswith('|') or set(raw) <= set('-| '):
            continue
        line_norm = normalize(raw)
        if not line_norm:
            continue
        add_variants(line_norm)
        if ':' in line_norm:
            prefix = line_norm.split(':', 1)[0].rstrip()
            add_variants(prefix)
    return keys

# Build key_map: maps normalized ref string -> section index
source_prefix = os.path.basename(source_path)
key_map = {}
key_sig = {}
ambiguous = set()

for idx, section in enumerate(sections):
    sig = (normalize(str(section.get('id', ''))), normalize(str(section.get('title', ''))))
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

# Add anchors to key_map
for anchor_id, section_indices in anchors.items():
    if not section_indices:
        continue
    idx = section_indices[0]
    anchor_norm = normalize(anchor_id)
    if anchor_norm and anchor_norm not in key_map:
        key_map[anchor_norm] = idx
    if source_prefix:
        prefixed = f"{normalize(source_prefix)} {anchor_norm}"
        if prefixed not in key_map:
            key_map[prefixed] = idx

# Filter out ambiguous keys (None values)
key_map_clean = {k: v for k, v in key_map.items() if v is not None}

payload = {
    "source_path": source_path,
    "source_sha256": source_sha,
    "digest_mode": digest_mode,
    "generated_at": datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    "section_count": len(sections),
    "anchor_count": len(anchors),
    "anchors": anchors,
    "key_map": key_map_clean,
    "ambiguous_keys": list(ambiguous),
    "sections": sections
}

os.makedirs(os.path.dirname(out_path) or '.', exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(payload, f, ensure_ascii=True, indent=2)
    f.write("\n")
PY
