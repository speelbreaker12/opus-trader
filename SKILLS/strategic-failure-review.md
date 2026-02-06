# SKILL: /strategic-failure-review

Purpose
- Find structural and operational problems that survive correct implementations
- **Architectural**: systemic risks, hidden assumptions, compounding failures, maintenance hazards (system-level)
- **Operational**: day-to-day impact, developer ergonomics, privacy, incident response, maintenance burden (human-level)
- Complements `/failure-mode-review` which covers implementation-level failures

When to use
- New subsystems, multi-phase rollouts, infrastructure that adds persistent state or multiple interacting mechanisms
- Changes affecting operator workflows, adding configuration surfaces (env vars, flags)
- Introducing telemetry/data collection
- Impacting developer day-to-day interaction with tooling
- Plans with >5 implementation tickets or >5 new env vars
- Multi-team handoffs or cross-plan coordination

When NOT to use
- Simple caching or state logic (use `/failure-mode-review` instead)
- Single-script changes with no configuration surface
- Implementation-only review (use `/failure-mode-review` instead)

Prerequisite: Run `/failure-mode-review` first. This skill assumes implementation-level analysis is already done.

---

## Architectural Failure Modes

### 1. Architectural Purity Check

Ask: "Does the new mechanism fit the existing architecture, or does it introduce a parallel model?"

- [ ] **Flat vs layered**: If the existing system has a flat model (e.g., all gates are independent named entities with `.rc` files), does the change introduce a grouping/hierarchy that violates that model?
- [ ] **Stateless vs stateful**: If the existing system is stateless (computed fresh each run), does the change add persistent state that can drift?
- [ ] **Single vs dual mechanisms**: Does the change create a second way to achieve the same outcome (e.g., a second skip system alongside an existing one)? If so, specify the interaction model:
  - Which runs first?
  - Which is authoritative on conflict?
  - How does the operator debug "why was X skipped?" across both systems?

Example failure:
```
Existing: change_detection says "skip rust gates" (stateless, per-run)
New:      checkpoint says "skip contract_coverage" (stateful, cached)

Operator asks: "Why didn't contract_coverage run?"
Answer requires checking TWO systems with different semantics.
No unified "skip reason" exists.
```

### 2. Complexity-to-Benefit Ratio

Before accepting a design, quantify what it costs vs what it delivers:

- [ ] **Enumerate the machinery**: Count new env vars, new files, new scripts, new acceptance tests, new rollout modes, new maintenance artifacts.
- [ ] **Enumerate the benefit**: What specific operations get faster/safer, by how much, and how often?
- [ ] **Check the ratio**: If the machinery exceeds the benefit, ask whether a simpler alternative achieves 80% of the value at 10% of the cost.
- [ ] **Check expandability claims**: If the plan justifies complexity by "this will expand to more cases later," verify that the plan's own safety constraints actually allow that expansion.

Example failure:
```
Plan: 12 implementation tickets, 8 new env vars, 30+ acceptance tests,
      4 rollout modes, 2 manifest files, 2 lint scripts
Benefit: skip 2 gates (~14 seconds) in manual quick-mode verify runs
Expansion: plan's own safety constraints prevent adding more gates
Result: highway built for two cars
```

### 3. Hidden Assumptions

Explicitly enumerate assumptions the plan takes for granted. For each, ask "what if this assumption is violated?"

Common hidden assumptions:

| Assumption | Violation | Impact |
|------------|-----------|--------|
| Gates are pure functions of fingerprinted inputs | Tool version changes, Python upgrades, transitive deps | False cache hit — gate would fail but is skipped |
| File name list captures all state changes | File CONTENT changes within existing diff set | Name-hash matches but content differs |
| The fast path is safe to weaken | Developers rely on fast path as primary feedback | Trust erosion: "verify is unreliable" → ignored failures |
| Evidence window proves ongoing correctness | Codebase evolves after evidence collection | Evidence is stale; no continuous validation exists |
| TTL prevents stale cache reuse | Continuous runs refresh TTL before expiry | Cache lives forever under active use |
| Atomic writes prevent all corruption | NFS, Docker overlay, disk-full between open and replace | Non-atomic write on non-POSIX filesystem |
| Cache file is not adversarial | Shared dev machine, CI runner reuse, file permissions | No HMAC/signature; anyone with write access can forge cache |
| `is_ci()` catches all CI environments | Custom CI, Docker without CI=true, developer with CI=false in profile | Skip fires in CI or is blocked on developer machine |

