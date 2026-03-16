#!/usr/bin/env python3
"""Aggregate statistics from verify.sh runs.

Scans artifacts/verify/*/ directories and produces:
  1. Overall pass/fail rate by mode (quick vs full)
  2. Per-gate failure frequency (ranked)
  3. Per-gate timing stats (avg, p50, p95, max)
  4. Timeout vs logic failure breakdown
  5. Recent trend comparison (last N days vs prior N days)

Usage:
  python tools/verify_stats.py                    # all runs, table output
  python tools/verify_stats.py --since 7d         # last 7 days
  python tools/verify_stats.py --mode quick        # only quick runs
  python tools/verify_stats.py --json              # JSON output
  python tools/verify_stats.py --top 10            # top 10 failing gates
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional


@dataclass
class GateResult:
    gate: str
    rc: int
    elapsed_s: Optional[float]
    run_id: str
    mode: str
    timestamp: datetime


@dataclass
class RunMeta:
    run_id: str
    mode: str
    status: str  # "ok" or "failed"
    failed_gate: str
    started_at: Optional[datetime]
    ended_at: Optional[datetime]
    head_sha: str
    run_dir: Path


@dataclass
class GateStats:
    gate: str
    total: int = 0
    passes: int = 0
    failures: int = 0
    timeouts: int = 0
    logic_failures: int = 0
    timings: list[float] = field(default_factory=list)

    @property
    def fail_rate(self) -> float:
        return self.failures / self.total if self.total > 0 else 0.0

    @property
    def timeout_rate(self) -> float:
        return self.timeouts / self.total if self.total > 0 else 0.0

    def timing_percentile(self, p: float) -> Optional[float]:
        if not self.timings:
            return None
        s = sorted(self.timings)
        idx = int(len(s) * p / 100)
        idx = min(idx, len(s) - 1)
        return s[idx]

    @property
    def timing_avg(self) -> Optional[float]:
        return sum(self.timings) / len(self.timings) if self.timings else None

    @property
    def timing_max(self) -> Optional[float]:
        return max(self.timings) if self.timings else None


def parse_iso(s: str) -> Optional[datetime]:
    if not s:
        return None
    try:
        s = s.replace("Z", "+00:00")
        return datetime.fromisoformat(s)
    except (ValueError, TypeError):
        return None


def parse_run_id_timestamp(run_id: str) -> Optional[datetime]:
    """Parse YYYYMMDD_HHMMSS from run_id."""
    m = re.match(r"^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})$", run_id)
    if not m:
        return None
    try:
        return datetime(
            int(m.group(1)), int(m.group(2)), int(m.group(3)),
            int(m.group(4)), int(m.group(5)), int(m.group(6)),
            tzinfo=timezone.utc,
        )
    except ValueError:
        return None


def load_run(run_dir: Path) -> Optional[RunMeta]:
    meta_path = run_dir / "verify.meta.json"
    if not meta_path.exists():
        return None
    try:
        with open(meta_path) as f:
            d = json.load(f)
    except (json.JSONDecodeError, OSError):
        return None

    started = parse_iso(d.get("started_at", ""))
    if started is None:
        started = parse_run_id_timestamp(d.get("run_id", ""))

    return RunMeta(
        run_id=d.get("run_id", run_dir.name),
        mode=d.get("mode", "unknown"),
        status=d.get("status", "unknown"),
        failed_gate=d.get("failed_gate", ""),
        started_at=started,
        ended_at=parse_iso(d.get("ended_at", "")),
        head_sha=d.get("head_sha", ""),
        run_dir=run_dir,
    )


def load_gate_results(run: RunMeta) -> list[GateResult]:
    results = []
    ts = run.started_at or datetime.now(tz=timezone.utc)

    for rc_file in run.run_dir.glob("*.rc"):
        gate = rc_file.stem
        try:
            rc = int(rc_file.read_text().strip())
        except (ValueError, OSError):
            continue

        time_file = run.run_dir / f"{gate}.time"
        elapsed = None
        if time_file.exists():
            try:
                elapsed = float(time_file.read_text().strip())
            except (ValueError, OSError):
                pass

        results.append(GateResult(
            gate=gate, rc=rc, elapsed_s=elapsed,
            run_id=run.run_id, mode=run.mode, timestamp=ts,
        ))
    return results


def compute_gate_stats(results: list[GateResult]) -> dict[str, GateStats]:
    by_gate: dict[str, GateStats] = {}
    for r in results:
        if r.gate not in by_gate:
            by_gate[r.gate] = GateStats(gate=r.gate)
        g = by_gate[r.gate]
        g.total += 1
        if r.rc == 0:
            g.passes += 1
        else:
            g.failures += 1
            if r.rc in (124, 137):
                g.timeouts += 1
            else:
                g.logic_failures += 1
        if r.elapsed_s is not None:
            g.timings.append(r.elapsed_s)
    return by_gate


def parse_duration(s: str) -> Optional[timedelta]:
    m = re.match(r"^(\d+)([dhm])$", s)
    if not m:
        return None
    val = int(m.group(1))
    unit = m.group(2)
    if unit == "d":
        return timedelta(days=val)
    elif unit == "h":
        return timedelta(hours=val)
    elif unit == "m":
        return timedelta(minutes=val)
    return None


def fmt_pct(val: float) -> str:
    return f"{val * 100:.1f}%"


def fmt_time(val: Optional[float]) -> str:
    if val is None:
        return "-"
    if val < 1:
        return f"{val:.2f}s"
    return f"{val:.1f}s"


def normalize_gate_name(name: str) -> str:
    """Collapse hashed status fixture names into a single canonical name.

    Status fixture gates changed naming schemes over time:
      status_fixture_market_data_stale
      status_fixture_a228fdf950bbf08052fac6b1_session_termination
    Normalize both to: status_fixture:<fixture_stem>
    """
    # Hashed form: status_fixture_<24hex>_<name>
    m = re.match(r"^status_fixture_[a-f0-9]{24}_(.+)$", name)
    if m:
        return f"status_fixture:{m.group(1)}"
    # Old form: status_fixture_<name> (no hash)
    m = re.match(r"^status_fixture_(.+)$", name)
    if m:
        stem = m.group(1)
        # Don't collapse if stem looks like a hash prefix itself
        if not re.match(r"^[a-f0-9]{16,}$", stem):
            return f"status_fixture:{stem}"
    return name


def print_table(headers: list[str], rows: list[list[str]], right_align: Optional[set[int]] = None):
    if not rows:
        return
    right_align = right_align or set()
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell))

    def fmt_cell(val: str, w: int, idx: int) -> str:
        if idx in right_align:
            return val.rjust(w)
        return val.ljust(w)

    header_line = "  ".join(fmt_cell(h, widths[i], i) for i, h in enumerate(headers))
    sep = "  ".join("-" * w for w in widths)
    print(header_line)
    print(sep)
    for row in rows:
        padded = row + [""] * (len(headers) - len(row))
        print("  ".join(fmt_cell(padded[i], widths[i], i) for i in range(len(headers))))


def print_report(
    runs: list[RunMeta],
    gate_results: list[GateResult],
    top_n: int,
    trend_days: int,
):
    now = datetime.now(tz=timezone.utc)
    cutoff_recent = now - timedelta(days=trend_days)
    cutoff_prior = cutoff_recent - timedelta(days=trend_days)

    # --- Section 1: Overall summary ---
    print("=" * 64)
    print("  VERIFY STATS REPORT")
    print("=" * 64)
    print()

    total = len(runs)
    passed = sum(1 for r in runs if r.status == "ok")
    failed = total - passed
    print(f"Total runs:  {total}")
    print(f"Passed:      {passed} ({fmt_pct(passed/total) if total else '-'})")
    print(f"Failed:      {failed} ({fmt_pct(failed/total) if total else '-'})")

    if runs:
        first = min(r.started_at for r in runs if r.started_at)
        last = max(r.started_at for r in runs if r.started_at)
        if first and last:
            span = (last - first).days
            print(f"Date range:  {first.strftime('%Y-%m-%d')} to {last.strftime('%Y-%m-%d')} ({span} days)")

    print()

    # By mode
    modes = defaultdict(lambda: {"total": 0, "passed": 0})
    for r in runs:
        modes[r.mode]["total"] += 1
        if r.status == "ok":
            modes[r.mode]["passed"] += 1

    print("By mode:")
    rows = []
    for mode in sorted(modes):
        m = modes[mode]
        fail_count = m["total"] - m["passed"]
        rows.append([
            mode,
            str(m["total"]),
            str(m["passed"]),
            str(fail_count),
            fmt_pct(fail_count / m["total"]) if m["total"] else "-",
        ])
    print_table(["Mode", "Runs", "Pass", "Fail", "Fail%"], rows, right_align={1, 2, 3, 4})
    print()

    # --- Section 2: First-failure gate (which gate killed the run?) ---
    print("-" * 64)
    print("  TOP GATES THAT KILL RUNS (first failure)")
    print("-" * 64)
    print()

    kill_counts: dict[str, int] = defaultdict(int)
    for r in runs:
        if r.failed_gate:
            kill_counts[normalize_gate_name(r.failed_gate)] += 1

    if kill_counts:
        sorted_kills = sorted(kill_counts.items(), key=lambda x: -x[1])[:top_n]
        rows = []
        for gate, count in sorted_kills:
            rows.append([gate, str(count), fmt_pct(count / failed) if failed else "-"])
        print_table(["Gate", "Kills", "% of failures"], rows, right_align={1, 2})
    else:
        print("  (no failures recorded)")
    print()

    # --- Section 3: Per-gate failure rate ---
    print("-" * 64)
    print("  PER-GATE FAILURE RATE (ranked by fail count)")
    print("-" * 64)
    print()

    # Normalize gate names in results
    normalized_results = []
    for r in gate_results:
        normalized_results.append(GateResult(
            gate=normalize_gate_name(r.gate),
            rc=r.rc, elapsed_s=r.elapsed_s,
            run_id=r.run_id, mode=r.mode, timestamp=r.timestamp,
        ))

    stats = compute_gate_stats(normalized_results)
    failing_gates = {k: v for k, v in stats.items() if v.failures > 0}
    sorted_failing = sorted(failing_gates.values(), key=lambda g: -g.failures)[:top_n]

    if sorted_failing:
        rows = []
        for g in sorted_failing:
            rows.append([
                g.gate,
                str(g.total),
                str(g.failures),
                fmt_pct(g.fail_rate),
                str(g.timeouts),
                str(g.logic_failures),
            ])
        print_table(
            ["Gate", "Runs", "Fails", "Fail%", "Timeouts", "Logic"],
            rows, right_align={1, 2, 3, 4, 5},
        )
    else:
        print("  (no gate failures)")
    print()

    # --- Section 4: Timing stats ---
    print("-" * 64)
    print("  GATE TIMING (top by p95, gates with >5 samples)")
    print("-" * 64)
    print()

    timed_gates = {k: v for k, v in stats.items() if len(v.timings) > 5}
    sorted_timed = sorted(timed_gates.values(), key=lambda g: -(g.timing_percentile(95) or 0))[:top_n]

    if sorted_timed:
        rows = []
        for g in sorted_timed:
            rows.append([
                g.gate,
                str(len(g.timings)),
                fmt_time(g.timing_avg),
                fmt_time(g.timing_percentile(50)),
                fmt_time(g.timing_percentile(95)),
                fmt_time(g.timing_max),
            ])
        print_table(
            ["Gate", "Samples", "Avg", "p50", "p95", "Max"],
            rows, right_align={1, 2, 3, 4, 5},
        )
    else:
        print("  (insufficient timing data)")
    print()

    # --- Section 5: Trend ---
    print("-" * 64)
    print(f"  TREND (last {trend_days}d vs prior {trend_days}d)")
    print("-" * 64)
    print()

    recent_runs = [r for r in runs if r.started_at and r.started_at >= cutoff_recent]
    prior_runs = [r for r in runs if r.started_at and cutoff_prior <= r.started_at < cutoff_recent]

    def period_stats(period_runs: list[RunMeta]) -> tuple[int, int, float]:
        t = len(period_runs)
        f = sum(1 for r in period_runs if r.status != "ok")
        rate = f / t if t > 0 else 0.0
        return t, f, rate

    r_total, r_fail, r_rate = period_stats(recent_runs)
    p_total, p_fail, p_rate = period_stats(prior_runs)

    rows = [
        [f"Last {trend_days}d", str(r_total), str(r_fail), fmt_pct(r_rate)],
        [f"Prior {trend_days}d", str(p_total), str(p_fail), fmt_pct(p_rate)],
    ]
    print_table(["Period", "Runs", "Fails", "Fail%"], rows, right_align={1, 2, 3})

    if r_rate < p_rate and p_total > 0:
        delta = p_rate - r_rate
        print(f"\n  Improving: fail rate down {delta*100:.1f}pp")
    elif r_rate > p_rate and r_total > 0:
        delta = r_rate - p_rate
        print(f"\n  Degrading: fail rate up {delta*100:.1f}pp")
    elif r_total > 0 and p_total > 0:
        print("\n  Stable")
    print()

    # Per-gate trend for recently-failing gates
    recent_gate_results = [r for r in normalized_results if r.timestamp >= cutoff_recent]
    prior_gate_results = [r for r in normalized_results if cutoff_prior <= r.timestamp < cutoff_recent]

    recent_stats = compute_gate_stats(recent_gate_results)
    prior_stats = compute_gate_stats(prior_gate_results)

    # Find gates that got worse
    worsened = []
    for gate, rs in recent_stats.items():
        if rs.failures == 0:
            continue
        ps = prior_stats.get(gate)
        prior_rate = ps.fail_rate if ps else 0.0
        if rs.fail_rate > prior_rate:
            worsened.append((gate, rs, prior_rate))

    if worsened:
        worsened.sort(key=lambda x: -(x[1].fail_rate - x[2]))
        print(f"  Gates that got WORSE (last {trend_days}d):")
        rows = []
        for gate, rs, pr in worsened[:10]:
            rows.append([
                gate,
                fmt_pct(pr),
                fmt_pct(rs.fail_rate),
                f"+{(rs.fail_rate - pr)*100:.1f}pp",
            ])
        print_table(["Gate", f"Prior {trend_days}d", f"Last {trend_days}d", "Delta"], rows, right_align={1, 2, 3})
        print()


def build_json_report(
    runs: list[RunMeta],
    gate_results: list[GateResult],
    top_n: int,
    trend_days: int,
) -> dict:
    now = datetime.now(tz=timezone.utc)
    cutoff_recent = now - timedelta(days=trend_days)
    cutoff_prior = cutoff_recent - timedelta(days=trend_days)

    total = len(runs)
    passed = sum(1 for r in runs if r.status == "ok")

    modes = defaultdict(lambda: {"total": 0, "passed": 0})
    for r in runs:
        modes[r.mode]["total"] += 1
        if r.status == "ok":
            modes[r.mode]["passed"] += 1

    kill_counts: dict[str, int] = defaultdict(int)
    for r in runs:
        if r.failed_gate:
            kill_counts[normalize_gate_name(r.failed_gate)] += 1

    normalized = [
        GateResult(
            gate=normalize_gate_name(r.gate), rc=r.rc, elapsed_s=r.elapsed_s,
            run_id=r.run_id, mode=r.mode, timestamp=r.timestamp,
        )
        for r in gate_results
    ]
    stats = compute_gate_stats(normalized)

    gate_list = []
    for g in sorted(stats.values(), key=lambda g: -g.failures):
        entry: dict = {
            "gate": g.gate,
            "total": g.total,
            "passes": g.passes,
            "failures": g.failures,
            "timeouts": g.timeouts,
            "logic_failures": g.logic_failures,
            "fail_rate": round(g.fail_rate, 4),
        }
        if g.timings:
            entry["timing"] = {
                "samples": len(g.timings),
                "avg_s": round(g.timing_avg, 2) if g.timing_avg else None,
                "p50_s": round(g.timing_percentile(50), 2) if g.timing_percentile(50) is not None else None,
                "p95_s": round(g.timing_percentile(95), 2) if g.timing_percentile(95) is not None else None,
                "max_s": round(g.timing_max, 2) if g.timing_max else None,
            }
        gate_list.append(entry)

    recent_runs = [r for r in runs if r.started_at and r.started_at >= cutoff_recent]
    prior_runs = [r for r in runs if r.started_at and cutoff_prior <= r.started_at < cutoff_recent]

    def period_obj(period_runs: list[RunMeta]) -> dict:
        t = len(period_runs)
        f = sum(1 for r in period_runs if r.status != "ok")
        return {"runs": t, "failures": f, "fail_rate": round(f / t, 4) if t else 0}

    return {
        "generated_at": now.isoformat(),
        "summary": {
            "total_runs": total,
            "passed": passed,
            "failed": total - passed,
            "fail_rate": round((total - passed) / total, 4) if total else 0,
        },
        "by_mode": {m: {"total": v["total"], "passed": v["passed"], "failed": v["total"] - v["passed"]} for m, v in modes.items()},
        "run_killers": dict(sorted(kill_counts.items(), key=lambda x: -x[1])[:top_n]),
        "gates": gate_list[:top_n] if top_n < len(gate_list) else gate_list,
        "trend": {
            "window_days": trend_days,
            "recent": period_obj(recent_runs),
            "prior": period_obj(prior_runs),
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Verify run statistics")
    parser.add_argument("--artifacts-dir", default=None,
                        help="Path to artifacts/verify/ (auto-detected from repo root)")
    parser.add_argument("--since", default=None,
                        help="Only include runs from last N days/hours (e.g. 7d, 24h)")
    parser.add_argument("--mode", default=None, choices=["quick", "full"],
                        help="Filter to only quick or full runs")
    parser.add_argument("--top", type=int, default=20,
                        help="Show top N gates (default: 20)")
    parser.add_argument("--trend", type=int, default=7,
                        help="Trend comparison window in days (default: 7)")
    parser.add_argument("--json", action="store_true",
                        help="Output as JSON instead of table")
    args = parser.parse_args()

    # Find artifacts dir
    if args.artifacts_dir:
        artifacts_dir = Path(args.artifacts_dir)
    else:
        # Walk up to find repo root
        here = Path(__file__).resolve().parent
        for p in [here.parent, here.parent.parent, Path.cwd()]:
            candidate = p / "artifacts" / "verify"
            if candidate.is_dir():
                artifacts_dir = candidate
                break
        else:
            print("ERROR: Cannot find artifacts/verify/ directory", file=sys.stderr)
            sys.exit(1)

    # Parse --since
    since_cutoff = None
    if args.since:
        delta = parse_duration(args.since)
        if delta is None:
            print(f"ERROR: Invalid --since format: {args.since} (use e.g. 7d, 24h, 30m)", file=sys.stderr)
            sys.exit(1)
        since_cutoff = datetime.now(tz=timezone.utc) - delta

    # Load all runs
    runs: list[RunMeta] = []
    all_gate_results: list[GateResult] = []

    run_dirs = sorted(artifacts_dir.iterdir()) if artifacts_dir.is_dir() else []
    for run_dir in run_dirs:
        if not run_dir.is_dir():
            continue
        run = load_run(run_dir)
        if run is None:
            continue

        # Apply filters
        if args.mode and run.mode != args.mode:
            continue
        if since_cutoff and run.started_at and run.started_at < since_cutoff:
            continue

        runs.append(run)
        all_gate_results.extend(load_gate_results(run))

    if not runs:
        print("No verify runs found matching filters.", file=sys.stderr)
        sys.exit(0)

    if args.json:
        report = build_json_report(runs, all_gate_results, args.top, args.trend)
        json.dump(report, sys.stdout, indent=2)
        print()
    else:
        print_report(runs, all_gate_results, args.top, args.trend)


if __name__ == "__main__":
    main()
