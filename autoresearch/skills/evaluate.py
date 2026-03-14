#!/usr/bin/env python3
"""
Skill Auto-Research: Binary Assertion Evaluator

Evaluates skill outputs against binary assertions from eval.json.
Supports both programmatic rules (fast, free, objective) and
natural-language checks (require human or Claude review).

Usage:
    python3 evaluate.py --eval eval.json --output-dir outputs/
    python3 evaluate.py --eval eval.json --output-dir outputs/ --verbose
    python3 evaluate.py --eval eval.json --output-dir outputs/ --json

Rule types (in eval.json assertion "rule" field):
    contains        — output contains the value string
    not_contains    — output does NOT contain the value string
    regex           — output matches the regex pattern
    not_regex       — output does NOT match the regex pattern
    count_min       — at least N occurrences of pattern
    count_max       — at most N occurrences of pattern
    count_exact     — exactly N occurrences of pattern
    word_count_max  — total word count is under max
    word_count_min  — total word count is at least min
    all_sections_have — every section matching section_pattern contains required
    line_count_max  — total line count is under max

If no "rule" field is present, the assertion requires manual/semantic evaluation
and is marked as "needs_review".
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

# ── ANSI Colors ──────────────────────────────────────────────────────

GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
BOLD = "\033[1m"
NC = "\033[0m"


# ── Rule Evaluators ──────────────────────────────────────────────────

def eval_contains(output: str, rule: dict) -> tuple[bool, str]:
    value = rule["value"]
    found = value in output
    reason = f"found '{value[:60]}'" if found else f"'{value[:60]}' not found"
    return found, reason


def eval_not_contains(output: str, rule: dict) -> tuple[bool, str]:
    value = rule["value"]
    found = value in output
    if found:
        # Find first occurrence for context
        idx = output.index(value)
        context = output[max(0, idx - 20):idx + len(value) + 20].replace("\n", "\\n")
        return False, f"found '{value[:40]}' at: ...{context}..."
    return True, f"'{value[:60]}' correctly absent"


def eval_regex(output: str, rule: dict) -> tuple[bool, str]:
    pattern = rule["pattern"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    match = re.search(pattern, output, flags)
    if match:
        return True, f"matched: '{match.group()[:60]}'"
    return False, f"pattern /{pattern[:60]}/ not found"


def eval_not_regex(output: str, rule: dict) -> tuple[bool, str]:
    pattern = rule["pattern"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    match = re.search(pattern, output, flags)
    if match:
        return False, f"unwanted match: '{match.group()[:60]}'"
    return True, f"pattern /{pattern[:60]}/ correctly absent"


def eval_count_min(output: str, rule: dict) -> tuple[bool, str]:
    pattern = rule["pattern"]
    minimum = rule["min"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    matches = re.findall(pattern, output, flags)
    count = len(matches)
    passed = count >= minimum
    return passed, f"found {count} occurrences (need >= {minimum})"


def eval_count_max(output: str, rule: dict) -> tuple[bool, str]:
    pattern = rule["pattern"]
    maximum = rule["max"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    matches = re.findall(pattern, output, flags)
    count = len(matches)
    passed = count <= maximum
    return passed, f"found {count} occurrences (need <= {maximum})"


def eval_count_exact(output: str, rule: dict) -> tuple[bool, str]:
    pattern = rule["pattern"]
    expected = rule["count"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    matches = re.findall(pattern, output, flags)
    count = len(matches)
    passed = count == expected
    return passed, f"found {count} occurrences (need exactly {expected})"


def eval_word_count_max(output: str, rule: dict) -> tuple[bool, str]:
    maximum = rule["max"]
    count = len(output.split())
    passed = count <= maximum
    return passed, f"{count} words (limit {maximum})"


def eval_word_count_min(output: str, rule: dict) -> tuple[bool, str]:
    minimum = rule["min"]
    count = len(output.split())
    passed = count >= minimum
    return passed, f"{count} words (need >= {minimum})"


def eval_line_count_max(output: str, rule: dict) -> tuple[bool, str]:
    maximum = rule["max"]
    count = len(output.strip().splitlines())
    passed = count <= maximum
    return passed, f"{count} lines (limit {maximum})"


def eval_all_sections_have(output: str, rule: dict) -> tuple[bool, str]:
    """Check that every section matching section_pattern contains required field."""
    section_pattern = rule["section_pattern"]
    required = rule["required"]

    # Split output into sections by markdown headers
    sections = re.split(r"(?=^###?\s)", output, flags=re.MULTILINE)
    matching_sections = [s for s in sections if re.search(section_pattern, s)]

    if not matching_sections:
        return False, f"no sections matching /{section_pattern}/"

    missing = []
    for i, section in enumerate(matching_sections):
        if required not in section:
            # Extract section title for reporting
            title_match = re.match(r"###?\s+(.+)", section)
            title = title_match.group(1)[:40] if title_match else f"section {i}"
            missing.append(title)

    if missing:
        return False, f"missing '{required}' in: {', '.join(missing[:3])}"
    return True, f"all {len(matching_sections)} sections have '{required[:30]}'"


# ── Rule Dispatch ────────────────────────────────────────────────────

RULE_EVALUATORS = {
    "contains": eval_contains,
    "not_contains": eval_not_contains,
    "regex": eval_regex,
    "not_regex": eval_not_regex,
    "count_min": eval_count_min,
    "count_max": eval_count_max,
    "count_exact": eval_count_exact,
    "word_count_max": eval_word_count_max,
    "word_count_min": eval_word_count_min,
    "line_count_max": eval_line_count_max,
    "all_sections_have": eval_all_sections_have,
}


def evaluate_assertion(output: str, assertion: dict) -> dict:
    """Evaluate a single assertion against output text."""
    assertion_id = assertion["id"]
    check_desc = assertion.get("check", "")
    expected = assertion.get("expected", True)
    rule = assertion.get("rule")

    result = {
        "id": assertion_id,
        "check": check_desc,
        "expected": expected,
    }

    if rule is None:
        # No programmatic rule — needs manual/semantic evaluation
        result["passed"] = None
        result["method"] = "needs_review"
        result["reason"] = "no programmatic rule defined — requires manual evaluation"
        return result

    rule_type = rule.get("type", "")
    evaluator = RULE_EVALUATORS.get(rule_type)

    if evaluator is None:
        result["passed"] = None
        result["method"] = "unknown_rule"
        result["reason"] = f"unknown rule type: {rule_type}"
        return result

    try:
        raw_passed, reason = evaluator(output, rule)
        # Apply expected inversion: if expected=false, flip the result
        passed = raw_passed if expected else not raw_passed
        result["passed"] = passed
        result["method"] = "programmatic"
        result["reason"] = reason
    except Exception as e:
        result["passed"] = False
        result["method"] = "error"
        result["reason"] = f"evaluation error: {e}"

    return result


# ── Test Runner ──────────────────────────────────────────────────────

def run_evaluation(eval_config: dict, output_dir: Path, verbose: bool = False) -> dict:
    """Run all tests and return scored results."""
    tests = eval_config.get("tests", [])
    all_results = []
    total_passed = 0
    total_assertions = 0
    total_needs_review = 0

    for test in tests:
        test_id = test["id"]
        test_name = test.get("name", "")
        assertions = test.get("assertions", [])

        # Load output file
        output_file = output_dir / f"{test_id}.md"
        if not output_file.exists():
            # Try .txt extension
            output_file = output_dir / f"{test_id}.txt"

        if not output_file.exists():
            test_result = {
                "id": test_id,
                "name": test_name,
                "status": "missing_output",
                "passed": 0,
                "total": len(assertions),
                "needs_review": 0,
                "assertions": [],
            }
            for a in assertions:
                test_result["assertions"].append({
                    "id": a["id"],
                    "check": a.get("check", ""),
                    "passed": None,
                    "method": "skipped",
                    "reason": f"output file not found: {test_id}.md",
                })
            total_assertions += len(assertions)
            total_needs_review += len(assertions)
            all_results.append(test_result)

            if verbose:
                print(f"  {YELLOW}[{test_id}]{NC} {test_name} — output file missing")
            continue

        output_text = output_file.read_text(encoding="utf-8")
        assertion_results = []
        test_passed = 0
        test_needs_review = 0

        for assertion in assertions:
            ar = evaluate_assertion(output_text, assertion)
            assertion_results.append(ar)

            if ar["passed"] is True:
                test_passed += 1
                total_passed += 1
            elif ar["passed"] is None:
                test_needs_review += 1
                total_needs_review += 1

            total_assertions += 1

            if verbose:
                if ar["passed"] is True:
                    status_icon = f"{GREEN}PASS{NC}"
                elif ar["passed"] is False:
                    status_icon = f"{RED}FAIL{NC}"
                else:
                    status_icon = f"{YELLOW}REVIEW{NC}"
                print(f"    [{status_icon}] {ar['id']}: {ar['check'][:60]}")
                if ar["passed"] is False or (verbose and ar["passed"] is None):
                    print(f"           {ar['reason']}")

        test_result = {
            "id": test_id,
            "name": test_name,
            "status": "evaluated",
            "passed": test_passed,
            "total": len(assertions),
            "needs_review": test_needs_review,
            "assertions": assertion_results,
        }
        all_results.append(test_result)

        if verbose:
            color = GREEN if test_passed == len(assertions) else (YELLOW if test_needs_review > 0 else RED)
            print(f"  {color}[{test_id}]{NC} {test_name} — {test_passed}/{len(assertions)}")

    # Calculate score (only count programmatically evaluated assertions)
    evaluated = total_assertions - total_needs_review
    score = total_passed / evaluated if evaluated > 0 else 0.0

    return {
        "score": round(score, 4),
        "passed": total_passed,
        "total": total_assertions,
        "evaluated": evaluated,
        "needs_review": total_needs_review,
        "tests": all_results,
    }


# ── Main ─────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Evaluate skill outputs against binary assertions"
    )
    parser.add_argument(
        "--eval", required=True, help="Path to eval.json"
    )
    parser.add_argument(
        "--output-dir", required=True, help="Directory containing output files (T1.md, T2.md, ...)"
    )
    parser.add_argument(
        "--skill-dir", default=None, help="Skill eval directory (for relative fixture paths)"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true", help="Show per-assertion results"
    )
    parser.add_argument(
        "--json", action="store_true", help="Output results as JSON"
    )
    args = parser.parse_args()

    eval_path = Path(args.eval)
    output_dir = Path(args.output_dir)

    if not eval_path.exists():
        print(f"{RED}FAIL: eval.json not found: {eval_path}{NC}", file=sys.stderr)
        sys.exit(2)

    if not output_dir.exists():
        print(f"{RED}FAIL: output directory not found: {output_dir}{NC}", file=sys.stderr)
        print(f"Run with --generate to create outputs, or create them manually.", file=sys.stderr)
        sys.exit(2)

    with open(eval_path) as f:
        eval_config = json.load(f)

    results = run_evaluation(eval_config, output_dir, verbose=args.verbose)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        # Summary output
        print()
        score_color = GREEN if results["score"] >= 0.9 else (YELLOW if results["score"] >= 0.7 else RED)
        print(f"  {BOLD}Score:{NC}         {score_color}{results['score']:.1%}{NC} ({results['passed']}/{results['evaluated']} programmatic)")
        if results["needs_review"] > 0:
            print(f"  {BOLD}Needs review:{NC} {YELLOW}{results['needs_review']}{NC} assertions without programmatic rules")
        print()

        # Per-test summary
        for test in results["tests"]:
            if test["status"] == "missing_output":
                print(f"  {YELLOW}[{test['id']}]{NC} {test['name']} — output missing")
            else:
                color = GREEN if test["passed"] == test["total"] else RED
                print(f"  {color}[{test['id']}]{NC} {test['name']} — {test['passed']}/{test['total']}")

                # Show failures
                for ar in test["assertions"]:
                    if ar["passed"] is False:
                        print(f"       {RED}✗ {ar['id']}: {ar['reason']}{NC}")
        print()

    # Exit code: 0 if perfect, 1 if any failures
    sys.exit(0 if results["score"] >= 1.0 else 1)


if __name__ == "__main__":
    main()
