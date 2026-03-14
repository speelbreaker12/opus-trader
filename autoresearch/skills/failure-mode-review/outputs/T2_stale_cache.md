## Failure Mode Review: audit_cache.py

### Triage

New caching/persistence logic: §2 State Transitions, §3 What-If, §6 Concrete Walkthrough, §10 Trusted Files apply.

### Findings

#### High

- **Cache never invalidated — stale results reused on config revert** — `audit_cache.py:13-16`
  - Failure scenario: Config changes (hash A → B → A). When config returns to content A, old cache entry from first run is reused. That cached result may be outdated if other audit inputs changed between runs.
  - Impact: Stale audit results served silently as valid. Orphaned cache files accumulate indefinitely.
  - Fix: Add TTL, explicit eviction, or version stamp in cache key. Document that cache is content-addressed and requires manual cleanup.

#### Medium

- **Config deletion crashes with FileNotFoundError** — `audit_cache.py:14-15`
  - Failure scenario: If `config_path` doesn't exist, `config_path.read_bytes()` raises `FileNotFoundError` inside `get_cache_key`, called from both `load_cached_result` and `save_cached_result`.
  - Impact: Unhandled crash instead of graceful "config missing" error.
  - Fix: Check `config_path.exists()` before computing key; propagate explicit error.

#### Low

- **Corrupted cache file raises unhandled JSONDecodeError** — `audit_cache.py:21-22`
  - Failure scenario: Cache file exists but is corrupted. `json.loads(cache_file.read_text())` raises `JSONDecodeError`, propagates to caller.
  - Impact: Crash instead of re-running audit with cache miss.
  - Fix: Wrap in `try/except JSONDecodeError`; delete corrupt file and return None.

### State Transitions Enumerated

| Question | Answer |
|----------|--------|
| What creates the artifact? | `save_cached_result` (on first cache miss in `run_audit`) |
| What reads/uses it? | `load_cached_result` (before each `run_audit`) |
| What invalidates/deletes it? | **Nothing** — no eviction or cleanup logic exists |
| What if config changes but cache remains? | Old entry orphaned (new key used), stale entry stays on disk |
| What if config disappears but cache remains? | Crash at `config_path.read_bytes()` in `get_cache_key` |
| What if cache is corrupted/partial/empty? | JSONDecodeError propagates uncaught |
| What if cache has wrong schema version? | No version field — old structure silently used |

### Concrete Value Walkthrough

**Scenario: Config content cycles A → B → A (stale reuse)**

1. Run 1: `config_path` has content A, `sha256(A)[:8]` = "abc12345"
   - `get_cache_key("slice1", config)` → `"slice1_abc12345"`
   - Cache miss → audit runs → result saved to `.cache/audit/slice1_abc12345.json`

2. Config updated to content B: hash changes to "def67890"
   - Cache key now `"slice1_def67890"` — old file `slice1_abc12345.json` stays on disk (orphaned stale entry)
   - Cache miss → audit runs fresh ✓

3. Config reverts to content A: hash = "abc12345" again
   - Cache key: `"slice1_abc12345"`
   - Cache file exists! Old result returned immediately
   - **Bug**: cached result may be invalid if other audit inputs changed between runs 1 and 3

### Interface Crossings Verified

- All functions in `audit_cache.py` — no cross-file interface crossings in this diff.

### Open Questions

- Who calls `run_audit`? Are callers prepared for a crash if config is deleted?
- Is `.cache/audit/` committed to git or excluded? Stale entries crossing git checkouts would be dangerous.

### Next Step

Cache lifecycle risk is non-trivial. Consider `/strategic-failure-review` for eviction strategy.