Checklist:
- [ ] For each cached/skipped decision: list ALL inputs that affect the outcome, not just the fingerprinted ones
- [ ] For each "never happens" scenario: what if it does?
- [ ] For each environment assumption: does it hold on NFS, Docker, CI, shared machines?

### 4. Systemic Risks and Emergent Behaviors

These are risks that emerge from component interactions, not from any single component.

#### 4a. Complexity Ratchet

Ask: "Does each safety mechanism justify adding the next one?"

```
Skip logic needs safety → add shared helper
Shared helper needs enforcement → add entrypoint guard
Entrypoint guard needs testing → add acceptance tests
Fingerprint needs completeness → add manifest lint
Manifest lint needs maintenance → add manifest files
Skip needs emergency disable → add kill switch
Kill switch needs rotation → add drill procedure
...
```

- [ ] Is the total debuggable by a single developer?
- [ ] How many decision points must be traced to answer "why was this gate skipped?"
- [ ] Could any layer be removed without meaningfully reducing safety?

#### 4b. Point-in-Time vs Continuous Correctness

- [ ] Does the plan prove correctness once (evidence window) or continuously (ongoing monitoring)?
- [ ] After rollout promotion, is there any mechanism to detect regression?
- [ ] What is the mean time to detect a false skip after it starts occurring?

#### 4c. Dual-Mechanism Interaction

When two independent mechanisms can both skip/route the same gate:

- [ ] Can they disagree? (Mechanism A says run, mechanism B says skip)
- [ ] If they disagree, which wins?
- [ ] Can the disagreement itself be detected and logged?
- [ ] Trace a concrete scenario where they disagree and identify the outcome.

### 5. Compounding Failure Scenarios

Trace multi-step failure chains where failure A enables failure B:

Template:
```
1. [Root cause]: <what goes wrong first>
2. [Propagation]: <how it enables the next failure>
3. [Amplification]: <why it gets worse over time>
4. [Detection gap]: <why nobody notices>
5. [Impact]: <what finally breaks>
```

Common compounding patterns:

| Chain | Example |
|-------|---------|
| Manifest drift + evidence staleness | New validator added → manifest not updated → shadow evidence is stale → enforce promoted → validator never runs |
| Kill switch neglect + TTL refresh loop | Token never rotated → TTL refreshed each run → cache never expires → gate never re-validated |
| Lint bypass + transitive dependency | Lint checks direct env reads → transitive import reads unlinted env var → fingerprint incomplete |
| Safety guard + bash dynamism | Guard uses static `rg` patterns → developer adds dynamic call path → guard passes but invariant is violated |

Checklist:
- [ ] For each safety mechanism: what if it fails silently?
- [ ] For each "manual maintenance" artifact (manifests, allowlists): what if it becomes stale?
- [ ] For each evidence gate: does the evidence remain valid as the codebase evolves?
- [ ] For each cache/TTL: can continuous use prevent the TTL from ever expiring?

### 6. Long-Term Maintenance Hazards

Ask: "What happens in 6 months when the original author is unavailable?"

#### 6a. Configuration Explosion

- [ ] How many env vars does the system have before and after the change?
- [ ] Is the interaction between env vars documented?
- [ ] Can a new developer understand the configuration without reading the source?
- [ ] Are any env var combinations dangerous or contradictory?

Rule of thumb: >50 env vars for a single script is a maintenance hazard. Each new var adds a dimension to the configuration space that can't be fully tested.

#### 6b. Manifest and Lint Staleness

For any manually-maintained artifact (manifests, allowlists, lint patterns):

- [ ] What is the forcing function to keep it updated? (CI failure? Lint? Nothing?)
- [ ] What happens if it becomes stale? (Silent false-positive? Noisy false-negative? Undetected drift?)
- [ ] Does the lint/guard itself need maintenance when coding patterns evolve?
- [ ] Can escape hatches (ignore annotations, allowlist entries) accumulate over time?

