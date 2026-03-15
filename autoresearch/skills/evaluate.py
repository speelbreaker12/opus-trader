#!/usr/bin/env python3
"""
Skill Auto-Research: Binary Assertion Evaluator

Evaluates skill outputs against binary assertions from eval.json.
Supports both legacy text rules and contract-specific JSON rules.

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
    json_schema_valid — validate JSON against a JSON Schema
    json_field_match — selected JSON field(s) match a value or regex
    json_array_count_bounds — selected array count is within min/max
    resolved_span_exists — every selected replace_span resolves to an exact unique slice
    json_field_not_match — selected JSON field(s) do NOT match a value or regex
    json_cross_ref_exists — IDs selected from one JSON artifact exist in another
    json_cross_ref_match — mapped fields match resolved sibling-artifact records
    json_unique_field — all selected values are unique

If no "rule" field is present, the assertion requires manual/semantic evaluation
and is marked as "needs_review".
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator

# ── ANSI Colors ──────────────────────────────────────────────────────

GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[1;33m"
NC = "\033[0m"
BOLD = "\033[1m"


# ── Legacy Rule Evaluators ───────────────────────────────────────────

def eval_contains(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    value = rule["value"]
    found = value in output
    reason = f"found '{value[:60]}'" if found else f"'{value[:60]}' not found"
    return found, reason


def eval_not_contains(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    value = rule["value"]
    found = value in output
    if found:
        idx = output.index(value)
        context = output[max(0, idx - 20):idx + len(value) + 20].replace("\n", "\\n")
        return False, f"found '{value[:40]}' at: ...{context}..."
    return True, f"'{value[:60]}' correctly absent"


def eval_regex(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    pattern = rule["pattern"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    match = re.search(pattern, output, flags)
    if match:
        return True, f"matched: '{match.group()[:60]}'"
    return False, f"pattern /{pattern[:60]}/ not found"


def eval_not_regex(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    pattern = rule["pattern"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    match = re.search(pattern, output, flags)
    if match:
        return False, f"unwanted match: '{match.group()[:60]}'"
    return True, f"pattern /{pattern[:60]}/ correctly absent"


def eval_count_min(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    pattern = rule["pattern"]
    minimum = rule["min"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    count = len(re.findall(pattern, output, flags))
    return count >= minimum, f"found {count} occurrences (need >= {minimum})"


def eval_count_max(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    pattern = rule["pattern"]
    maximum = rule["max"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    count = len(re.findall(pattern, output, flags))
    return count <= maximum, f"found {count} occurrences (need <= {maximum})"


def eval_count_exact(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    pattern = rule["pattern"]
    expected = rule["count"]
    flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
    count = len(re.findall(pattern, output, flags))
    return count == expected, f"found {count} occurrences (need exactly {expected})"


def eval_word_count_max(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    maximum = rule["max"]
    count = len(output.split())
    return count <= maximum, f"{count} words (limit {maximum})"


def eval_word_count_min(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    minimum = rule["min"]
    count = len(output.split())
    return count >= minimum, f"{count} words (need >= {minimum})"


def eval_line_count_max(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    maximum = rule["max"]
    count = len(output.strip().splitlines())
    return count <= maximum, f"{count} lines (limit {maximum})"


def eval_all_sections_have(output: str, rule: dict[str, Any]) -> tuple[bool, str]:
    section_pattern = rule["section_pattern"]
    required = rule["required"]
    sections = re.split(r"(?=^###?\s)", output, flags=re.MULTILINE)
    matching_sections = [section for section in sections if re.search(section_pattern, section)]
    if not matching_sections:
        return False, f"no sections matching /{section_pattern}/"

    missing: list[str] = []
    for index, section in enumerate(matching_sections):
        if required in section:
            continue
        title_match = re.match(r"###?\s+(.+)", section)
        title = title_match.group(1)[:40] if title_match else f"section {index}"
        missing.append(title)

    if missing:
        return False, f"missing '{required}' in: {', '.join(missing[:3])}"
    return True, f"all {len(matching_sections)} sections have '{required[:30]}'"


# ── Contract JSON Helpers ────────────────────────────────────────────

SCALAR_TYPES = (str, int, float, bool)
JSONPATH_SEGMENT_RE = re.compile(
    r"""
    (?:
        \.([A-Za-z_][A-Za-z0-9_-]*) |
        \[(\*)\] |
        \[(\d+)\] |
        \[\?\((.+?)\)\]
    )
    """,
    re.VERBOSE,
)
FILTER_CLAUSE_RE = re.compile(
    r"""@\.([A-Za-z_][A-Za-z0-9_-]*)\s*==\s*("(?:[^"\\]|\\.)*"|true|false|-?\d+)"""
)


