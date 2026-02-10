//! Phase-0 runtime automation tests.
//!
//! These are executable integration tests (not evidence-only checks):
//! - policy binding must fail closed when policy is missing/malformed
//! - key scope least-privilege validation must fail closed on bad probes
//! - break-glass kill blocks OPEN while allowing risk reduction

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;
use std::process::{Command, Output};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

fn repo_root() -> PathBuf {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .ancestors()
        .nth(2)
        .expect("workspace root")
        .to_path_buf()
}

fn cli_path() -> PathBuf {
    repo_root().join("stoic-cli")
}

fn unique_temp_file(prefix: &str, suffix: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    env::temp_dir().join(format!("{prefix}_{nanos}_{suffix}"))
}

fn unique_temp_state_file(prefix: &str) -> PathBuf {
    let root = repo_root()
        .join("artifacts")
        .join("phase0")
        .join("runtime_state_tests");
    fs::create_dir_all(&root).expect("create runtime state test directory");
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    root.join(format!("{prefix}_{}_{}.state.json", process::id(), nanos))
}

fn run_cli<I, S>(args: I, env_overrides: &[(&str, &str)]) -> Output
where
    I: IntoIterator<Item = S>,
    S: AsRef<std::ffi::OsStr>,
{
    let mut cmd = Command::new(cli_path());
    cmd.current_dir(repo_root());
    cmd.args(args);
    for (k, v) in env_overrides {
        cmd.env(k, v);
    }
    cmd.output().unwrap_or_else(|err| {
        panic!(
            "failed to execute stoic-cli at {}: {err}",
            cli_path().display()
        )
    })
}

fn parse_stdout_json(output: &Output) -> Value {
    serde_json::from_slice(&output.stdout)
        .unwrap_or_else(|e| panic!("stdout is not valid JSON: {e}\nstdout={:?}", output.stdout))
}

fn remove_if_exists(path: &Path) {
    if let Err(err) = fs::remove_file(path) {
        assert_eq!(
            err.kind(),
            std::io::ErrorKind::NotFound,
            "failed to remove temporary file {}: {err}",
            path.display()
        );
    }
}

#[test]
fn test_policy_is_required_and_bound_runtime() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    assert!(valid_policy.exists(), "expected baseline policy config");

    // Baseline sanity: valid policy + ACTIVE OPEN should allow.
    let ok_out = run_cli(
        ["dispatch-check", "--intent", "OPEN", "--mode", "ACTIVE"],
        &[("STOIC_POLICY_PATH", valid_policy.to_str().unwrap())],
    );
    assert_eq!(
        ok_out.status.code(),
        Some(0),
        "valid policy should allow ACTIVE OPEN"
    );
    let ok_payload = parse_stdout_json(&ok_out);
    assert_eq!(ok_payload["ok"], Value::Bool(true));
    assert_eq!(ok_payload["decision"], Value::String("ALLOW".to_string()));

    // Missing policy: must fail closed.
    let missing_policy = root.join("config/missing_policy_for_test.json");
    let missing_out = run_cli(
        ["dispatch-check", "--intent", "OPEN", "--mode", "ACTIVE"],
        &[("STOIC_POLICY_PATH", missing_policy.to_str().unwrap())],
    );
    assert_eq!(
        missing_out.status.code(),
        Some(1),
        "missing policy must fail closed"
    );
    let missing_payload = parse_stdout_json(&missing_out);
    assert_eq!(missing_payload["ok"], Value::Bool(false));
    assert_eq!(
        missing_payload["reason"],
        Value::String("policy_validation_failed".to_string())
    );
    let missing_errors = missing_payload["errors"]
        .as_array()
        .expect("errors array required on policy failure");
    assert!(
        missing_errors
            .iter()
            .any(|e| e.as_str().unwrap_or("").to_lowercase().contains("policy")),
        "policy errors should be explicit"
    );

    // Malformed policy: must fail closed, no implicit fallback.
    let bad_policy = unique_temp_file("phase0_bad_policy", "json");
    fs::write(&bad_policy, "{ invalid_json: ").expect("write malformed policy");
    let malformed_out = run_cli(
        ["dispatch-check", "--intent", "OPEN", "--mode", "ACTIVE"],
        &[("STOIC_POLICY_PATH", bad_policy.to_str().unwrap())],
    );
    assert_eq!(
        malformed_out.status.code(),
        Some(1),
        "malformed policy must fail closed"
    );
    let malformed_payload = parse_stdout_json(&malformed_out);
    assert_eq!(malformed_payload["ok"], Value::Bool(false));
    assert_eq!(
        malformed_payload["reason"],
        Value::String("policy_validation_failed".to_string())
    );
    remove_if_exists(&bad_policy);
}