#### 6c. Debugging Archaeology

- [ ] How many steps does it take to debug "why did this gate not run?"
- [ ] Does each step require knowledge of a different subsystem?
- [ ] Is there a unified "skip reason" log entry, or must the operator check multiple systems?
- [ ] Compare: how many steps does the current (pre-change) debugging path require?

#### 6d. Zombie Features

- [ ] If the feature is never fully enabled (rollout stalls at shadow), does the scaffolding stay forever?
- [ ] Does the scaffolding add overhead to every run even when disabled?
- [ ] Is there a sunset clause or removal criteria?

#### 6e. "Expand Later" Debt

- [ ] If the plan justifies complexity by future expansion, are those expansion paths actually viable?
- [ ] Do the plan's own safety constraints prevent the expansion it claims to enable?
- [ ] What is the concrete list of future skip candidates, and how many are actually eligible?

---

## Operational & Human Factors

### 7. Day-to-Day Operations & Incident Response

Ask: "When something goes wrong at 2am, how many steps does it take to diagnose?"

- [ ] **Debug path length**: Count steps to answer "why did gate X not run?" Compare pre-change vs post-change.
- [ ] **Incident signal clarity**: When a cached/skipped decision causes a missed failure, is the signal loud or buried?
  - Forced-run failure after N skips should be a distinct alert level, not a normal failure.
- [ ] **Diagnostic tooling**: Is there a single command to dump system state? (`--status`, `--why-skipped <gate>`, `--checkpoint-info`)
- [ ] **Rollback clarity**: Can an operator disable the new behavior without reading source code? Is it one env var or five?

Example failure:
```
Gate skipped via checkpoint → broken code passes verify → pushed to main
Diagnosis requires: check rollout mode → check skip decision log → check
fingerprint match → check forced-run counter → check kill switch token
= 5 steps across 3 subsystems vs 1 step (read gate .log) before the change
```

### 8. Integration with Existing Tooling

Check how the change interacts with the developer's actual environment:

- [ ] **Git hooks**: Does the change work in pre-commit context? (`GIT_DIR`/`GIT_WORK_TREE` set, partial staging, timeout constraints)
- [ ] **IDE/editor integration**: If tools call the script in background, do TTY detection or interactive prompts break?
- [ ] **Multiple terminals**: Two instances running simultaneously — is shared state safe? (last-writer-wins acceptable if fail-closed)
- [ ] **CI context leakage**: If a CI env var (`CI=true`) leaks into local shell profile, does the change handle it? Conversely, if `CI=true` is missing in a custom CI, does the change fire inappropriately?
- [ ] **Shell profile pollution**: Env vars set in `.bashrc`/`.zshrc` leak into all invocations. Are any new env vars dangerous if permanently set?

### 9. Organizational & Process Aspects

- [ ] **Bus factor**: Are >50% of tickets assigned to one person? If that person is unavailable, what stalls?
- [ ] **Handoff artifacts**: When ticket A's output is ticket B's input, is there a documented handoff point or does B's author need to read A's code?
- [ ] **Cross-plan coordination**: If another active plan touches the same files/state, is there a detection mechanism? (File ownership, lock file, CI check)
- [ ] **Ticket ordering**: Are dependencies between tickets explicit, or must implementers discover them by failing?

### 10. Data & Privacy Considerations

For any telemetry, logging, or data collection:

- [ ] **What's captured?** Enumerate exact fields. Is user identity, hostname, or path information included?
- [ ] **Where's it stored?** Local only? Shared filesystem? Committed to git?
- [ ] **Retention**: Is there a TTL? Does it apply to all data or only some fields?
- [ ] **Consent and opt-out**: Is collection documented? Can it be disabled?
- [ ] **Privacy preservation**: Use hashed identifiers instead of raw usernames/hostnames when identity is needed for uniqueness checks, not identification.