def resolve_base_dir(eval_path: Path, skill_dir: Path | None) -> Path:
    if skill_dir is not None:
        return skill_dir.resolve()
    return eval_path.parent.resolve()


def resolve_rule_path(base_dir: Path, current_output_path: Path, raw_path: str) -> Path:
    path = Path(raw_path)
    if path.is_absolute():
        return path.resolve()
    candidate = (current_output_path.parent / path).resolve()
    if candidate.exists():
        return candidate
    return (base_dir / path).resolve()


def load_json_path(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"JSON file not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in {path}: {exc}") from exc


def normalize_ws(value: str) -> str:
    return " ".join(value.split())


def parse_filter_value(raw_value: str) -> Any:
    if raw_value == "true":
        return True
    if raw_value == "false":
        return False
    if raw_value.startswith('"'):
        return json.loads(raw_value)
    return int(raw_value)


def evaluate_filter_clause(item: Any, clause_text: str) -> bool:
    if not isinstance(item, dict):
        return False
    match = FILTER_CLAUSE_RE.fullmatch(clause_text.strip())
    if not match:
        raise ValueError(f"unsupported JSONPath filter clause: {clause_text}")
    field_name, raw_value = match.groups()
    return item.get(field_name) == parse_filter_value(raw_value)


def evaluate_filter_expr(item: Any, expr: str) -> bool:
    or_clauses = [part.strip() for part in expr.split("||")]
    for or_clause in or_clauses:
        and_clauses = [part.strip() for part in or_clause.split("&&")]
        if all(evaluate_filter_clause(item, clause) for clause in and_clauses):
            return True
    return False


def select_json_path(document: Any, path: str) -> list[Any]:
    if path == "$":
        return [document]
    if not path.startswith("$"):
        raise ValueError(f"JSONPath must start with '$': {path}")

    current = [document]
    position = 1
    while position < len(path):
        match = JSONPATH_SEGMENT_RE.match(path, position)
        if match is None:
            raise ValueError(f"unsupported JSONPath syntax near: {path[position:]}")
        field_name, wildcard, index_value, filter_expr = match.groups()
        next_values: list[Any] = []
        if field_name is not None:
            for node in current:
                if not isinstance(node, dict):
                    raise ValueError(f"JSONPath segment '.{field_name}' expected object")
                if field_name in node:
                    next_values.append(node[field_name])
        elif wildcard is not None:
            for node in current:
                if not isinstance(node, list):
                    raise ValueError("JSONPath wildcard expected array")
                next_values.extend(node)
        elif index_value is not None:
            index = int(index_value)
            for node in current:
                if not isinstance(node, list):
                    raise ValueError(f"JSONPath index [{index}] expected array")
                if index < len(node):
                    next_values.append(node[index])
        else:
            for node in current:
                if not isinstance(node, list):
                    raise ValueError("JSONPath filter expected array")
                for item in node:
                    if evaluate_filter_expr(item, filter_expr):
                        next_values.append(item)
        current = next_values
        position = match.end()
    return current


def selection_count(values: list[Any]) -> int:
    if len(values) == 1 and isinstance(values[0], list):
        return len(values[0])
    return len(values)


def scalar_values(values: list[Any], label: str) -> list[Any]:
    scalars: list[Any] = []
    for value in values:
        if not isinstance(value, SCALAR_TYPES):
            raise ValueError(f"{label} selected non-scalar value")
        scalars.append(value)
    return scalars