#[test]
fn test_api_keys_are_least_privilege_runtime() {
    let root = repo_root();
    let baseline_probe = root.join("evidence/phase0/keys/key_scope_probe.json");
    assert!(baseline_probe.exists(), "expected baseline key_scope_probe");

    // Baseline probe should pass.
    let ok_out = run_cli(
        [
            "keys-check",
            "--probe",
            baseline_probe.to_str().unwrap(),
            "--env",
            "STAGING",
        ],
        &[],
    );
    assert_eq!(
        ok_out.status.code(),
        Some(0),
        "baseline STAGING probe should pass least-privilege checks"
    );
    let ok_payload = parse_stdout_json(&ok_out);
    assert_eq!(ok_payload["ok"], Value::Bool(true));

    // Over-privileged probe must fail closed.
    let bad_probe = unique_temp_file("phase0_bad_probe", "json");
    let bad_probe_json = r#"
{
  "probes": [
    {
      "env": "STAGING",
      "exchange": "Deribit",
      "key_id": "key_staging_trade_bad",
      "scopes": ["read_account", "trade"],
      "withdraw_enabled": true,
      "probe_results": {
        "withdraw": {
          "attempted": true,
          "result": "success"
        }
      }
    }
  ]
}
"#;
    fs::write(&bad_probe, bad_probe_json).expect("write bad probe");

    let bad_out = run_cli(
        [
            "keys-check",
            "--probe",
            bad_probe.to_str().unwrap(),
            "--env",
            "STAGING",
        ],
        &[],
    );
    assert_eq!(
        bad_out.status.code(),
        Some(1),
        "over-privileged probe must fail"
    );
    let bad_payload = parse_stdout_json(&bad_out);
    assert_eq!(bad_payload["ok"], Value::Bool(false));
    let errs = bad_payload["errors"]
        .as_array()
        .expect("errors array expected for failing key checks");
    assert!(
        errs.iter()
            .any(|e| e.as_str().unwrap_or("").contains("withdraw_enabled")),
        "failure should explicitly report withdraw_enabled violation"
    );
    remove_if_exists(&bad_probe);
}

#[test]
fn test_break_glass_kill_blocks_open_allows_reduce_runtime() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");

    // Kill must block OPEN.
    let blocked_out = run_cli(
        ["dispatch-check", "--intent", "OPEN", "--mode", "KILL"],
        &[("STOIC_POLICY_PATH", valid_policy.to_str().unwrap())],
    );
    assert_eq!(
        blocked_out.status.code(),
        Some(1),
        "KILL mode must block OPEN"
    );
    let blocked_payload = parse_stdout_json(&blocked_out);
    assert_eq!(blocked_payload["ok"], Value::Bool(false));
    assert_eq!(
        blocked_payload["reason"],
        Value::String("kill_mode_blocks_open".to_string())
    );

    // Kill must still allow risk-reducing actions.
    let reduce_out = run_cli(
        [
            "dispatch-check",
            "--intent",
            "REDUCE_ONLY",
            "--mode",
            "KILL",
        ],
        &[("STOIC_POLICY_PATH", valid_policy.to_str().unwrap())],
    );
    assert_eq!(
        reduce_out.status.code(),
        Some(0),
        "KILL mode must allow risk reduction"
    );
    let reduce_payload = parse_stdout_json(&reduce_out);
    assert_eq!(reduce_payload["ok"], Value::Bool(true));
    assert_eq!(
        reduce_payload["reason"],
        Value::String("kill_mode_allows_risk_reduction".to_string())
    );
}

