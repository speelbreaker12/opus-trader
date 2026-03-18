# Cross-Reference Validator Design
## Automated Traceability Between Contract, Roadmap, and PRD

**Version:** 1.0  
**Status:** Design Phase  
**Target Integration:** `plans/verify.sh` preflight gate

---

## 1. Purpose

Prevent drift between canonical sources by enforcing:
- **Every** contract requirement has implementation coverage
- **Every** roadmap milestone has PRD stories
- **Every** PRD reference points to valid contract/roadmap items
- **No** orphaned or stale references exist

---

## 2. Validation Matrix

### 2.1 Cross-Reference Types to Validate

| From | To | Validation Rule | Criticality |
|------|----|-----------------|-------------|
| PRD `contract_refs` | Contract AT-### | AT must exist in contract | BLOCKING |
| PRD `contract_refs` | Contract anchors | Anchor must exist | BLOCKING |
| PRD `plan_refs` | IMPLEMENTATION_PLAN slices | Slice must exist | WARNING |
| PRD `enforcing_contract_ats` | Contract AT-### | AT must exist | BLOCKING |
| Roadmap Phase Exit | PRD stories | All criteria have stories | WARNING |
| Contract ATs | PRD coverage | Every AT referenced ≥1 story | WARNING |
| PRD `observability.status_contract_ats` | Contract AT-### | AT must exist | BLOCKING |
| Contract Appendix A defaults | PRD test mapping | Default has test alias | WARNING |

### 2.2 Reference Syntax Standards

```
Contract AT refs:     "AT-###" or "AT-### (description)"
Contract anchors:     "Anchor-###" or "Anchor-### (description)"
Contract sections:    "§X.Y" or "CONTRACT.md §X.Y"
Implementation refs:  "Slice N", "S{N}-{###}", "PL-{N}"
Roadmap refs:         "Phase N", "P{N}-{A-Z}"
```

---

## 3. Technical Architecture

### 3.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    crossref_validator.py                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │   Parser    │  │   Indexer   │  │    Validator Engine     │  │
│  │   Module    │→ │   Module    │→ │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
│         ↓                ↓                      ↓               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Contract MD │  │ Reference   │  │   Report Generator      │  │
│  │   Parser    │  │   Graph     │  │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                    ┌─────────────────┐
                    │  validation.json │
                    │   (artifacts)    │
                    └─────────────────┘
```

### 3.2 Parser Module Specifications

#### Contract Parser (`parsers/contract_parser.py`)
**Input:** `specs/CONTRACT.md`
**Output:** `contract_index.json`

```json
{
  "version": "5.2",
  "ats": {
    "AT-001": {
      "section": "2.2.1.1",
      "profile": "CSP",
      "title": "PolicyGuard Critical Input Freshness",
      "line_start": 1884,
      "line_end": 1890
    }
  },
  "anchors": {
    "Anchor-021": {
      "section": "7.0",
      "title": "Status Endpoint Required Fields"
    }
  },
  "sections": {
    "2.2.1.1": {
      "title": "PolicyGuard Critical Input Freshness",
      "ats": ["AT-001", "AT-112"]
    }
  },
  "profiles": {
    "CSP": ["AT-001", "AT-104", ...],
    "GOP": ["AT-005", "AT-105", ...]
  }
}
```

#### Roadmap Parser (`parsers/roadmap_parser.py`)
**Input:** `docs/ROADMAP.md`, `docs/PHASE{0,1}_CHECKLIST_BLOCK.md`
**Output:** `roadmap_index.json`

```json
{
  "phases": {
    "0": {
      "status": "COMPLETE",
      "checklist_items": ["P0-A", "P0-B", "P0-C", "P0-D", "P0-E", "P0-F"],
      "exit_criteria": [...],
      "evidence_required": [...]
    },
    "1": {
      "status": "IN_PROGRESS",
      "checklist_items": ["P1-A", "P1-B", "P1-C", "P1-D", "P1-E", "P1-F", "P1-G"],
      "evidence_required": [
        "evidence/phase1/restart_loop/restart_100_cycles.log",
        "evidence/phase1/determinism/intent_hashes.txt"
      ]
    }
  },
  "checklist_items": {
    "P1-A": {
      "phase": 1,
      "title": "Single Dispatch Chokepoint Proof",
      "requires_auto": true,
      "requires_manual": true,
      "evidence_paths": ["docs/dispatch_chokepoint.md"]
    }
  }
}
```

#### PRD Parser (`parsers/prd_parser.py`)
**Input:** `plans/prd.json`
**Output:** `prd_index.json`

```json
{
  "stories": {
    "S1-001": {
      "phase": 1,
      "slice": 1,
      "passes": true,
      "contract_refs": ["AT-905"],
      "enforcing_contract_ats": ["AT-905"],
      "evidence": ["cargo test output"]
    }
  },
  "coverage_map": {
    "AT-905": ["S1-001"]
  },
  "orphaned_refs": [],
  "unreferenced_ats": ["AT-XXX"]
}
```

### 3.3 Validation Rules Engine

```python
class ValidationRules:
    """Deterministic validation rule implementations."""
    
    RULES = {
        "R1": {
            "name": "prd_contract_ref_exists",
            "severity": "BLOCKING",
            "description": "Every PRD contract_refs entry must resolve to existing AT or anchor"
        },
        "R2": {
            "name": "prd_enforcing_at_coverage",
            "severity": "BLOCKING", 
            "description": "Every PRD enforcing_contract_ats must exist in contract"
        },
        "R3": {
            "name": "roadmap_evidence_has_story",
            "severity": "WARNING",
            "description": "Every roadmap evidence requirement should have implementing story"
        },
        "R4": {
            "name": "contract_at_has_coverage",
            "severity": "WARNING",
            "description": "Every CSP-profile AT should be referenced by at least one story"
        },
        "R5": {
            "name": "implementation_plan_refs_valid",
            "severity": "WARNING",
            "description": "PRD plan_refs should reference valid implementation plan slices"
        },
        "R6": {
            "name": "slice_consistency",
            "severity": "BLOCKING",
            "description": "Story slice_ref should match actual slice in plan_refs"
        }
    }
