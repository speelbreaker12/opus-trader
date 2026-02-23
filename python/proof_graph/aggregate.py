#!/usr/bin/env python3
"""Fail-closed reviewer merge for proof graph V2.

Merges multiple reviewer proof graphs into one, selecting the strictest
verdict for each AT. Tracks disagreements in meta.conflicts and reviewer
metadata in meta.review_sources.

Usage:
  python3 python/proof_graph/aggregate.py \
      --base artifacts/story/S1-007/proof_graph.json \
      --reviews artifacts/story/S1-007/codex/proof_graph.json \
               artifacts/story/S1-007/opus/proof_graph.json \
      --output artifacts/story/S1-007/proof_graph_merged.json
"""
from __future__ import annotations

import argparse
import json
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any


# Severity strictness ordering (for deterministic tie-breaking)
SEVERITY_STRICTNESS: dict[str, int] = {
    "INFO": 0,
    "HARDENING": 1,
    "BLOCKING": 2,
}

# Full verdict strictness ordering (0=least strict, higher=more strict)
VERDICT_STRICTNESS: dict[str, int] = {
    "PROVEN_INTEGRATED": 0,
    "PROVEN_UNIT": 1,
    "WEAK_PROOF": 2,
    "CLAIMED_NOT_PROVEN": 3,
    "UNTESTED_ENFORCEMENT": 4,
    "WRONG_IMPL_UNBLOCKED": 5,
    "INVALID_REF": 6,
    "FAIL_OPEN_RISK": 7,
    "MISSING": 8,
}

# Unknown verdicts get rank 9 (fail-closed: stricter than MISSING)
UNKNOWN_VERDICT_RANK = 9

# DEFERRED means "no opinion" — excluded from strictness comparison
DEFERRED_VERDICT = "DEFERRED"


def _verdict_rank(verdict: str) -> int:
    """Return strictness rank for a verdict. Unknown = 9 (fail-closed)."""
    return VERDICT_STRICTNESS.get(verdict, UNKNOWN_VERDICT_RANK)


def _strictest_verdict(verdicts: list[str]) -> str:
    """Select the strictest verdict from a list, excluding DEFERRED.

    If all verdicts are DEFERRED, returns DEFERRED.
    """
    non_deferred = [v for v in verdicts if v != DEFERRED_VERDICT]
    if not non_deferred:
        return DEFERRED_VERDICT
    return max(non_deferred, key=_verdict_rank)


def _compute_trading_halt(graph: dict[str, Any]) -> bool:
    """Recompute trading halt condition from graph data.

    Delegates to rules.should_trigger_trading_halt (single source of truth).
    """
    # Lazy import: works via Python 3 namespace packages (python/ has no __init__.py).
    # Requires repo root on sys.path — set by main() for CLI, by pytest/conftest for tests.
    from python.proof_graph.rules import should_trigger_trading_halt

    story_meta = graph.get("story_meta", {})
    return should_trigger_trading_halt(
        safety_critical=story_meta.get("safety_critical", False),
        loss_level=story_meta.get("loss_mode", {}).get("level", ""),
        verdicts=[
            at.get("at_verdict", {}).get("verdict", "")
            for at in graph.get("ats", [])
        ],
    )