def validate_span_against_file(span: dict[str, Any], fixture_path: Path, require_unique: bool) -> None:
    try:
        fixture_text = fixture_path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise ValueError(f"fixture not found: {fixture_path}") from exc

    required_fields = ("start_line", "end_line", "old_text", "new_text")
    for field_name in required_fields:
        if field_name not in span:
            raise ValueError(f"replace_span missing field '{field_name}'")

    start_line = span["start_line"]
    end_line = span["end_line"]
    old_text = span["old_text"]
    new_text = span["new_text"]
    if not isinstance(start_line, int) or not isinstance(end_line, int):
        raise ValueError("replace_span line bounds must be integers")
    if not isinstance(old_text, str) or not isinstance(new_text, str):
        raise ValueError("replace_span text fields must be strings")
    if start_line < 1 or end_line < start_line:
        raise ValueError("replace_span line bounds are invalid")

    line_slice = fixture_text.splitlines()
    if end_line > len(line_slice):
        raise ValueError("replace_span line bounds exceed fixture length")

    match_count = fixture_text.count(old_text)
    if require_unique and match_count != 1:
        raise ValueError("replace_span old_text does not resolve to one unique target slice")
    if match_count == 0:
        raise ValueError("replace_span old_text not found in fixture")

    actual_slice = "\n".join(line_slice[start_line - 1:end_line])
    if actual_slice != old_text:
        raise ValueError("replace_span old_text mismatch at declared line range")
    if normalize_ws(old_text) == normalize_ws(new_text):
        raise ValueError("replace_span new_text is a no-op after normalization")


def validate_json_schema(output_path: Path, output_json: Any, schema_path: Path) -> tuple[bool, str]:
    schema = load_json_path(schema_path)
    if not isinstance(schema, dict):
        raise ValueError(f"schema must be a JSON object: {schema_path}")
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(output_json), key=lambda error: list(error.absolute_path))
    if errors:
        first = errors[0]
        location = ".".join(str(part) for part in first.absolute_path) or "<root>"
        return False, f"{output_path.name} schema validation failed at {location}: {first.message}"
    return True, f"{output_path.name} matches schema {schema_path.name}"


def match_scalar(value: Any, rule: dict[str, Any], label: str) -> bool:
    if "pattern" in rule:
        if not isinstance(value, str):
            raise ValueError(f"{label} requires string values for pattern matching")
        flags = re.IGNORECASE if rule.get("ignore_case", False) else 0
        return re.search(rule["pattern"], value, flags) is not None
    if "value" in rule:
        return value == rule["value"]
    raise ValueError(f"{label} requires either 'pattern' or 'value'")


def eval_json_field_match(output_json: Any, rule: dict[str, Any]) -> tuple[bool, str]:
    path = rule["path"]
    values = scalar_values(select_json_path(output_json, path), "json_field_match")
    if not values:
        return False, f"no values matched {path}"
    matched = [value for value in values if match_scalar(value, rule, "json_field_match")]
    match_mode = rule.get("match_mode", "all")
    if match_mode not in {"all", "any"}:
        raise ValueError("json_field_match match_mode must be 'all' or 'any'")
    if match_mode == "all":
        if len(matched) != len(values):
            return False, f"{len(matched)}/{len(values)} selected values matched at {path}"
        return True, f"all {len(values)} selected values matched at {path}"
    if not matched:
        return False, f"no selected values matched at {path}"
    return True, f"{len(matched)}/{len(values)} selected values matched at {path}"