#[test]
fn test_status_command_behavior_runtime() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_state_file("phase0_status_state");
    remove_if_exists(&runtime_state);

    let runtime_state_str = runtime_state.to_str().expect("utf8 path");
    let valid_policy_str = valid_policy.to_str().expect("utf8 path");

    let healthy_out = run_cli(
        ["status", "--format", "json"],
        &[
            ("STOIC_POLICY_PATH", valid_policy_str),
            ("STOIC_RUNTIME_STATE_PATH", runtime_state_str),
            ("STOIC_BUILD_ID", "phase0-status-runtime-test"),
        ],
    );
    assert_eq!(
        healthy_out.status.code(),
        Some(0),
        "status healthy path must exit 0"
    );
    let healthy_payload = parse_stdout_json(&healthy_out);
    assert_eq!(healthy_payload["ok"], Value::Bool(true));
    assert_eq!(
        healthy_payload["trading_mode"],
        Value::String("ACTIVE".to_string())
    );
    assert_eq!(healthy_payload["is_trading_allowed"], Value::Bool(true));

    let missing_policy = root.join("config/missing_policy_for_status_test.json");
    let unhealthy_out = run_cli(
        ["status", "--format", "json"],
        &[
            ("STOIC_POLICY_PATH", missing_policy.to_str().unwrap()),
            ("STOIC_RUNTIME_STATE_PATH", runtime_state_str),
            ("STOIC_BUILD_ID", "phase0-status-runtime-test"),
        ],
    );
    assert_eq!(
        unhealthy_out.status.code(),
        Some(1),
        "status unhealthy path must exit 1"
    );
    let unhealthy_payload = parse_stdout_json(&unhealthy_out);
    assert_eq!(unhealthy_payload["ok"], Value::Bool(false));
    assert_eq!(
        unhealthy_payload["trading_mode"],
        Value::String("KILL".to_string())
    );
    assert_eq!(unhealthy_payload["is_trading_allowed"], Value::Bool(false));
    let errs = unhealthy_payload["errors"]
        .as_array()
        .expect("errors array expected on unhealthy status");
    assert!(
        errs.iter()
            .any(|e| e.as_str().unwrap_or("").to_lowercase().contains("policy")),
        "status unhealthy errors should mention policy failure"
    );

    remove_if_exists(&runtime_state);
}

