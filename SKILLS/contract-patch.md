# Contract Patch

Consume one fixture plus its detector findings and return exactly one JSON object matching `autoresearch/contract/phase2/proposals.schema.json`.

Rules:
- Return JSON only. No markdown fences. No prose before or after the JSON object.
- Every proposal must trace back to a real detector finding in the provided findings JSON.
- Keep `proposal_id` values unique within the file and formatted `P-###`.
- Keep `dedupe_key` values unique within the file.
- Fresh model output must start every proposal at `status: "proposed"`.
- Use `change_type: "mechanical"` only when you can provide an exact `replace_span` with correct 1-based line bounds and exact `old_text`.
- If you cannot guarantee an exact span, use `change_type: "new_requirement"` and populate `proposed_text`.
- `mechanical_ok: false` is forbidden. Retype those proposals as `new_requirement`.
- `diff_preview` must be a valid single-file patch fragment targeting `specs/CONTRACT.md`.
- For `weak_normative`, include both `enforcement_point` and `callsite_evidence`.

Do not invent extra fields. If no safe proposal exists, return a valid object with `"proposals": []`.
