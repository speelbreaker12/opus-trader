#!/usr/bin/env python3
"""
contract_prd_matrix.py — mechanical Contract <-> PRD mapping emitter

Goal:
- Eliminate O(AT x stories) manual cross-join work for agents.
- Emit a RAW mapping matrix (TSV/JSON) so the auditor only does judgment calls.

Inputs:
- CONTRACT.md (path via --contract)
- prd.json (path via --prd)

Outputs (default paths relative to CWD unless overridden):
- evidence/doc_sync/contract_prd_matrix.tsv
- evidence/doc_sync/contract_prd_matrix.json
- evidence/doc_sync/prd_invalid_at_refs.tsv
- evidence/doc_sync/prd_story_index.tsv

What it does:
1) Extract AT-* IDs from CONTRACT.md and infer Profile (CSP/GOP/FULL/UNKNOWN) by scanning nearby lines.
2) Parse PRD items and collect AT mappings from:
   - enforcing_contract_ats[]
   - contract_refs[] (string search for AT-###)
   - contract_must_evidence[].anchor (string search for AT-###)
3) Emit per-AT rows with:
   - owners, fields_found, passes flags, proof/enforcement heuristics
4) Emit PRD invalid AT refs (AT referenced by PRD but missing in contract).

Heuristics:
- "proof" is present if any of these arrays are non-empty: implementation_tests, verify
- "enforcement point" is present if item has enforcement_point (string, non-empty)

Exit codes:
- 0: success
- 1: error (bad inputs)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any

AT_RE = re.compile(r"\bAT-\d{3,}\b")

# Matches standalone profile declaration lines (bare or in backticks).
# Excludes prose like "Run all `Profile: CSP` acceptance tests".
# Per CONTRACT.md §0.Z.5 line 417: "ATs inherit the most recent Profile: tag above them."
PROFILE_DECL_RE = re.compile(r"^\s*`?Profile\s*:\s*(CSP|GOP|FULL)`?\s*$", re.IGNORECASE)


def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def load_json(p: Path) -> Any:
    return json.loads(read_text(p))


def ensure_parent(p: Path) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)


def build_profile_map(lines: list[str], at_positions: dict[str, int]) -> dict[str, str]:
    """Build AT -> profile mapping using top-down inheritance.

    Per CONTRACT.md §0.Z.5: "ATs inherit the most recent Profile: tag above them."
    If both an explicit per-AT Profile: line and a section-level tag exist,
    the explicit line wins (checked by proximity: within 2 lines of the AT).
    """
    # Step 1: Collect all profile declaration line numbers and their values.
    profile_decls: list[tuple[int, str]] = []
    for idx, line in enumerate(lines):
        m = PROFILE_DECL_RE.match(line)
        if m:
            profile_decls.append((idx, m.group(1).upper()))

    if not profile_decls:
        return {at: "UNKNOWN" for at in at_positions}

    # Step 2: For each AT, find the most recent Profile: declaration at or above it.
    # Then check if there's an explicit per-AT declaration within 2 lines (wins over inheritance).
    result: dict[str, str] = {}
    for at, at_line in at_positions.items():
        # Find inherited profile: most recent declaration at or above the AT line.
        inherited = "UNKNOWN"
        for decl_line, prof in reversed(profile_decls):
            if decl_line <= at_line:
                inherited = prof
                break

        # Check for explicit per-AT profile: a declaration within 2 lines above the AT.
        # This handles cases like:
        #   Profile: GOP
        #   AT-992: ...
        explicit = None
        best_dist = 3  # sentinel > max allowed distance
        for decl_line, prof in profile_decls:
            dist = at_line - decl_line
            if 0 <= dist <= 2 and dist < best_dist:
                explicit = prof
                best_dist = dist

        result[at] = explicit if explicit else inherited

    return result


def stringify(x: Any) -> str:
    if x is None:
        return ""
    return str(x)


def list_str(d: dict[str, Any], key: str) -> list[str]:
    v = d.get(key)
    if isinstance(v, list):
        return [stringify(x) for x in v if stringify(x)]
    return []


def extract_ats_from_strings(strings: list[str]) -> set[str]:
    out: set[str] = set()
    for s in strings:
        out.update(AT_RE.findall(s))
    return out


def extract_story_ats(item: dict[str, Any]) -> tuple[set[str], list[str]]:
    """Extract all AT refs from a PRD item across all three fields.

    Returns (at_set, anchor_strings).
    """
    ats: set[str] = set()
    ats |= {a for a in list_str(item, "enforcing_contract_ats") if AT_RE.fullmatch(a)}
    ats |= extract_ats_from_strings(list_str(item, "contract_refs"))

    anchors: list[str] = []
    cme = item.get("contract_must_evidence")
    if isinstance(cme, list):
        for e in cme:
            if isinstance(e, dict):
                anchors.append(stringify(e.get("anchor")))
    ats |= extract_ats_from_strings(anchors)

    return ats, anchors


def build_at_field_map(item: dict[str, Any], contract_set: set[str]) -> dict[str, set[str]]:
    """Map each AT referenced by item to the PRD field(s) where the reference was found.

    Only includes ATs present in contract_set.
    """
    result: dict[str, set[str]] = {}

    for a in list_str(item, "enforcing_contract_ats"):
        if AT_RE.fullmatch(a) and a in contract_set:
            result.setdefault(a, set()).add("enforcing_contract_ats")

    for a in extract_ats_from_strings(list_str(item, "contract_refs")):
        if a in contract_set:
            result.setdefault(a, set()).add("contract_refs")

    cme = item.get("contract_must_evidence")
    anchors: list[str] = []
    if isinstance(cme, list):
        anchors = [stringify(e.get("anchor")) for e in cme if isinstance(e, dict)]
    for a in extract_ats_from_strings(anchors):
        if a in contract_set:
            result.setdefault(a, set()).add("contract_must_evidence.anchor")

    return result


def story_passes(item: dict[str, Any]) -> bool | None:
    v = item.get("passes")
    if isinstance(v, bool):
        return v
    return None


def story_proof_present(item: dict[str, Any]) -> bool:
    for k in ("implementation_tests", "verify"):
        v = item.get(k)
        if isinstance(v, list) and len(v) > 0:
            return True
    return False


def story_enforcement_present(item: dict[str, Any]) -> bool:
    v = item.get("enforcement_point")
    if isinstance(v, str) and v.strip():
        return True
    return False


def scope_touch(item: dict[str, Any]) -> list[str]:
    sc = item.get("scope")
    if isinstance(sc, dict):
        touch = sc.get("touch")
        if isinstance(touch, list):
            return [stringify(x) for x in touch if stringify(x)]
    return []


@dataclass
class MappingRow:
    contract_item: str
    kind: str
    profile: str
    owners: str
    owners_count: int
    mapping_details: str
    suggested_status: str
    covered_candidates: str
    any_enforcement_point: bool
    any_proof: bool
    notes: str


def main() -> int:
    ap = argparse.ArgumentParser(description="Contract <-> PRD mechanical mapping matrix")
    ap.add_argument("--contract", default="specs/CONTRACT.md")
    ap.add_argument("--prd", default="plans/prd.json")
    ap.add_argument("--out-tsv", default="evidence/doc_sync/contract_prd_matrix.tsv")
    ap.add_argument("--out-json", default="evidence/doc_sync/contract_prd_matrix.json")
    ap.add_argument("--out-invalid", default="evidence/doc_sync/prd_invalid_at_refs.tsv")
    ap.add_argument("--out-story-index", default="evidence/doc_sync/prd_story_index.tsv")
    args = ap.parse_args()

    root = Path(os.getcwd())
    contract_path = (root / args.contract).resolve()
    prd_path = (root / args.prd).resolve()

    if not contract_path.exists():
        print(f"ERROR: contract not found: {contract_path}", file=sys.stderr)
        return 1
    if not prd_path.exists():
        print(f"ERROR: prd not found: {prd_path}", file=sys.stderr)
        return 1

    # ── Step 1: Extract ATs from CONTRACT.md ──
    contract_text = read_text(contract_path)
    lines = contract_text.splitlines()

    # Collect AT positions. Prefer the "definition line" (AT at start of line)
    # over first-mention (which may be in a summary/reference far from the
    # Profile: declaration). Falls back to first occurrence if no def-like line.
    at_first: dict[str, int] = {}
    at_def: dict[str, int] = {}
    for idx, line in enumerate(lines):
        for at in AT_RE.findall(line):
            at_first.setdefault(at, idx)
            stripped = re.sub(r"^[\-\*\d.\s>]+", "", line.strip())
            if stripped.startswith(at):
                at_def.setdefault(at, idx)
    at_positions: dict[str, int] = {}
    for at in at_first:
        at_positions[at] = at_def.get(at, at_first[at])

    contract_ats = sorted(at_positions.keys())
    contract_set = set(contract_ats)

    at_profile = build_profile_map(lines, at_positions)

    # ── Step 2: Parse PRD items ──
    prd = load_json(prd_path)
    items = prd.get("items")
    if not isinstance(items, list):
        print("ERROR: prd.json must have top-level 'items' list", file=sys.stderr)
        return 1

    story_by_id: dict[str, dict[str, Any]] = {}
    prd_ats_all: set[str] = set()
    story_rows: list[list[str]] = []

    for it in items:
        if not isinstance(it, dict):
            continue
        sid = stringify(it.get("id"))
        if not sid:
            continue
        story_by_id[sid] = it

        ats, anchors = extract_story_ats(it)
        prd_ats_all |= ats

        passes = story_passes(it)
        proof = story_proof_present(it)
        enf = story_enforcement_present(it)
        touches = scope_touch(it)

        story_rows.append([
            sid,
            stringify(passes) if passes is not None else "",
            "1" if proof else "0",
            "1" if enf else "0",
            ",".join(sorted(ats)),
            "|".join(list_str(it, "contract_refs")),
            "|".join([a for a in anchors if a]),
            ",".join(touches),
        ])

    # ── Step 3: Build AT -> story mapping ──
    invalid_at_set = {a for a in prd_ats_all if a not in contract_set}
    invalid_ats = sorted(invalid_at_set)

    at_to_story_fields: dict[str, dict[str, set[str]]] = {at: {} for at in contract_ats}

    for sid, it in story_by_id.items():
        field_map = build_at_field_map(it, contract_set)
        for at, fields in field_map.items():
            at_to_story_fields[at].setdefault(sid, set()).update(fields)

    # ── Step 3b: Validate primary_owner_for consistency ──
    for sid, it in story_by_id.items():
        pof = it.get("primary_owner_for")
        if not isinstance(pof, list):
            continue
        story_ats, _ = extract_story_ats(it)
        for at in pof:
            if at not in story_ats:
                print(
                    f"[matrix] WARNING: {sid} declares primary_owner_for {at} "
                    f"but does not reference it in any AT field",
                    file=sys.stderr,
                )

    # ── Step 4: Emit matrix rows ──
    out_rows: list[MappingRow] = []
    for at in contract_ats:
        mapping = at_to_story_fields.get(at, {})
        owners = sorted(mapping.keys())
        owners_count = len(owners)

        details_parts: list[str] = []
        any_proof = False
        any_enf = False
        covered_candidates: list[str] = []

        for sid in owners:
            fields = sorted(mapping[sid])
            it = story_by_id[sid]
            passes = story_passes(it)
            proof = story_proof_present(it)
            enf = story_enforcement_present(it)
            any_proof = any_proof or proof
            any_enf = any_enf or enf
            if passes is True and proof and enf:
                covered_candidates.append(sid)
            details_parts.append(f"{sid}:{'|'.join(fields)}")

        if owners_count == 0:
            status = "MISSING"
        elif owners_count > 1:
            # Check if primary_owner_for resolves ambiguity.
            primary = [
                sid for sid in owners
                if at in story_by_id[sid].get("primary_owner_for", [])
            ]
            if len(primary) == 1:
                # Resolved: treat as single-owner using the primary.
                sid = primary[0]
                it = story_by_id[sid]
                passes = story_passes(it)
                proof = story_proof_present(it)
                enf = story_enforcement_present(it)
                if passes is True and proof and enf:
                    status = "COVERED"
                else:
                    status = "CLAIMED"
            elif len(primary) > 1:
                status = "AMBIGUOUS"
            else:
                status = "AMBIGUOUS"
        else:
            sid = owners[0]
            it = story_by_id[sid]
            passes = story_passes(it)
            proof = story_proof_present(it)
            enf = story_enforcement_present(it)
            if passes is True and proof and enf:
                status = "COVERED"
            else:
                status = "CLAIMED"

        notes_parts: list[str] = []
        # Warn if multiple stories claim primary_owner_for the same AT.
        if owners_count > 1:
            primary = [
                sid for sid in owners
                if at in story_by_id[sid].get("primary_owner_for", [])
            ]
            if len(primary) > 1:
                notes_parts.append(
                    f"Multiple primary_owner_for claims: {','.join(primary)}"
                )
        if owners_count > 0 and not any_proof:
            notes_parts.append("No implementation_tests/verify arrays found in owning stories.")
        if owners_count > 0 and not any_enf:
            notes_parts.append("No enforcement_point field found; scope.touch may be used as proxy.")
        notes = " ".join(notes_parts)

        out_rows.append(MappingRow(
            contract_item=at,
            kind="AT",
            profile=at_profile.get(at, "UNKNOWN"),
            owners=",".join(owners),
            owners_count=owners_count,
            mapping_details=";".join(details_parts),
            suggested_status=status,
            covered_candidates=",".join(covered_candidates),
            any_enforcement_point=any_enf,
            any_proof=any_proof,
            notes=notes,
        ))

    # ── Step 5: Write outputs ──

    # 5a) Main matrix TSV
    out_tsv = (root / args.out_tsv).resolve()
    ensure_parent(out_tsv)
    header = [
        "contract_item", "kind", "profile", "owners", "owners_count",
        "mapping_details", "suggested_status", "covered_candidates",
        "any_enforcement_point", "any_proof", "notes",
    ]
    tsv_lines = ["\t".join(header)]
    for r in out_rows:
        tsv_lines.append("\t".join([
            r.contract_item,
            r.kind,
            r.profile,
            r.owners,
            str(r.owners_count),
            r.mapping_details,
            r.suggested_status,
            r.covered_candidates,
            "1" if r.any_enforcement_point else "0",
            "1" if r.any_proof else "0",
            r.notes.replace("\t", " ").replace("\n", " "),
        ]))
    out_tsv.write_text("\n".join(tsv_lines) + "\n", encoding="utf-8")

    # 5b) Main matrix JSON
    out_json = (root / args.out_json).resolve()
    ensure_parent(out_json)
    out_json.write_text(
        json.dumps([asdict(r) for r in out_rows], indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    # 5c) Invalid AT refs TSV (includes passes state for BLOCKER detection)
    out_invalid = (root / args.out_invalid).resolve()
    ensure_parent(out_invalid)
    inv_lines = ["invalid_at\tstory_ids\tpasses\tfields_found"]

    inv_map: dict[str, dict[str, set[str]]] = {}
    for sid, it in story_by_id.items():
        for a in list_str(it, "enforcing_contract_ats"):
            if AT_RE.fullmatch(a) and a in invalid_at_set:
                inv_map.setdefault(a, {}).setdefault(sid, set()).add("enforcing_contract_ats")
        for a in extract_ats_from_strings(list_str(it, "contract_refs")):
            if a in invalid_at_set:
                inv_map.setdefault(a, {}).setdefault(sid, set()).add("contract_refs")
        cme = it.get("contract_must_evidence")
        anchors: list[str] = []
        if isinstance(cme, list):
            anchors = [stringify(e.get("anchor")) for e in cme if isinstance(e, dict)]
        for a in extract_ats_from_strings(anchors):
            if a in invalid_at_set:
                inv_map.setdefault(a, {}).setdefault(sid, set()).add("contract_must_evidence.anchor")

    blocker_count = 0
    for a in invalid_ats:
        stories = sorted(inv_map.get(a, {}).keys())
        passes_vals: list[str] = []
        fields: list[str] = []
        for sid in stories:
            p = story_passes(story_by_id[sid])
            if p is True:
                status = "true"
                blocker_count += 1
            elif p is False:
                status = "false"
            else:
                status = "unknown"
            passes_vals.append(f"{sid}={status}")
            fields.append(f"{sid}:{'|'.join(sorted(inv_map[a][sid]))}")
        inv_lines.append(f"{a}\t{','.join(stories)}\t{','.join(passes_vals)}\t{';'.join(fields)}")
    out_invalid.write_text("\n".join(inv_lines) + "\n", encoding="utf-8")

    # 5d) Story index TSV
    out_story = (root / args.out_story_index).resolve()
    ensure_parent(out_story)
    story_header = [
        "story_id", "passes", "has_proof_arrays", "has_enforcement_point",
        "ats_any_field", "contract_refs_raw", "anchors_raw", "scope_touch",
    ]
    story_lines = ["\t".join(story_header)]
    for row in sorted(story_rows, key=lambda r: r[0]):
        story_lines.append("\t".join([c.replace("\t", " ").replace("\n", " ") for c in row]))
    out_story.write_text("\n".join(story_lines) + "\n", encoding="utf-8")

    # ── Summary ──
    status_counts: dict[str, int] = {}
    for r in out_rows:
        status_counts[r.suggested_status] = status_counts.get(r.suggested_status, 0) + 1

    print("[matrix] Wrote:")
    print(f"  - {out_tsv}")
    print(f"  - {out_json}")
    print(f"  - {out_invalid}")
    print(f"  - {out_story}")
    print(f"[matrix] Contract ATs: {len(contract_ats)} | PRD stories: {len(story_by_id)} | PRD AT refs (any field): {len(prd_ats_all)} | invalid refs: {len(invalid_ats)}")
    print(f"[matrix] Status breakdown: {' | '.join(f'{k}={v}' for k, v in sorted(status_counts.items()))}")
    if blocker_count > 0:
        print(f"[matrix] WARNING: {blocker_count} invalid AT ref(s) in stories with passes=true (BLOCKER)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