#[test]
fn test_break_glass_command_path_runtime() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_state_file("phase0_break_glass_state");
    remove_if_exists(&runtime_state);

    let runtime_state_str = runtime_state.to_str().expect("utf8 path");
    let valid_policy_str = valid_policy.to_str().expect("utf8 path");
    let env_base = [
        ("STOIC_POLICY_PATH", valid_policy_str),
        ("STOIC_RUNTIME_STATE_PATH", runtime_state_str),
        ("STOIC_BUILD_ID", "phase0-break-glass-runtime-test"),
    ];

    // Active mode should allow simulated OPEN queueing.
    let seed_out = run_cli(
        [
            "simulate-open",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--count",
            "3",
        ],
        &env_base,
    );
    assert_eq!(
        seed_out.status.code(),
        Some(0),
        "simulate-open should accept in ACTIVE mode"
    );
    let seed_payload = parse_stdout_json(&seed_out);
    assert_eq!(
        seed_payload["result"],
        Value::String("ACCEPTED".to_string())
    );

    // Pending orders should now be visible.
    let pending_before = run_cli(["orders", "--pending", "--format", "json"], &env_base);
    assert_eq!(pending_before.status.code(), Some(0));
    let pending_before_payload = parse_stdout_json(&pending_before);
    assert_eq!(pending_before_payload["pending_count"], Value::from(3));

    // Emergency kill should flush OPEN queue and disable trading.
    let kill_out = run_cli(
        ["emergency", "kill", "--reason", "runtime e2e drill"],
        &env_base,
    );
    assert_eq!(
        kill_out.status.code(),
        Some(0),
        "emergency kill must succeed"
    );
    let kill_payload = parse_stdout_json(&kill_out);
    assert_eq!(
        kill_payload["trading_mode"],
        Value::String("KILL".to_string())
    );
    assert_eq!(kill_payload["is_trading_allowed"], Value::Bool(false));
    assert_eq!(kill_payload["pending_orders"], Value::from(0));

    // Status confirms Kill + no trading.
    let status_after_kill = run_cli(["status", "--format", "json"], &env_base);
    assert_eq!(
        status_after_kill.status.code(),
        Some(0),
        "status must remain queryable after kill"
    );
    let status_after_kill_payload = parse_stdout_json(&status_after_kill);
    assert_eq!(
        status_after_kill_payload["trading_mode"],
        Value::String("KILL".to_string())
    );
    assert_eq!(
        status_after_kill_payload["is_trading_allowed"],
        Value::Bool(false)
    );
    assert_eq!(status_after_kill_payload["pending_orders"], Value::from(0));

    // OPEN must be blocked while in kill mode.
    let open_in_kill = run_cli(
        [
            "simulate-open",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--count",
            "1",
        ],
        &env_base,
    );
    assert_eq!(
        open_in_kill.status.code(),
        Some(1),
        "OPEN must block in KILL"
    );
    let open_in_kill_payload = parse_stdout_json(&open_in_kill);
    assert_eq!(
        open_in_kill_payload["result"],
        Value::String("BLOCKED".to_string())
    );

    // Risk reduction path remains available via reduce-only mode + simulate-close.
    let reduce_mode = run_cli(
        [
            "emergency",
            "reduce-only",
            "--reason",
            "runtime e2e reduce path",
        ],
        &env_base,
    );
    assert_eq!(
        reduce_mode.status.code(),
        Some(0),
        "reduce-only transition must succeed"
    );
    let reduce_mode_payload = parse_stdout_json(&reduce_mode);
    assert_eq!(
        reduce_mode_payload["trading_mode"],
        Value::String("REDUCE_ONLY".to_string())
    );

    let close_out = run_cli(
        [
            "simulate-close",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--dry-run",
        ],
        &env_base,
    );
    assert_eq!(
        close_out.status.code(),
        Some(0),
        "simulate-close dry-run should be accepted"
    );
    let close_payload = parse_stdout_json(&close_out);
    assert_eq!(
        close_payload["result"],
        Value::String("ACCEPTED".to_string())
    );

    remove_if_exists(&runtime_state);
}

#[test]
fn test_simulate_open_rejects_when_policy_invalid() {
    let root = repo_root();
    let runtime_state = unique_temp_state_file("phase0_policy_reject_open");
    remove_if_exists(&runtime_state);
    let missing_policy = root.join("config/missing_policy_for_sim_open.json");

    let out = run_cli(
        [
            "simulate-open",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--count",
            "1",
        ],
        &[
            (
                "STOIC_POLICY_PATH",
                missing_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_BUILD_ID", "phase0-policy-open-reject-test"),
        ],
    );
    assert_eq!(
        out.status.code(),
        Some(1),
        "policy failure must reject OPEN"
    );
    let payload = parse_stdout_json(&out);
    assert_eq!(payload["ok"], Value::Bool(false));
    assert_eq!(
        payload["reason"],
        Value::String("policy_validation_failed".to_string())
    );
    assert_eq!(payload["result"], Value::String("REJECTED".to_string()));
    remove_if_exists(&runtime_state);
}

#[test]
fn test_runtime_state_path_outside_repo_rejected() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");

    let out = run_cli(
        ["status", "--format", "json"],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                "/tmp/phase0_outside_repo_state.json",
            ),
            ("STOIC_BUILD_ID", "phase0-state-path-guard-test"),
        ],
    );
    assert_eq!(
        out.status.code(),
        Some(1),
        "path outside repo must fail closed"
    );
    let payload = parse_stdout_json(&out);
    assert_eq!(payload["ok"], Value::Bool(false));
    assert_eq!(
        payload["trading_mode"],
        Value::String("KILL".to_string()),
        "status should fail closed to KILL when runtime path is invalid"
    );
    let errs = payload["errors"]
        .as_array()
        .expect("errors array expected on invalid runtime path");
    assert!(
        errs.iter()
            .any(|e| e.as_str().unwrap_or("").contains("runtime_state")),
        "runtime_state path violation should be explicit"
    );
}