```

---

## 4. Implementation Phases

### Phase 1: Indexers (Week 1)
**Goal:** Create parsers that extract structured data from each source

**Deliverables:**
- `tools/crossref/parsers/contract_parser.py` - Extract ATs, anchors, sections
- `tools/crossref/parsers/roadmap_parser.py` - Extract phases, checklist items
- `tools/crossref/parsers/prd_parser.py` - Extract story references
- Unit tests for each parser with fixtures

**Acceptance Criteria:**
- Contract parser extracts 100% of AT-### patterns
- Roadmap parser extracts all P{N}-{X} checklist items
- PRD parser handles all current JSON schema fields

### Phase 2: Core Validator (Week 2)
**Goal:** Build the validation engine that cross-references indices

**Deliverables:**
- `tools/crossref/validator.py` - Main validation orchestrator
- `tools/crossref/rules.py` - Rule implementations
- `tools/crossref/reports.py` - Report generators

**Acceptance Criteria:**
- Detects orphaned PRD contract_refs (test with fake AT)
- Detects unreferenced CSP ATs (test with synthetic index)
- Generates structured JSON report

### Phase 3: Integration (Week 3)
**Goal:** Wire into existing workflow

**Deliverables:**
- `plans/crossref_check.sh` - Shell wrapper following existing pattern
- Integration with `plans/preflight.sh` (blocking for R1/R2)
- Integration with `plans/verify.sh` (warning mode initially)
- CI workflow updates

**Acceptance Criteria:**
- Preflight fails on orphaned BLOCKING references
- Verify outputs report in `artifacts/verify/{run_id}/crossref_report.json`

### Phase 4: Dashboard & Automation (Week 4)
**Goal:** Make traceability visible and actionable

**Deliverables:**
- Coverage dashboard (markdown or HTML)
- Gap reports showing unimplemented ATs
- Automated PR comments for new orphaned refs

---

## 5. Report Format

### 5.1 Machine-Readable Output

```json
{
  "schema_version": "1.0",
  "run_id": "20260212_120000",
  "summary": {
    "total_stories": 73,
    "total_ats": 187,
    "referenced_ats": 142,
    "unreferenced_ats": 45,
    "orphaned_refs": 0,
    "blocking_issues": 0,
    "warnings": 3
  },
  "violations": [
    {
      "rule": "R1",
      "severity": "BLOCKING",
      "story_id": "S9-999",
      "field": "contract_refs",
      "value": "AT-9999",
      "message": "AT-9999 not found in contract index",
      "suggestion": "Check contract version or remove stale reference"
    }
  ],
  "gaps": [
    {
      "type": "unreferenced_csp_at",
      "at": "AT-XXX",
      "section": "2.2.3",
      "profile": "CSP",
      "severity": "HIGH",
      "message": "CSP-profile AT has no implementing story"
    },
    {
      "type": "roadmap_evidence_missing_story",
      "phase": 1,
      "evidence": "evidence/phase1/restart_loop/restart_100_cycles.log",
      "message": "No PRD story produces this artifact"
    }
  ],
  "coverage": {
    "phase_0": {
      "required_ats": 25,
      "covered_ats": 25,
      "coverage_pct": 100
    },
    "phase_1": {
      "required_ats": 60,
      "covered_ats": 48,
      "coverage_pct": 80
    }
  }
}
```

### 5.2 Human-Readable Output

```markdown
# Cross-Reference Validation Report
Run: 2026-02-12T12:00:00Z