def aggregate(
    base: dict[str, Any],
    reviews: list[dict[str, Any]],
    review_labels: list[str] | None = None,
) -> dict[str, Any]:
    """Merge base + reviewer graphs, selecting strictest verdict per AT.

    Args:
        base: Base proof graph dict (typically from init.py or agent fill)
        reviews: List of reviewer proof graph dicts
        review_labels: Optional labels for each reviewer (e.g. ["codex", "opus"])

    Returns:
        Merged proof graph dict
    """
    if review_labels is None:
        review_labels = [f"reviewer_{i}" for i in range(len(reviews))]
    elif len(review_labels) != len(reviews):
        raise ValueError(
            f"review_labels count ({len(review_labels)}) must match "
            f"reviews count ({len(reviews)})"
        )

    merged = deepcopy(base)

    # Index base ATs by at_id
    base_ats: dict[str, dict[str, Any]] = {}
    for at in merged.get("ats", []):
        base_ats[at["at_id"]] = at

    # Collect all reviewer ATs indexed by at_id
    reviewer_ats: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for label, review in zip(review_labels, reviews):
        for at in review.get("ats", []):
            at_id = at["at_id"]
            if at_id not in reviewer_ats:
                reviewer_ats[at_id] = []
            reviewer_ats[at_id].append((label, at))

    conflicts: dict[str, Any] = {}

    # Process each AT
    all_at_ids = set(base_ats.keys()) | set(reviewer_ats.keys())
    for at_id in sorted(all_at_ids):
        if at_id not in reviewer_ats:
            # AT in base but not any reviewer → keep base verdict
            continue

        base_at = base_ats.get(at_id)
        reviewer_entries = reviewer_ats[at_id]

        # Collect verdicts from reviewers
        reviewer_verdicts: list[tuple[str, str]] = []
        for label, rat in reviewer_entries:
            v = rat.get("at_verdict", {}).get("verdict", "MISSING")
            reviewer_verdicts.append((label, v))

        verdict_values = [v for _, v in reviewer_verdicts]
        strictest = _strictest_verdict(verdict_values)

        if base_at is None:
            # AT in reviewer but not base → add to merged.
            # Deterministic tie-break: among reviewers with the strictest
            # verdict, pick the one with the strictest severity, then
            # lowest label (alphabetical) for full determinism.
            best_entry = None
            best_sev = -1
            best_label = ""
            for label, rat in reviewer_entries:
                rv = rat.get("at_verdict", {}).get("verdict", "MISSING")
                if rv == strictest or (strictest == DEFERRED_VERDICT):
                    rsev = SEVERITY_STRICTNESS.get(
                        rat.get("at_verdict", {}).get("severity", ""), 0
                    )
                    if best_entry is None or rsev > best_sev or \
                            (rsev == best_sev and label < best_label):
                        best_entry = rat
                        best_sev = rsev
                        best_label = label
            if best_entry is not None:
                merged_at = deepcopy(best_entry)
                merged["ats"].append(merged_at)
                base_ats[at_id] = merged_at
        else:
            # Check for all-DEFERRED
            if strictest == DEFERRED_VERDICT:
                # Keep base verdict, record conflict
                conflicts[at_id] = {
                    "type": "all_deferred",
                    "reviewers": {lbl: v for lbl, v in reviewer_verdicts},
                    "kept_verdict": base_at.get("at_verdict", {}).get("verdict", ""),
                }
                continue

            # Update verdict to strictest
            base_at["at_verdict"]["verdict"] = strictest

            # Always compute the strictest severity across all reviewers
            # (independent of whether the verdict changed) for fail-closed
            # correctness. Deterministic tie-break: highest severity rank,
            # then lowest label.
            best_sev_str = base_at.get("at_verdict", {}).get("severity", "")
            best_sev_rank = SEVERITY_STRICTNESS.get(best_sev_str, 0)
            for _lbl, rat in reviewer_entries:
                rsev = rat.get("at_verdict", {}).get("severity", "")
                rsev_rank = SEVERITY_STRICTNESS.get(rsev, 0)
                if rsev_rank > best_sev_rank:
                    best_sev_rank = rsev_rank
                    best_sev_str = rsev
            if best_sev_str:
                base_at["at_verdict"]["severity"] = best_sev_str

            # Record disagreements
            unique_verdicts = set(verdict_values) - {DEFERRED_VERDICT}
            if len(unique_verdicts) > 1:
                conflicts[at_id] = {
                    "type": "disagreement",
                    "reviewers": {lbl: v for lbl, v in reviewer_verdicts},
                    "selected": strictest,
                }

    # Recompute blocking_count and hardening_count (by severity, matching R-009/R-010)
    blocking_count = 0
    hardening_count = 0
    for at in merged.get("ats", []):
        sev = at.get("at_verdict", {}).get("severity", "")
        if sev == "BLOCKING":
            blocking_count += 1
        elif sev == "HARDENING":
            hardening_count += 1

    merged["story_verdict"]["blocking_count"] = blocking_count
    merged["story_verdict"]["hardening_count"] = hardening_count

    # Recompute trading halt from merged data
    merged["story_verdict"]["trading_halt_trigger"] = _compute_trading_halt(merged)

    # Populate meta
    if "meta" not in merged:
        merged["meta"] = {}
    merged["meta"]["review_sources"] = review_labels
    merged["meta"]["review_count"] = len(review_labels)
    # Clear stale conflicts from prior aggregation, then set new ones
    merged["meta"].pop("conflicts", None)
    if conflicts:
        merged["meta"]["conflicts"] = conflicts

    return merged


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Merge reviewer proof graphs (fail-closed, strictest-wins)."
    )
    parser.add_argument(
        "--base", required=True,
        help="Path to base proof_graph.json",
    )
    parser.add_argument(
        "--reviews", nargs="+", required=True,
        help="Paths to reviewer proof_graph.json files",
    )
    parser.add_argument(
        "--labels", nargs="+", default=None,
        help="Labels for each reviewer (e.g. codex opus)",
    )
    parser.add_argument(
        "--output", required=True,
        help="Path for merged output",
    )
    args = parser.parse_args(argv)

    base_path = Path(args.base)
    if not base_path.is_file():
        print(f"ERROR: base not found: {base_path}", file=sys.stderr)
        return 1

    base = json.loads(base_path.read_text(encoding="utf-8"))
    reviews = []
    for rp in args.reviews:
        p = Path(rp)
        if not p.is_file():
            print(f"ERROR: review not found: {p}", file=sys.stderr)
            return 1
        reviews.append(json.loads(p.read_text(encoding="utf-8")))

    labels = args.labels
    if labels and len(labels) != len(reviews):
        print("ERROR: --labels count must match --reviews count", file=sys.stderr)
        return 1

    merged = aggregate(base, reviews, review_labels=labels)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")
    print(f"Merged: {out_path}")
    return 0


if __name__ == "__main__":
    # Allow running as `python3 python/proof_graph/aggregate.py` from repo root:
    # ensure the repo root is on sys.path so `from python.proof_graph.rules import ...`
    # resolves correctly, and remove the script's own directory to avoid shadowing.
    _this = Path(__file__).resolve()
    _pkg_parent = str(_this.parent.parent.parent)
    _script_dir = str(_this.parent)
    if _script_dir in sys.path:
        sys.path.remove(_script_dir)
    if _pkg_parent not in sys.path:
        sys.path.insert(0, _pkg_parent)
    sys.exit(main())
