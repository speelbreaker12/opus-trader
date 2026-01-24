#!/usr/bin/env python3
"""check_state_machines.py
Structural linter for state machine specs.

Checks (strict mode):
- stored_state machines must define initial_state
- non-terminal states must have an outgoing transition
- states must be reachable (inbound transition exists, except initial_state)

Always enforces:
- required machine fields, transitions, illegal transitions, events, and effects
- duplicate states/acceptance_tests/terminal_states are errors
- entry_conditions cover all states
- transitions have id/from/to/event/guard/effects and fail_closed/on_fail
- illegal transitions are defined and policy is hard_fail
- referenced events/effects exist (when catalogs provided)
- duplicate transitions or ambiguous guards
- contract enum coverage for TradingMode/RiskState
- latch bool coverage for OpenPermissionLatch
- flow traceability (invariant IDs and transition refs)

Exit codes:
0 = pass
2 = errors
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

try:
    import yaml
except Exception:
    yaml = None

GI_HEADER_RE = re.compile(r"^###\s+(GI-\d{3})\b")
ENUM_RE = re.compile(r"^\s*-\s+\*\*(TradingMode|RiskState)\*\*.*?:\s*`([^`]+)`")


@dataclass(frozen=True)
class MachineResult:
    name: str
    transition_ids: Set[str]


def die(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(2)


def load_yaml(path: Path) -> Dict[str, Any]:
    if yaml is None:
        die("PyYAML not installed (pip install pyyaml)")
    try:
        obj = yaml.safe_load(path.read_text(encoding="utf-8", errors="replace"))
    except Exception as e:
        die(f"YAML parse error: {e}")
    if not isinstance(obj, dict):
        die("Machine spec file must be a YAML mapping (dict) at top-level")
    return obj


def load_lines(path: Path) -> List[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def dupes(items: List[str]) -> List[str]:
    seen: Set[str] = set()
    out: Set[str] = set()
    for x in items:
        if x in seen:
            out.add(x)
        else:
            seen.add(x)
    return sorted(out)


def parse_contract_enums(contract_lines: List[str]) -> Dict[str, Set[str]]:
    enums: Dict[str, Set[str]] = {}
    for line in contract_lines:
        m = ENUM_RE.match(line)
        if not m:
            continue
        name = m.group(1)
        raw = m.group(2)
        vals = [v.strip() for v in raw.split("|") if v.strip()]
        enums[name] = set(vals)
    return enums


def contract_has_latch_bool(contract_lines: List[str]) -> bool:
    for line in contract_lines:
        if "open_permission_blocked_latch" in line and "bool" in line:
            return True
    return False


def validate_machine(
    m: Dict[str, Any],
    strict: bool,
    contract_enums: Dict[str, Set[str]],
    latch_bool: bool,
) -> Tuple[List[str], MachineResult]:
    errs: List[str] = []
    source = m.get("_source")
    mid = m.get("machine_id")
    if not isinstance(mid, str) or not mid.strip():
        msg = "machine_id missing/invalid"
        if source:
            msg = f"{source}: {msg}"
        return [msg], MachineResult("<unknown>", set())

    prefix = mid if not source else f"{mid} ({source})"

    kind = m.get("kind", "stored_state")

    states = m.get("states")
    if not isinstance(states, list) or not states:
        return [f"{prefix}: states[] missing/empty"], MachineResult(mid, set())

    states_clean = [s for s in states if isinstance(s, str) and s.strip()]
    if len(states_clean) != len(states):
        errs.append(f"{prefix}: states[] contains non-string or empty entries")
    d = dupes(states_clean)
    if d:
        errs.append(f"{prefix}: duplicate state names in states[]: {d}")
    state_set = set(states_clean)

    entry_conditions = m.get("entry_conditions")
    if not isinstance(entry_conditions, dict):
        errs.append(f"{prefix}: entry_conditions mapping missing/invalid")
    else:
        for key in entry_conditions:
            if not isinstance(key, str):
                errs.append(f"{prefix}: entry_conditions has non-string state key")
        missing_ec = [s for s in state_set if s not in entry_conditions]
        if missing_ec:
            errs.append(f"{prefix}: entry_conditions missing for states: {sorted(missing_ec)}")
        extra_ec = [k for k in entry_conditions.keys() if isinstance(k, str) and k not in state_set]
        if extra_ec:
            errs.append(f"{prefix}: entry_conditions has unknown states: {sorted(extra_ec)}")
        for s in state_set:
            val = entry_conditions.get(s)
            if not isinstance(val, str):
                errs.append(f"{prefix}: entry_conditions for state '{s}' must be a string")
            elif strict and not val.strip():
                errs.append(f"{prefix}: entry_conditions empty for state '{s}'")

    terminal_states = m.get("terminal_states")
    if terminal_states is None:
        errs.append(f"{prefix}: terminal_states must be present (can be empty list)")
        terminal_states = []
    if not isinstance(terminal_states, list):
        errs.append(f"{prefix}: terminal_states must be a list")
        terminal_states = []
    else:
        term_clean = [t for t in terminal_states if isinstance(t, str)]
        td = dupes(term_clean)
        if td:
            errs.append(f"{prefix}: duplicate terminal state names: {td}")
        for t in term_clean:
            if t not in state_set:
                errs.append(f"{prefix}: terminal state '{t}' not in states[]")

    tests = m.get("acceptance_tests")
    if tests is None:
        errs.append(f"{prefix}: acceptance_tests[] missing")
    elif not isinstance(tests, list):
        errs.append(f"{prefix}: acceptance_tests must be a list")
    else:
        tclean = [t for t in tests if isinstance(t, str)]
        td = dupes(tclean)
        if td:
            errs.append(f"{prefix}: duplicate AT ids in acceptance_tests[]: {td}")

    if kind != "derived_each_tick":
        init = m.get("initial_state")
        if strict and init is None:
            errs.append(f"{prefix}: initial_state is required for kind='{kind}'")
        if init is not None and init not in state_set:
            errs.append(f"{prefix}: initial_state '{init}' not in states[]")
    else:
        init = None

    # events
    events = m.get("events")
    event_ids: Set[str] = set()
    if not isinstance(events, list) or not events:
        errs.append(f"{prefix}: events[] missing/empty")
    else:
        for idx, ev in enumerate(events):
            if not isinstance(ev, str) or not ev.strip():
                errs.append(f"{prefix}: events[{idx}] invalid id")
                continue
            if ev in event_ids:
                errs.append(f"{prefix}: duplicate event id '{ev}'")
            event_ids.add(ev)

    # effects catalog (optional but validated if present)
    effects_catalog = m.get("effects_catalog")
    effect_ids: Set[str] = set()
    if effects_catalog is not None:
        if not isinstance(effects_catalog, list):
            errs.append(f"{prefix}: effects_catalog must be a list")
        else:
            for idx, eff in enumerate(effects_catalog):
                if not isinstance(eff, dict):
                    errs.append(f"{prefix}: effects_catalog[{idx}] is not a dict")
                    continue
                eid = eff.get("id")
                if not isinstance(eid, str) or not eid.strip():
                    errs.append(f"{prefix}: effects_catalog[{idx}] missing id")
                    continue
                if eid in effect_ids:
                    errs.append(f"{prefix}: duplicate effect id '{eid}'")
                effect_ids.add(eid)

    # transitions
    transitions = m.get("transitions")
    transition_ids: Set[str] = set()
    inbound: Dict[str, int] = {s: 0 for s in state_set}
    outbound: Dict[str, int] = {s: 0 for s in state_set}
    transition_keys: Set[Tuple[str, str, str, str]] = set()
    guard_index: Dict[Tuple[str, str, str], str] = {}

    if not isinstance(transitions, list) or not transitions:
        errs.append(f"{prefix}: transitions[] missing/empty")
        transitions = []

    for idx, tr in enumerate(transitions):
        if not isinstance(tr, dict):
            errs.append(f"{prefix}: transition[{idx}] is not a dict")
            continue
        tid = tr.get("id")
        fr = tr.get("from")
        to = tr.get("to")
        event = tr.get("event")
        guard = tr.get("guard")
        effects_ref = tr.get("effects")
        fail_closed = tr.get("fail_closed")
        on_fail = tr.get("on_fail")

        missing = [k for k in ["id", "from", "to", "event", "guard", "effects"] if tr.get(k) is None]
        if missing:
            errs.append(f"{prefix}: transition[{idx}] missing fields: {missing}")
            continue

        if not isinstance(tid, str) or not tid.strip():
            errs.append(f"{prefix}: transition[{idx}] invalid id")
        else:
            if tid in transition_ids:
                errs.append(f"{prefix}: duplicate transition id '{tid}'")
            transition_ids.add(tid)

        if not isinstance(to, str) or to not in state_set:
            errs.append(f"{prefix}: transition[{idx}] has unknown to='{to}'")
        if fr == "*":
            for s in state_set:
                outbound[s] += 1
        elif isinstance(fr, str) and fr in state_set:
            outbound[fr] += 1
        else:
            errs.append(f"{prefix}: transition[{idx}] has unknown from='{fr}'")

        if isinstance(to, str) and to in state_set:
            inbound[to] += 1

        if not isinstance(event, str) or event not in event_ids:
            errs.append(f"{prefix}: transition[{idx}] has unknown event='{event}'")
        if not isinstance(guard, str) or not guard.strip():
            errs.append(f"{prefix}: transition[{idx}] guard missing/empty")
        if fail_closed is not None and on_fail is not None and fail_closed != on_fail:
            errs.append(f"{prefix}: transition[{idx}] fail_closed and on_fail differ")
        fc = fail_closed if fail_closed is not None else on_fail
        if fc is None:
            errs.append(f"{prefix}: transition[{idx}] missing fail_closed/on_fail")
        elif not isinstance(fc, str) or not fc.strip():
            errs.append(f"{prefix}: transition[{idx}] fail_closed/on_fail missing/empty")

        if not isinstance(effects_ref, list) or not effects_ref:
            errs.append(f"{prefix}: transition[{idx}] effects must be a non-empty list")
        else:
            for eff in effects_ref:
                if not isinstance(eff, str):
                    errs.append(f"{prefix}: transition[{idx}] effect id must be a string")
                    continue
                if effect_ids and eff not in effect_ids:
                    errs.append(f"{prefix}: transition[{idx}] unknown effect '{eff}'")

        key = (str(fr), str(to), str(event), str(guard))
        if key in transition_keys:
            errs.append(f"{prefix}: duplicate transition signature {key}")
        transition_keys.add(key)

        guard_key = (str(fr), str(event), str(guard))
        if guard_key in guard_index and guard_index[guard_key] != str(to):
            errs.append(f"{prefix}: ambiguous guard for from='{fr}', event='{event}', guard='{guard}'")
        else:
            guard_index[guard_key] = str(to)

    # illegal transitions
    illegal_policy = m.get("illegal_transition_policy")
    if illegal_policy != "hard_fail":
        errs.append(f"{prefix}: illegal_transition_policy must be 'hard_fail'")

    illegal_transitions = m.get("illegal_transitions")
    if not isinstance(illegal_transitions, list) or not illegal_transitions:
        errs.append(f"{prefix}: illegal_transitions[] missing/empty")
    else:
        illegal_ids: Set[str] = set()
        for idx, tr in enumerate(illegal_transitions):
            if not isinstance(tr, dict):
                errs.append(f"{prefix}: illegal_transitions[{idx}] is not a dict")
                continue
            tid = tr.get("id")
            fr = tr.get("from")
            to = tr.get("to")
            event = tr.get("event")
            guard = tr.get("guard")
            effects_ref = tr.get("effects")
            fail_closed = tr.get("fail_closed")
            on_fail = tr.get("on_fail")
            missing = [k for k in ["id", "from", "to", "event", "guard", "effects"] if tr.get(k) is None]
            if missing:
                errs.append(f"{prefix}: illegal_transitions[{idx}] missing fields: {missing}")
                continue
            if not isinstance(tid, str) or not tid.strip():
                errs.append(f"{prefix}: illegal_transitions[{idx}] invalid id")
            else:
                if tid in illegal_ids:
                    errs.append(f"{prefix}: duplicate illegal transition id '{tid}'")
                if tid in transition_ids:
                    errs.append(f"{prefix}: illegal transition id '{tid}' conflicts with transition id")
                illegal_ids.add(tid)
            if fr != "*" and fr not in state_set:
                errs.append(f"{prefix}: illegal_transitions[{idx}] unknown from='{fr}'")
            if to != "*" and to not in state_set:
                errs.append(f"{prefix}: illegal_transitions[{idx}] unknown to='{to}'")
            if not isinstance(event, str) or event not in event_ids:
                errs.append(f"{prefix}: illegal_transitions[{idx}] unknown event='{event}'")
            if not isinstance(guard, str) or not guard.strip():
                errs.append(f"{prefix}: illegal_transitions[{idx}] guard missing/empty")
            if fail_closed is not None and on_fail is not None and fail_closed != on_fail:
                errs.append(f"{prefix}: illegal_transitions[{idx}] fail_closed and on_fail differ")
            fc = fail_closed if fail_closed is not None else on_fail
            if fc is None:
                errs.append(f"{prefix}: illegal_transitions[{idx}] missing fail_closed/on_fail")
            elif not isinstance(fc, str) or not fc.strip():
                errs.append(f"{prefix}: illegal_transitions[{idx}] fail_closed/on_fail missing/empty")
            if not isinstance(effects_ref, list) or not effects_ref:
                errs.append(f"{prefix}: illegal_transitions[{idx}] effects must be a non-empty list")
            else:
                for eff in effects_ref:
                    if not isinstance(eff, str):
                        errs.append(f"{prefix}: illegal_transitions[{idx}] effect id must be a string")
                        continue
                    if effect_ids and eff not in effect_ids:
                        errs.append(f"{prefix}: illegal_transitions[{idx}] unknown effect '{eff}'")

    # reachability and exits
    for s in state_set:
        if init is not None and s == init:
            continue
        if inbound.get(s, 0) == 0:
            errs.append(f"{prefix}: state '{s}' has no inbound transitions (unreachable)")

    terminals = set(terminal_states) if isinstance(terminal_states, list) else set()
    if strict:
        for s in state_set:
            if s in terminals:
                continue
            if outbound.get(s, 0) == 0:
                errs.append(f"{prefix}: non-terminal state '{s}' has no outbound transitions")

    # contract enum coverage
    if mid in contract_enums:
        expected = contract_enums[mid]
        external_mapping = m.get("external_mapping", {})
        mapped = set()
        if isinstance(external_mapping, dict):
            mapped = set(str(v) for v in external_mapping.values())
        covered = state_set | mapped
        missing = sorted(v for v in expected if v not in covered)
        if missing:
            errs.append(f"{prefix}: contract enum values missing from state machine: {missing}")

    if mid == "OpenPermissionLatch" and latch_bool:
        state_value_map = m.get("state_value_map")
        if not isinstance(state_value_map, dict):
            errs.append(f"{prefix}: state_value_map required for latch bool coverage")
        else:
            values: Set[bool] = set()
            for st in state_set:
                mapping = state_value_map.get(st)
                if not isinstance(mapping, dict):
                    errs.append(f"{prefix}: state_value_map missing mapping for state '{st}'")
                    continue
                val = mapping.get("open_permission_blocked_latch")
                if not isinstance(val, bool):
                    errs.append(f"{prefix}: state_value_map for '{st}' must include boolean open_permission_blocked_latch")
                    continue
                values.add(val)
            if values != {True, False}:
                errs.append(f"{prefix}: state_value_map must cover open_permission_blocked_latch true and false")

    return errs, MachineResult(name=mid, transition_ids=transition_ids)


def load_invariant_ids(path: Path) -> Set[str]:
    ids: Set[str] = set()
    for line in load_lines(path):
        m = GI_HEADER_RE.match(line.strip())
        if m:
            ids.add(m.group(1))
    return ids


def check_flows(flows_path: Path, invariants_path: Path, transition_map: Dict[str, Set[str]]) -> List[str]:
    errs: List[str] = []
    if yaml is None:
        errs.append("PyYAML not installed (pip install pyyaml)")
        return errs

    if not flows_path.exists():
        errs.append(f"flows file not found: {flows_path}")
        return errs
    if not invariants_path.exists():
        errs.append(f"invariants file not found: {invariants_path}")
        return errs

    flows_doc = yaml.safe_load(flows_path.read_text(encoding="utf-8", errors="replace"))
    if not isinstance(flows_doc, dict):
        errs.append("ARCH_FLOWS.yaml must be a YAML mapping (dict) at top-level")
        return errs

    flows = flows_doc.get("flows")
    if not isinstance(flows, list) or not flows:
        errs.append("ARCH_FLOWS.yaml top-level 'flows' must be a non-empty list")
        return errs

    invariant_ids = load_invariant_ids(invariants_path)
    for flow in flows:
        if not isinstance(flow, dict):
            errs.append("flow entry is not a dict")
            continue
        fid = flow.get("id", "<unknown>")
        if not isinstance(fid, str) or not fid.startswith("ACF-"):
            continue
        refs = flow.get("refs")
        if not isinstance(refs, dict):
            errs.append(f"{fid}: refs missing or not a dict")
            continue

        inv_refs = refs.get("global_invariants")
        if not isinstance(inv_refs, list) or not inv_refs:
            errs.append(f"{fid}: refs.global_invariants missing/empty")
        else:
            for inv in inv_refs:
                if not isinstance(inv, str) or inv not in invariant_ids:
                    errs.append(f"{fid}: invariant ref not found: {inv}")

        trans_refs = refs.get("state_transitions")
        if not isinstance(trans_refs, list) or not trans_refs:
            errs.append(f"{fid}: refs.state_transitions missing/empty")
        else:
            for ref in trans_refs:
                if not isinstance(ref, str) or ":" not in ref:
                    errs.append(f"{fid}: invalid state transition ref '{ref}' (expected Machine:TransitionId)")
                    continue
                machine, tid = ref.split(":", 1)
                if machine not in transition_map:
                    errs.append(f"{fid}: unknown machine in state transition ref '{ref}'")
                    continue
                if tid not in transition_map[machine]:
                    errs.append(f"{fid}: transition id not found: {ref}")

    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="specs/state_machines", help="Directory of machine spec files")
    ap.add_argument("--file", action="append", help="Machine spec file (can be repeated)")
    ap.add_argument("--strict", action="store_true")
    ap.add_argument("--contract", default="specs/CONTRACT.md", help="Path to CONTRACT.md")
    ap.add_argument("--flows", default="specs/flows/ARCH_FLOWS.yaml", help="Path to ARCH_FLOWS.yaml")
    ap.add_argument("--invariants", default="specs/invariants/GLOBAL_INVARIANTS.md", help="Path to GLOBAL_INVARIANTS.md")
    args = ap.parse_args()

    paths: List[Path] = []
    if args.file:
        paths = [Path(p) for p in args.file]
    else:
        base = Path(args.dir)
        if not base.exists():
            die(f"Directory not found: {base}")
        paths = sorted(base.glob("*.yaml"))
    if not paths:
        die("No machine spec files found")
    for p in paths:
        if not p.exists():
            die(f"File not found: {p}")

    contract_path = Path(args.contract)
    if not contract_path.exists():
        die(f"Contract file not found: {contract_path}")

    contract_lines = load_lines(contract_path)
    contract_enums = parse_contract_enums(contract_lines)
    latch_bool = contract_has_latch_bool(contract_lines)

    machines: List[Dict[str, Any]] = []
    for p in paths:
        doc = load_yaml(p)
        if not isinstance(doc, dict):
            die(f"Machine spec must be a YAML mapping: {p}")
        doc["_source"] = str(p)
        machines.append(doc)

    seen: Set[str] = set()
    errs: List[str] = []
    transition_map: Dict[str, Set[str]] = {}

    for m in machines:
        if not isinstance(m, dict):
            errs.append("machine entry is not a dict")
            continue
        mid = m.get("machine_id", "<unknown>")
        if mid in seen:
            errs.append(f"Duplicate machine_id: {mid}")
        else:
            seen.add(mid)
        machine_errs, info = validate_machine(m, strict=args.strict, contract_enums=contract_enums, latch_bool=latch_bool)
        errs.extend(machine_errs)
        transition_map[info.name] = info.transition_ids

    flow_errs = check_flows(Path(args.flows), Path(args.invariants), transition_map)
    errs.extend(flow_errs)

    if errs:
        for e in errs:
            print(f"ERROR: {e}", file=sys.stderr)
        return 2

    print("STATE MACHINES OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