def eval_json_field_not_match(output_json: Any, rule: dict[str, Any]) -> tuple[bool, str]:
    path = rule["path"]
    values = select_json_path(output_json, path)
    if not values:
        return True, f"no values matched {path}"

    if "compare_fields" in rule:
        compare_fields = rule["compare_fields"]
        if not isinstance(compare_fields, dict):
            raise ValueError("compare_fields must be an object")
        left_field = compare_fields.get("left")
        right_field = compare_fields.get("right")
        if not isinstance(left_field, str) or not isinstance(right_field, str):
            raise ValueError("compare_fields requires string left/right field names")
        normalize = bool(rule.get("normalize_whitespace", False))
        violations = 0
        for value in values:
            if not isinstance(value, dict):
                raise ValueError("json_field_not_match compare_fields selected non-object value")
            left_value = value.get(left_field)
            right_value = value.get(right_field)
            if not isinstance(left_value, str) or not isinstance(right_value, str):
                raise ValueError("json_field_not_match compare_fields requires string field values")
            if normalize:
                left_value = normalize_ws(left_value)
                right_value = normalize_ws(right_value)
            if left_value == right_value:
                violations += 1
        if violations:
            return False, f"{violations} selected object(s) matched forbidden field comparison at {path}"
        return True, f"no selected objects matched forbidden field comparison at {path}"

    scalars = scalar_values(values, "json_field_not_match")
    violations = [value for value in scalars if match_scalar(value, rule, "json_field_not_match")]
    if violations:
        return False, f"{len(violations)} selected value(s) matched forbidden value at {path}"
    return True, f"no selected values matched forbidden value at {path}"


def eval_json_array_count_bounds(output_json: Any, rule: dict[str, Any]) -> tuple[bool, str]:
    path = rule["path"]
    values = select_json_path(output_json, path)
    count = selection_count(values)
    minimum = rule.get("min")
    maximum = rule.get("max")
    if minimum is not None and count < minimum:
        return False, f"{path} count {count} is below minimum {minimum}"
    if maximum is not None and count > maximum:
        return False, f"{path} count {count} exceeds maximum {maximum}"
    return True, f"{path} count {count} is within bounds"


def eval_json_unique_field(output_json: Any, rule: dict[str, Any]) -> tuple[bool, str]:
    path = rule["path"]
    values = scalar_values(select_json_path(output_json, path), "json_unique_field")
    if len(values) != len(set(values)):
        return False, f"duplicate values found at {path}"
    return True, f"all {len(values)} values are unique at {path}"


def eval_json_cross_ref_exists(
    output_json: Any,
    rule: dict[str, Any],
    current_output_path: Path,
    base_dir: Path,
) -> tuple[bool, str]:
    source_payload = output_json
    if "source_path" in rule:
        source_payload = load_json_path(resolve_rule_path(base_dir, current_output_path, rule["source_path"]))
    target_payload = load_json_path(resolve_rule_path(base_dir, current_output_path, rule["target_path"]))
    source_values = scalar_values(
        select_json_path(source_payload, rule["source_json_path"]),
        "json_cross_ref_exists source",
    )
    target_values_list = scalar_values(
        select_json_path(target_payload, rule["target_json_path"]),
        "json_cross_ref_exists target",
    )
    if len(target_values_list) != len(set(target_values_list)):
        raise ValueError("json_cross_ref_exists target lookup values must be unique")
    target_values = set(target_values_list)
    missing = [value for value in source_values if value not in target_values]
    if missing:
        return False, f"missing cross-reference target(s): {', '.join(map(str, missing[:3]))}"
    return True, f"all {len(source_values)} cross-reference value(s) resolved"


def eval_json_cross_ref_match(
    output_json: Any,
    rule: dict[str, Any],
    current_output_path: Path,
    base_dir: Path,
) -> tuple[bool, str]:
    source_payload = output_json
    if "source_path" in rule:
        source_payload = load_json_path(resolve_rule_path(base_dir, current_output_path, rule["source_path"]))
    target_payload = load_json_path(resolve_rule_path(base_dir, current_output_path, rule["target_path"]))
    source_records = select_json_path(source_payload, rule["source_records_path"])
    target_records = select_json_path(target_payload, rule["target_records_path"])
    if not all(isinstance(record, dict) for record in source_records + target_records):
        raise ValueError("json_cross_ref_match requires object records")

    source_lookup = rule["source_lookup_field"]
    target_lookup = rule["target_lookup_field"]
    field_map = rule["field_map"]
    if not isinstance(field_map, dict):
        raise ValueError("json_cross_ref_match field_map must be an object")

    target_index = {
        record[target_lookup]: record
        for record in target_records
        if target_lookup in record
    }
    if len(target_index) != len(target_records):
        raise ValueError("json_cross_ref_match target lookup values must be unique")
    mismatches: list[str] = []
    for record in source_records:
        lookup_value = record.get(source_lookup)
        if lookup_value not in target_index:
            mismatches.append(f"{lookup_value}: missing target record")
            continue
        target_record = target_index[lookup_value]
        for source_field, target_field in field_map.items():
            if record.get(source_field) != target_record.get(target_field):
                mismatches.append(f"{lookup_value}: {source_field}!={target_field}")
                break
    if mismatches:
        return False, "cross-ref field mismatches: " + ", ".join(mismatches[:3])
    return True, f"all {len(source_records)} cross-reference record(s) matched"


