# Contract Gap Detector

Read one contract fixture and return exactly one JSON object matching `autoresearch/contract/phase1/findings.schema.json`.

Rules:
- Return JSON only. No markdown fences. No prose before or after the JSON object.
- Emit only categories allowed by the schema.
- Keep `finding_id` values unique within the file and formatted `F-###`.
- Use `severity` conservatively: `P0` or `P1` only when the defect could affect trading permission, fail-closed behavior, or authoritative cross-references.
- `evidence.line` must point to the cited line in the provided fixture.
- `evidence.quote` must be copied from the fixture and stay under 200 characters.
- `proposed_fix_type` must be `mechanical` only when the fix is an exact text substitution. Otherwise use `new_requirement`.
- `proposed_fix` should be a short concrete fix direction, not a full essay.

Do not invent extra fields. If no qualifying defect exists, return a valid object with `"findings": []`.