#[test]
fn test_runtime_state_path_outside_repo_allowed_with_explicit_opt_in() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_file("phase0_external_state_opt_in", "json");
    remove_if_exists(&runtime_state);

    let out = run_cli(
        ["status", "--format", "json"],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_ALLOW_EXTERNAL_RUNTIME_STATE", "1"),
            ("STOIC_BUILD_ID", "phase0-state-path-opt-in-test"),
        ],
    );
    assert_eq!(
        out.status.code(),
        Some(0),
        "explicit external-state opt-in should allow outside-repo path"
    );
    let payload = parse_stdout_json(&out);
    assert_eq!(payload["ok"], Value::Bool(true));
    assert_eq!(payload["trading_mode"], Value::String("ACTIVE".to_string()));

    remove_if_exists(&runtime_state);
}

#[test]
fn test_simulate_open_enforces_pending_orders_capacity() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_state_file("phase0_capacity_guard");
    remove_if_exists(&runtime_state);

    let seed = run_cli(
        [
            "simulate-open",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--count",
            "1",
        ],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_MAX_PENDING_ORDERS", "1"),
            ("STOIC_BUILD_ID", "phase0-capacity-seed-test"),
        ],
    );
    assert_eq!(seed.status.code(), Some(0), "first OPEN should be accepted");

    let blocked = run_cli(
        [
            "simulate-open",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--count",
            "1",
        ],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_MAX_PENDING_ORDERS", "1"),
            ("STOIC_BUILD_ID", "phase0-capacity-block-test"),
        ],
    );
    assert_eq!(
        blocked.status.code(),
        Some(1),
        "capacity limit must reject overflow OPEN"
    );
    let payload = parse_stdout_json(&blocked);
    assert_eq!(payload["ok"], Value::Bool(false));
    assert_eq!(
        payload["reason"],
        Value::String("pending_orders_capacity_exceeded".to_string())
    );
    remove_if_exists(&runtime_state);
}

#[test]
fn test_runtime_state_schema_mismatch_fails_closed() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_state_file("phase0_schema_mismatch");
    remove_if_exists(&runtime_state);
    fs::write(
        &runtime_state,
        r#"{
  "schema_version": 999,
  "trading_mode": "ACTIVE",
  "orders_in_flight": 1,
  "pending_orders": [{"id":"sim_0001","intent":"OPEN","instrument":"BTC"}],
  "last_transition_reason": "seed",
  "last_transition_ts": "2026-01-01T00:00:00Z"
}"#,
    )
    .expect("write mismatched runtime state");

    let out = run_cli(
        ["status", "--format", "json"],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_BUILD_ID", "phase0-schema-mismatch-test"),
        ],
    );
    assert_eq!(
        out.status.code(),
        Some(1),
        "schema mismatch must fail closed and surface error"
    );
    let payload = parse_stdout_json(&out);
    assert_eq!(payload["ok"], Value::Bool(false));
    assert_eq!(payload["trading_mode"], Value::String("KILL".to_string()));
    let errs = payload["errors"]
        .as_array()
        .expect("errors array expected on schema mismatch");
    assert!(
        errs.iter()
            .any(|e| e.as_str().unwrap_or("").contains("schema_version")),
        "schema mismatch should be explicit in errors"
    );

    remove_if_exists(&runtime_state);
}