def eval_resolved_span_exists(
    output_json: Any,
    rule: dict[str, Any],
    current_output_path: Path,
    base_dir: Path,
) -> tuple[bool, str]:
    path = rule["path"]
    spans = select_json_path(output_json, path)
    if not spans:
        return True, f"no spans selected at {path}"
    fixture_path_raw = rule["fixture_path"]
    snapshot_path_raw = rule.get("snapshot_path")
    if "fixtures/snapshot/" in fixture_path_raw.replace("\\", "/") and not snapshot_path_raw:
        raise ValueError(
            f"eval.json error: snapshot fixture {fixture_path_raw} requires snapshot_path in resolved_span_exists rule"
        )
    fixture_path = resolve_rule_path(base_dir, current_output_path, fixture_path_raw)
    if rule.get("require_unique") is False:
        raise ValueError("resolved_span_exists requires unique exact target resolution")
    require_unique = bool(rule.get("require_unique", True))
    for span in spans:
        if not isinstance(span, dict):
            raise ValueError("resolved_span_exists selected non-object replace_span")
        validate_span_against_file(span, fixture_path, require_unique)
        if snapshot_path_raw:
            snapshot_path = resolve_rule_path(base_dir, current_output_path, snapshot_path_raw)
            validate_span_against_file(span, snapshot_path, require_unique)
    return True, f"validated {len(spans)} replace_span target(s)"


def validate_eval_config(eval_config: dict[str, Any], base_dir: Path | None = None) -> None:
    tests = eval_config.get("tests", [])
    if not isinstance(tests, list):
        raise ValueError("eval.json must contain a tests array")
    for test in tests:
        if not isinstance(test, dict):
            raise ValueError("eval.json contains a non-object test entry")
        assertions = test.get("assertions", [])
        if not isinstance(assertions, list):
            raise ValueError(f"eval.json test '{test.get('id', '<unknown>')}' assertions must be an array")
        for assertion in assertions:
            if not isinstance(assertion, dict):
                raise ValueError("eval.json contains a non-object assertion")
            rule = assertion.get("rule")
            if not isinstance(rule, dict):
                continue
            rule_type = rule.get("type")
            if rule_type == "resolved_span_exists":
                fixture_path = rule.get("fixture_path")
                if not isinstance(fixture_path, str) or not fixture_path.strip():
                    raise ValueError("resolved_span_exists requires fixture_path")
                if rule.get("require_unique") is False:
                    raise ValueError("resolved_span_exists requires unique exact target resolution")
                if "fixtures/snapshot/" in fixture_path.replace("\\", "/") and not rule.get("snapshot_path"):
                    raise ValueError(
                        f"eval.json error: snapshot fixture {fixture_path} requires snapshot_path in resolved_span_exists rule"
                    )
                if base_dir is not None:
                    target_path = (base_dir / fixture_path).resolve()
                    if target_path.name == ".gitkeep":
                        raise ValueError("resolved_span_exists cannot target .gitkeep")


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