## Summary
✅ No blocking issues  
⚠️  3 warnings

## Coverage by Phase
| Phase | ATs Required | ATs Covered | % |
|-------|-------------|-------------|---|
| Phase 0 | 25 | 25 | 100% ✅ |
| Phase 1 | 60 | 48 | 80% ⚠️ |

## Warnings
### Unreferenced CSP ATs (HIGH priority)
- AT-1048 (Axis Resolver Enumerability) - Add to PolicyGuard slice
- AT-1053 (Axis Resolver Monotonicity) - Add to PolicyGuard slice

### Roadmap Evidence Gaps
- evidence/phase1/restart_loop/restart_100_cycles.log
  - Required by ROADMAP.md Phase 1 Exit
  - No producing PRD story found
  - Suggestion: Add story S1-EVIDENCE-003
```

---

## 6. Configuration

### 6.1 Config File: `config/crossref.yaml`

```yaml
validation:
  # Which rules to enforce
  rules:
    R1: { enabled: true, severity: blocking }
    R2: { enabled: true, severity: blocking }
    R3: { enabled: true, severity: warning }
    R4: { enabled: true, severity: warning }
    R5: { enabled: false, severity: info }  # PL refs optional for now
    R6: { enabled: true, severity: blocking }

  # Profile prioritization
  profiles:
    CSP: { require_coverage: true }
    GOP: { require_coverage: false }  # GOP features optional

  # Phase-specific thresholds
  phase_coverage:
    phase_0: { min_pct: 100, required_ats: all }
    phase_1: { min_pct: 90, required_ats: all_csp }
    phase_2: { min_pct: 80, required_ats: all_csp }

  # Exclusions (for legacy/in-progress work)
  exclude_ats:
    - "AT-9999"  # Reserved for future
  exclude_stories:
    - "S9-999"   # Placeholder

paths:
  contract: specs/CONTRACT.md
  roadmap: docs/ROADMAP.md
  phase_checklists:
    - docs/PHASE0_CHECKLIST_BLOCK.md
    - docs/PHASE1_CHECKLIST_BLOCK.md
  prd: plans/prd.json
  implementation_plan: specs/IMPLEMENTATION_PLAN.md
  output_dir: artifacts/crossref
```

---

## 7. Integration Points

### 7.1 Preflight Gate (Blocking)

```bash
# plans/preflight.sh (addition)

phase "Cross-Reference Validation"
run_check "Cross-reference index build" \
  python3 tools/crossref/build_index.py --output artifacts/crossref/index.json

run_check "Cross-reference validation (blocking rules only)" \
  python3 tools/crossref/validate.py \
    --index artifacts/crossref/index.json \
    --config config/crossref.yaml \
    --severity blocking \
    --output artifacts/crossref/validation_blocking.json

if [[ -s artifacts/crossref/validation_blocking.json ]]; then
  fail "Cross-reference violations found (see artifacts/crossref/)"
fi
```

### 7.2 Verify Gate (Warning + Report)

```bash
# plans/verify_fork.sh (addition in appropriate section)