#[test]
fn test_runtime_state_null_schema_fails_closed() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_state_file("phase0_schema_null");
    remove_if_exists(&runtime_state);
    fs::write(
        &runtime_state,
        r#"{
  "schema_version": null,
  "trading_mode": "ACTIVE",
  "orders_in_flight": 1,
  "pending_orders": [{"id":"sim_0001","intent":"OPEN","instrument":"BTC"}],
  "last_transition_reason": "seed",
  "last_transition_ts": "2026-01-01T00:00:00Z"
}"#,
    )
    .expect("write null-schema runtime state");

    let out = run_cli(
        ["status", "--format", "json"],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_BUILD_ID", "phase0-schema-null-test"),
        ],
    );
    assert_eq!(
        out.status.code(),
        Some(1),
        "null schema_version must fail closed"
    );
    let payload = parse_stdout_json(&out);
    assert_eq!(payload["ok"], Value::Bool(false));
    assert_eq!(payload["trading_mode"], Value::String("KILL".to_string()));
    let errs = payload["errors"]
        .as_array()
        .expect("errors array expected on null schema");
    assert!(
        errs.iter()
            .any(|e| e.as_str().unwrap_or("").contains("schema_version")),
        "null schema error should explicitly mention schema_version"
    );

    remove_if_exists(&runtime_state);
}

#[test]
fn test_legacy_runtime_state_without_schema_is_migrated() {
    let root = repo_root();
    let valid_policy = root.join("config/policy.json");
    let runtime_state = unique_temp_state_file("phase0_legacy_state_migration");
    remove_if_exists(&runtime_state);
    fs::write(
        &runtime_state,
        r#"{
  "trading_mode": "ACTIVE",
  "orders_in_flight": 1,
  "pending_orders": [{"id":"sim_0001","intent":"OPEN","instrument":"BTC"}],
  "last_transition_reason": "legacy_seed",
  "last_transition_ts": "2026-01-01T00:00:00Z"
}"#,
    )
    .expect("write legacy runtime state");

    let status_out = run_cli(
        ["status", "--format", "json"],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_BUILD_ID", "phase0-legacy-state-status-test"),
        ],
    );
    assert_eq!(
        status_out.status.code(),
        Some(0),
        "legacy unversioned state should remain readable"
    );
    let status_payload = parse_stdout_json(&status_out);
    assert_eq!(status_payload["ok"], Value::Bool(true));
    assert_eq!(
        status_payload["trading_mode"],
        Value::String("ACTIVE".to_string())
    );

    let open_out = run_cli(
        [
            "simulate-open",
            "--instrument",
            "BTC-28MAR26-50000-C",
            "--count",
            "1",
        ],
        &[
            (
                "STOIC_POLICY_PATH",
                valid_policy.to_str().expect("utf8 path"),
            ),
            (
                "STOIC_RUNTIME_STATE_PATH",
                runtime_state.to_str().expect("utf8 path"),
            ),
            ("STOIC_BUILD_ID", "phase0-legacy-state-migrate-test"),
        ],
    );
    assert_eq!(
        open_out.status.code(),
        Some(0),
        "legacy state should be writable and migratable"
    );
    let open_payload = parse_stdout_json(&open_out);
    assert_eq!(open_payload["ok"], Value::Bool(true));

    let persisted = fs::read_to_string(&runtime_state).expect("read migrated runtime state");
    let persisted_obj: Value =
        serde_json::from_str(&persisted).expect("migrated state must be valid JSON");
    assert_eq!(persisted_obj["schema_version"], Value::from(1));

    remove_if_exists(&runtime_state);
}
