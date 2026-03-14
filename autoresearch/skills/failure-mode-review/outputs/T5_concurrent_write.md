## Failure Mode Review: state_tracker.py

### Triage

New shared-state file with read-modify-write: §7 Concurrent Execution, §2 State Transitions, §3 What-If, §6 Concrete Walkthrough.

### Findings

#### High

- **Race condition in update_state: read-modify-write with no file locking** — `state_tracker.py:19-23`
  - Failure scenario: Two parallel CI jobs call `mark_complete()` simultaneously.
    - Job A: `read_state()` → `{}`
    - Job B: `read_state()` → `{}`
    - Job A: `STATE_FILE.write_text({"job_a": "complete"})`
    - Job B: `STATE_FILE.write_text({"job_b": "complete"})` — **OVERWRITES job_a's entry**
  - Impact: State file missing entries. `all_complete()` returns False even when all jobs finished. CI coordination logic broken.
  - Fix: Use file locking (`flock`), atomic rename (write to `.tmp` then `os.rename()`), or per-job files with merge step.

### Concurrent Execution Analysis

`update_state` performs a read-modify-write sequence with no mutual exclusion:

1. `read_state()` reads JSON from `STATE_FILE`
2. Updates in-memory dict
3. `STATE_FILE.write_text(json.dumps(state, indent=2))` overwrites the file

Two concurrent writers → last writer wins → all other writers' updates are silently lost.

The module docstring explicitly says "Track execution state across parallel CI jobs" — the intended use case is exactly the one that triggers the race condition.

### State Transitions Enumerated

| Question | Answer |
|----------|--------|
| What creates the artifact? | `update_state` → `STATE_FILE.write_text(...)` |
| What reads/uses it? | `read_state`, `all_complete` |
| What invalidates/deletes it? | Nothing — no cleanup logic |
| What if two writers run simultaneously? | Last writer wins; others' updates lost |
| What if STATE_FILE is corrupted/partial? | `json.loads` raises JSONDecodeError (unhandled) |
| What if STATE_FILE.parent doesn't exist? | `mkdir(parents=True)` handles this ✓ |

### Concrete Value Walkthrough

**Scenario: 3 parallel CI jobs complete at the same time**

Timeline:
1. job_a calls `update_state("job_a", "complete")`: reads `{}`, writes `{"job_a": "complete"}`
2. job_b calls `update_state("job_b", "complete")`: reads `{}` (read before job_a finished), writes `{"job_b": "complete"}` — **overwrites job_a**
3. job_c calls `update_state("job_c", "complete")`: reads `{"job_b": "complete"}` (read before job_c's write), writes `{"job_b": "complete", "job_c": "complete"}` — **loses job_a**

Final state: `{"job_b": "complete", "job_c": "complete"}`

`all_complete(["job_a", "job_b", "job_c"])` → `False` (job_a missing) — deadlock in CI coordination.

### Fix Patterns

1. **File locking (flock)**: Wrap `update_state` with OS-level lock:
   ```python
   import fcntl
   with open(".state/lock", "w") as lock:
       fcntl.flock(lock, fcntl.LOCK_EX)
       # ... read-modify-write ...
   ```

2. **Atomic rename**: Write to temp file then rename (prevents torn writes but not lost updates without locking):
   ```python
   tmp = STATE_FILE.with_suffix(".tmp")
   tmp.write_text(json.dumps(state, indent=2))
   os.rename(tmp, STATE_FILE)
   ```

3. **Per-process files with merge**: Each job writes `state_{job_name}.json`; a single merge step reads all files — no locking needed.

### Next Step

This needs a concurrency fix before use in parallel CI. Consider `/strategic-failure-review` for overall state management architecture.