run_gate "Cross-Reference Coverage" {
  log_info "Running full cross-reference validation..."
  python3 tools/crossref/validate.py \
    --index artifacts/crossref/index.json \
    --config config/crossref.yaml \
    --severity all \
    --output artifacts/verify/${RUN_ID}/crossref_report.json \
    --html artifacts/verify/${RUN_ID}/crossref_report.html
  
  # Non-blocking but reported
  log_info "Cross-reference report: artifacts/verify/${RUN_ID}/crossref_report.html"
}
```

### 7.3 PR Integration (Future)

```yaml
# .github/workflows/crossref.yml (future)
name: Cross-Reference Check
on: [pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run crossref validation
        run: python3 tools/crossref/validate.py --format github-annotations
      - name: Comment PR
        uses: actions/github-script@v6
        with:
          script: |
            const report = require('./artifacts/crossref/report.json');
            // Post coverage summary as PR comment
```

---

## 8. Testing Strategy

### 8.1 Fixture-Based Tests

```python
# tools/crossref/tests/test_validator.py

class TestCrossRefValidator:
    def test_detects_orphaned_contract_ref(self):
        # Given: PRD referencing non-existent AT
        prd = {"S1-999": {"contract_refs": ["AT-NONEXISTENT"]}}
        contract = {"ats": {}}
        
        # When: Validate
        result = validate(prd, contract)
        
        # Then: Violation reported
        assert len(result.violations) == 1
        assert result.violations[0]["rule"] == "R1"
    
    def test_detects_unreferenced_csp_at(self):
        # Given: CSP AT not referenced by any story
        contract = {"ats": {"AT-001": {"profile": "CSP"}}}
        prd = {}  # No stories
        
        # When: Validate
        result = validate(prd, contract)
        
        # Then: Gap reported
        assert len(result.gaps) == 1
        assert result.gaps[0]["type"] == "unreferenced_csp_at"
```

### 8.2 Integration Tests

```bash
# tools/crossref/tests/test_integration.sh

test_contract_parsing() {
  python3 tools/crossref/parsers/contract_parser.py \
    --input specs/CONTRACT.md \
    --output /tmp/contract_index.json
  
  # Assert: AT-001 exists
  jq -e '.ats["AT-001"]' /tmp/contract_index.json || fail
  
  # Assert: Known anchor exists
  jq -e '.anchors["Anchor-021"]' /tmp/contract_index.json || fail
}

test_end_to_end_validation() {
  ./plans/crossref_check.sh
  [[ -f artifacts/crossref/validation.json ]] || fail
}
```

---

## 9. Migration Plan

### Current State → Target State

| Step | Action | Duration |
|------|--------|----------|
| 1 | Build contract parser, validate against known ATs | 2 days |
| 2 | Build PRD parser, index current stories | 1 day |
| 3 | Run gap analysis (one-time) to find current orphans | 1 day |
| 4 | Fix existing orphaned refs (cleanup sprint) | 3 days |
| 5 | Enable R1/R2 as warnings in preflight | 1 day |
| 6 | Enable R1/R2 as blocking after cleanup | 1 day |
| 7 | Add R3-R6 as warnings, tune thresholds | 2 days |

---

## 10. Open Questions

1. **Should GOP-profile ATs require coverage?** (Currently optional)
2. **How to handle WIP stories with incomplete refs?** (Exclude list?)
3. **Should implementation plan slice_refs be validated against actual plan structure?**
4. **How to validate "derived" evidence (e.g., restart_100_cycles.log produced by test)?**
5. **Version pinning: Should validator check contract version matches PRD expectation?**

---

## Appendix A: Related Files to Create

```
tools/crossref/
├── __init__.py
├── main.py                    # CLI entry point
├── parsers/
│   ├── __init__.py
│   ├── contract_parser.py     # Contract MD → JSON
│   ├── roadmap_parser.py      # Roadmap MD → JSON
│   ├── prd_parser.py          # PRD JSON → normalized
│   └── implementation_parser.py
├── rules.py                   # Validation rule implementations
├── validator.py               # Orchestration logic
├── reports.py                 # Output formatters
├── tests/
│   ├── fixtures/
│   │   ├── sample_contract.md
│   │   ├── sample_prd.json
│   │   └── sample_roadmap.md
│   ├── test_parsers.py
│   ├── test_rules.py
│   └── test_integration.sh
└── README.md

config/crossref.yaml           # Validation configuration
plans/crossref_check.sh        # Shell wrapper (preflight style)
docs/crossref_validator.md     # User documentation (this file becomes)
```

---

## Appendix B: Command-Line Interface

```bash
# Build indices only
python3 tools/crossref/main.py build-index \
  --output artifacts/crossref/index.json

# Run validation
python3 tools/crossref/main.py validate \
  --index artifacts/crossref/index.json \
  --format json \
  --output artifacts/crossref/validation.json

# Generate coverage report
python3 tools/crossref/main.py report \
  --validation artifacts/crossref/validation.json \
  --format markdown \
  --output artifacts/crossref/report.md

# Check specific story
python3 tools/crossref/main.py check-story S1-001

# One-shot (build + validate + report)
python3 tools/crossref/main.py full-check \
  --output-dir artifacts/crossref
```

---

*End of Design Document*