def evaluate_assertion(
    output: str,
    assertion: dict[str, Any],
    *,
    output_path: Path,
    base_dir: Path,
) -> dict[str, Any]:
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
        result["passed"] = None
        result["method"] = "needs_review"
        result["reason"] = "no programmatic rule defined — requires manual evaluation"
        return result

    rule_type = rule.get("type", "")
    try:
        if rule_type in RULE_EVALUATORS:
            raw_passed, reason = RULE_EVALUATORS[rule_type](output, rule)
        else:
            output_json = load_json_path(output_path)
            if rule_type == "json_schema_valid":
                schema_path = resolve_rule_path(base_dir, output_path, rule["schema_path"])
                raw_passed, reason = validate_json_schema(output_path, output_json, schema_path)
            elif rule_type == "json_field_match":
                raw_passed, reason = eval_json_field_match(output_json, rule)
            elif rule_type == "json_array_count_bounds":
                raw_passed, reason = eval_json_array_count_bounds(output_json, rule)
            elif rule_type == "resolved_span_exists":
                raw_passed, reason = eval_resolved_span_exists(output_json, rule, output_path, base_dir)
            elif rule_type == "json_field_not_match":
                raw_passed, reason = eval_json_field_not_match(output_json, rule)
            elif rule_type == "json_cross_ref_exists":
                raw_passed, reason = eval_json_cross_ref_exists(output_json, rule, output_path, base_dir)
            elif rule_type == "json_cross_ref_match":
                raw_passed, reason = eval_json_cross_ref_match(output_json, rule, output_path, base_dir)
            elif rule_type == "json_unique_field":
                raw_passed, reason = eval_json_unique_field(output_json, rule)
            else:
                raise ValueError(f"unknown rule type: '{rule_type}' — check eval.json for typos")

        passed = raw_passed if expected else not raw_passed
        result["passed"] = passed
        result["method"] = "programmatic"
        result["reason"] = reason
    except Exception as exc:
        result["passed"] = False
        result["method"] = "error"
        result["reason"] = str(exc)

    return result


# ── Test Runner ──────────────────────────────────────────────────────

def resolve_test_output_file(output_dir: Path, test: dict[str, Any]) -> Path:
    output_file = test.get("output_file")
    if isinstance(output_file, str) and output_file.strip():
        return (output_dir / output_file).resolve()

    test_id = test["id"]
    markdown_path = output_dir / f"{test_id}.md"
    if markdown_path.exists():
        return markdown_path
    return output_dir / f"{test_id}.txt"


def run_evaluation(
    eval_config: dict[str, Any],
    output_dir: Path,
    *,
    verbose: bool = False,
    eval_path: Path | None = None,
    skill_dir: Path | None = None,
) -> dict[str, Any]:
    output_dir = output_dir.resolve()
    tests = eval_config.get("tests", [])
    base_dir = resolve_base_dir(eval_path or output_dir, skill_dir)
    validate_eval_config(eval_config, base_dir)

    declared = eval_config.get("total_assertions")
    if declared is not None:
        actual = sum(len(test.get("assertions", [])) for test in tests)
        if declared != actual:
            print(
                f"{YELLOW}WARNING: eval.json total_assertions={declared} but "
                f"actual count={actual} — update the metadata field{NC}"
            )

    all_results: list[dict[str, Any]] = []
    total_passed = 0
    total_assertions = 0
    total_needs_review = 0
    missing_output_tests = 0

    for test in tests:
        test_id = test["id"]
        test_name = test.get("name", "")
        assertions = test.get("assertions", [])
        output_file = resolve_test_output_file(output_dir, test)

        if not output_file.exists():
            missing_output_tests += 1
            test_result = {
                "id": test_id,
                "name": test_name,
                "status": "missing_output",
                "passed": 0,
                "total": len(assertions),
                "needs_review": 0,
                "assertions": [],
            }
            for assertion in assertions:
                test_result["assertions"].append({
                    "id": assertion["id"],
                    "check": assertion.get("check", ""),
                    "passed": False,
                    "method": "missing_output",
                    "reason": f"output file not found: {output_file.relative_to(output_dir)}",
                })
            total_assertions += len(assertions)
            all_results.append(test_result)
            if verbose:
                print(f"  {YELLOW}[{test_id}]{NC} {test_name} — output file missing")
            continue

        output_text = output_file.read_text(encoding="utf-8")
        assertion_results: list[dict[str, Any]] = []
        test_passed = 0
        test_needs_review = 0

        for assertion in assertions:
            assertion_result = evaluate_assertion(
                output_text,
                assertion,
                output_path=output_file,
                base_dir=base_dir,
            )
            assertion_results.append(assertion_result)

            if assertion_result["passed"] is True:
                test_passed += 1
                total_passed += 1
            elif assertion_result["passed"] is None:
                test_needs_review += 1
                total_needs_review += 1

            total_assertions += 1

            if verbose:
                if assertion_result["passed"] is True:
                    status_icon = f"{GREEN}PASS{NC}"
                elif assertion_result["passed"] is False:
                    status_icon = f"{RED}FAIL{NC}"
                else:
                    status_icon = f"{YELLOW}REVIEW{NC}"
                print(f"    [{status_icon}] {assertion_result['id']}: {assertion_result['check'][:60]}")
                if assertion_result["passed"] is False or assertion_result["passed"] is None:
                    print(f"           {assertion_result['reason']}")

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

    evaluated = total_assertions - total_needs_review
    score = total_passed / evaluated if evaluated > 0 else 0.0
    return {
        "score": round(score, 4),
        "passed": total_passed,
        "total": total_assertions,
        "evaluated": evaluated,
        "needs_review": total_needs_review,
        "missing_outputs": missing_output_tests,
        "tests": all_results,
    }