Example failure:
```
Telemetry collects $USER and $(hostname) for "sample diversity checks"
→ stored in local JSON files with 7-day TTL
→ shared machine: other users can see who ran what and when
Fix: hash the identity — sha256("$USER@$HOSTNAME") truncated to 12 chars
```

### 11. Failure Recovery Scenarios

Trace what happens when things go wrong in specific ways:

- [ ] **Disk full during write**: Temp file created but rename fails. Is temp file cleaned up? Does it accumulate over runs?
- [ ] **Runtime dependency disappears**: Python/jq/rg removed or upgraded mid-rollout. Does the system detect and degrade gracefully, or silently use stale data?
- [ ] **Process killed (SIGKILL)**: No trap possible. Is state left consistent? (Atomic rename is safe; temp files may leak)
- [ ] **Concurrent state mutation**: Another process (editor, git hook, background job) modifies state files between read and decision. Is the window small enough? Is the impact bounded?
- [ ] **Partial previous run**: Script killed mid-execution. What state is left? Does next run detect and recover?

### 12. Mental Model Mismatches

Ask: "Will a developer who doesn't read the docs misunderstand this?"

Common mismatches:

| What developer thinks | What actually happens | Impact |
|----------------------|----------------------|--------|
| "verify passed = all gates ran" | Some gates were skipped via cache | False confidence in code correctness |
| "I changed an env var, verify will catch it" | Env var not in fingerprint manifest → cache hit | Silent behavioral divergence |
| "kill switch disables skip" | Kill switch is token-match, not toggle. Empty-matches-empty is a pass | Skip still active when developer expects it disabled |
| "shadow mode is no-op" | Shadow mode writes telemetry silently | Unexpected data collection |
| "force-run catches all issues" | Force-run triggers after N skips, not immediately | Window of vulnerability between skips |

Checklist:
- [ ] Does the pass/fail summary line indicate how many gates were skipped?
- [ ] Is there a visible indicator when shadow/probe mode is active?
- [ ] Are emergency-disable semantics obvious without reading source code?
- [ ] Can a developer discover all configuration options from `--help` or a single doc?

### 13. Performance Beyond the Core Change

- [ ] **I/O amplification**: Count additional file reads/writes per run. Schema validation, telemetry writes, manifest reads — each adds I/O.
- [ ] **Slow filesystem impact**: NFS, Docker overlay, WSL2 — are all file operations tolerant of high-latency I/O?
- [ ] **Write path divergence**: If skip creates a different write path than normal execution (e.g., writing `.status=skipped` markers vs normal `.rc` files), is the write path tested equally?
- [ ] **Telemetry write amplification**: In shadow/probe modes, how many extra files per run? At team scale?

### 14. Documentation Discoverability

- [ ] **Single entry point**: Is there one place a developer goes to understand the new behavior? Or must they read 3+ files?
- [ ] **`--help` coverage**: Are new flags/env vars documented in the script's usage output?
- [ ] **Migration guide**: For behavior changes, is there a "what changed for me" document?
- [ ] **Changelog**: Is the change noted somewhere discoverable (not just in a plan file)?

### 15. Manifest & Guard Maintenance Burden

For any manually-maintained artifact introduced by the change:

- [ ] **Update trigger**: What event forces the artifact to be updated? (CI lint, test failure, nothing?)
- [ ] **Staleness direction**: Does a stale manifest cause false positives (gate runs unnecessarily) or false negatives (gate skipped when it shouldn't be)?
- [ ] **Removal detection**: Lint catches additions (new env reads not in manifest). Does it catch removals (manifest entry for file that no longer exists)?
- [ ] **Lint maintenance**: If coding patterns evolve (variable indirection, dynamic imports), does the lint still work?
- [ ] **Escape hatch accumulation**: Can ignore annotations pile up over time? Is there a review/audit mechanism?

### 16. Ralph / Harness Interaction

Even for changes scoped to manual runs, check harness edge cases:

- [ ] **Env var leakage**: Does the harness explicitly set or unset the new env vars, or does it inherit from the developer's shell?
- [ ] **Special modes**: Does the harness have modes (verify-only, dry-run, promotion) that interact unexpectedly with the change?
- [ ] **Phase asymmetry**: If the harness calls the tool twice per iteration (e.g., verify_pre + verify_post), does the change behave correctly in both contexts?

---

## Output Format

```markdown
## Strategic Failure Review: <component/PR>

### Architectural Findings

#### High
- **<title>**
  - Risk: <what could go wrong>
  - Impact: <blast radius>
  - Mitigation: <recommendation>

#### Medium / Low
- ...

### Hidden Assumptions
- [ ] <assumption>: violated when <scenario>

### Systemic Risks
- [ ] Complexity ratio: <N env vars, M scripts> for <benefit>
- [ ] Dual-mechanism interaction: <system A> vs <system B> on conflict

### Compounding Failures
- [ ] Chain: <A> → <B> → <C> with detection gap at <step>

### Maintenance Hazards
- [ ] Debug path: <N steps> to answer "why was X skipped?"
- [ ] Zombie risk: if rollout stalls, scaffolding remains with <overhead>

### Operational Findings

### Operations & Incident Response
- [ ] Debug path: <N steps> pre-change vs <M steps> post-change
- [ ] Diagnostic command exists: <yes/no>

### Developer Ergonomics
- [ ] Mental model mismatches: <list>
- [ ] Config discoverability: `--help` covers new options? <yes/no>

### Data & Privacy
- [ ] Identity data: <what's collected, how stored, retention>
- [ ] Opt-out mechanism: <exists/missing>

### Tooling Integration
- [ ] Git hooks: <safe/unsafe/untested>
- [ ] Concurrent terminals: <safe with last-writer-wins / needs locking>

### Open Questions
- <question needing clarification>
```

---

## Common Failure Patterns (Strategic)

| Pattern | Failure Mode | Check |
|---------|--------------|-------|
| Dual skip mechanisms | Two systems disagree on skip/run | Specify ordering, authority, unified logging |
| Complexity ratchet | Each safety layer justifies the next | Count total machinery vs actual benefit |
| Point-in-time evidence | Evidence window proves nothing about future | Ask "is correctness proved once or continuously?" |
| TTL refresh loop | Continuous use prevents TTL expiry | Ask "can cache live forever under active use?" |
| Manifest staleness | Manual artifact drifts from reality | Ask "what forces this to stay updated?" |
| Impure function caching | Tool version / env changes invisible to fingerprint | List ALL inputs, not just fingerprinted ones |
| Zombie scaffolding | Feature never fully enabled but code stays | Ask "what if rollout stalls at shadow forever?" |
| Expand-later debt | Complexity justified by future expansion that can't happen | Verify expansion is viable under plan's own constraints |
| Config explosion | >50 env vars, untestable combinations | Count before/after; flag contradictory combos |
| Debug archaeology | N-step trace across M subsystems to find root cause | Compare pre-change vs post-change debug path length |
| "Passed" ≠ "all ran" | Skip changes meaning of pass/fail summary | Does summary line show skip count? |
| Shell profile pollution | Env var in `.bashrc` leaks into all invocations | Are any new vars dangerous if permanently set? |
| Pre-commit context | `GIT_DIR`/`GIT_WORK_TREE` set, partial staging | Does script handle hook context? |
| Last-writer-wins | Two terminals overwrite shared state | Is fail-closed on mismatch sufficient? |
| Identity in telemetry | Raw `$USER`/`$(hostname)` in local files | Use privacy-preserving hashes for uniqueness |
| Forced-run failure signal | Cache masked a broken gate | Is post-skip-streak failure a distinct alert level? |
| Manifest removal detection | Lint catches additions but not stale removals | Dead entries accumulate silently |
| Diagnostic discoverability | No `--help` or `--status` for new behavior | Developer must read source to understand system |
| Bus factor / ticket concentration | >50% tickets on one owner | Stalls if owner is unavailable |
| Cross-plan file ownership | Two plans modify same state file | No detection mechanism for conflicts |

## Integration with Other Skills

- Run `/failure-mode-review` first for implementation-level analysis
- Use `/strategic-failure-review` (this skill) for architectural and operational analysis
- Run `/pr-review` for general correctness
- For safety-critical Rust code, also use `/contract-review`
