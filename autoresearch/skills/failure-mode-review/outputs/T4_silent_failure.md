## Failure Mode Review: deploy_check.sh

### Triage

Error handling with `|| true` (§4 Error Path Tracing, §9 Downstream Propagation), external inputs (§3 What-If), §6 Concrete Walkthrough.

### Findings

#### High

- **Suppressed test failure allows broken code to deploy** — `deploy_check.sh:11`
  - Failure scenario: `cargo test --lib` fails because tests are broken. `|| true` converts the exit code to 0. Script continues to `./scripts/deploy.sh`.
  - Impact: Broken code deployed to production. The entire purpose of this pre-deploy safety gate is defeated.
  - Fix: Remove `|| true`. Let test failures abort the deployment.

#### High

- **curl failure overwrites production config with empty file** — `deploy_check.sh:15-18`
  - Failure scenario: Network unavailable or config server unreachable. `curl -s` fails, but the redirect `> /tmp/trading_config.json` creates an empty 0-byte file. `|| true` silences the curl failure. The next `cp /tmp/trading_config.json "$ROOT/config/trading.json"` then overwrites the working production config with an empty file.
  - Impact: Production config destroyed. `./scripts/deploy.sh` runs with an empty/invalid config → undefined or catastrophic behavior.
  - Fix: Validate curl succeeds and file is non-empty before copying:
    ```bash
    curl -sf https://config.internal/trading.json -o /tmp/trading_config.json \
      || { echo "Config fetch failed"; exit 1; }
    [[ -s /tmp/trading_config.json ]] || { echo "Empty config fetched"; exit 1; }
    ```

#### Medium

- **Suppressed clippy failure silences code quality gate** — `deploy_check.sh:12`
  - Failure scenario: `cargo clippy -- -D warnings` finds warnings/errors. `|| true` silences them. Deployment proceeds despite known code quality issues.
  - Impact: Lint gate bypassed; technical debt accumulates unchecked.
  - Fix: Remove `|| true`.

### Error Path Tracing

| Error Source | Immediate Effect | Downstream Impact |
|---|---|---|
| `cargo test || true` | Test failure hidden, exit 0 | Broken code reaches deployment |
| `cargo clippy || true` | Lint warnings hidden, exit 0 | Quality gate bypassed |
| `curl ... || true` | Network error hidden, empty file created | Config overwritten with empty file |
| Empty config copied | Production config destroyed | Deploy runs with invalid/empty config |

### Downstream Errors Traced

- `cargo test` fails → `|| true` → exit 0 → `./scripts/deploy.sh` runs with broken binary
- `curl` fails → empty `/tmp/trading_config.json` → `cp` overwrites production config → deploy runs with empty config

### Concrete Value Walkthrough

**Scenario: Network failure during config fetch**

1. `cargo test --lib || true` → tests fail (exit 1), `|| true` → exit 0. Tests ignored.
2. `cargo clippy -- -D warnings || true` → clippy fails, silenced. Ignored.
3. `curl -s https://config.internal/trading.json > /tmp/trading_config.json || true`:
   - curl times out / connection refused → exit 7
   - `>` redirect already created `/tmp/trading_config.json` (0 bytes)
   - `|| true` → exit 0
4. `cp /tmp/trading_config.json "$ROOT/config/trading.json"`:
   - cp succeeds (copying an empty file is valid)
   - Production `config/trading.json` is now 0 bytes
5. `./scripts/deploy.sh` runs → reads empty config → behavior undefined / crash

**Result**: A network blip destroys the production config and allows a broken build to deploy.

### Next Step

All three `|| true` additions are safety regressions. This diff must be reverted before any deployment proceeds.