# ── Main ─────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Evaluate skill outputs against binary assertions"
    )
    parser.add_argument("--eval", required=True, help="Path to eval.json")
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory containing output files or per-fixture output subdirectories",
    )
    parser.add_argument(
        "--skill-dir",
        default=None,
        help="Base directory for relative schema/fixture paths",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Show per-assertion results")
    parser.add_argument("--json", action="store_true", help="Output results as JSON")
    args = parser.parse_args()

    eval_path = Path(args.eval)
    output_dir = Path(args.output_dir)
    skill_dir = Path(args.skill_dir) if args.skill_dir is not None else None

    if not eval_path.exists():
        print(f"{RED}FAIL: eval.json not found: {eval_path}{NC}", file=sys.stderr)
        sys.exit(2)
    if not output_dir.exists():
        print(f"{RED}FAIL: output directory not found: {output_dir}{NC}", file=sys.stderr)
        sys.exit(2)

    try:
        eval_config = json.loads(eval_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"{RED}FAIL: invalid eval.json: {exc}{NC}", file=sys.stderr)
        sys.exit(2)

    try:
        results = run_evaluation(
            eval_config,
            output_dir,
            verbose=args.verbose,
            eval_path=eval_path,
            skill_dir=skill_dir,
        )
    except ValueError as exc:
        print(f"{RED}FAIL: {exc}{NC}", file=sys.stderr)
        sys.exit(2)

    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print()
        score_color = GREEN if results["score"] >= 0.9 else (YELLOW if results["score"] >= 0.7 else RED)
        print(f"  {BOLD}Score:{NC}         {score_color}{results['score']:.1%}{NC} ({results['passed']}/{results['evaluated']} programmatic)")
        if results["needs_review"] > 0:
            print(f"  {BOLD}Needs review:{NC} {YELLOW}{results['needs_review']}{NC} assertions without programmatic rules")
        if results["missing_outputs"] > 0:
            print(f"  {BOLD}Missing output files:{NC} {RED}{results['missing_outputs']}{NC} test(s)")
        print()
        for test in results["tests"]:
            if test["status"] == "missing_output":
                print(f"  {YELLOW}[{test['id']}]{NC} {test['name']} — output missing")
                continue
            color = GREEN if test["passed"] == test["total"] else RED
            print(f"  {color}[{test['id']}] {NC}{test['name']} — {test['passed']}/{test['total']}")
            for assertion in test["assertions"]:
                if assertion["passed"] is False:
                    print(f"       {RED}x {assertion['id']}: {assertion['reason']}{NC}")
        print()

    if results["missing_outputs"] > 0:
        sys.exit(1)
    sys.exit(0 if results["score"] >= 1.0 else 1)


if __name__ == "__main__":
    main()
