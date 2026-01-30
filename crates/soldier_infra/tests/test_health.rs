//! Integration tests for the health endpoint.
//!
//! Acceptance criteria (from PRD S0-004):
//! - GIVEN health endpoint called WHEN system healthy THEN returns ok=true, build_id, contract_version.
//! - GIVEN health command WHEN system healthy THEN exits 0.

use soldier_infra::health::{
    CONTRACT_VERSION, EXIT_HEALTHY, EXIT_UNHEALTHY, HealthResponse, check_health, exit_code,
};

/// AT-022 partial: Health response MUST include ok, build_id, contract_version.
#[test]
fn test_health_endpoint_returns_required_fields() {
    let build_id = "abc123def";
    let response = check_health(build_id);

    // Required field: ok (bool; MUST be true when process is up)
    assert!(response.ok, "ok field MUST be true when healthy");

    // Required field: build_id (string)
    assert_eq!(
        response.build_id, build_id,
        "build_id MUST match the provided value"
    );

    // Required field: contract_version (string)
    assert_eq!(
        response.contract_version, CONTRACT_VERSION,
        "contract_version MUST be set"
    );
    assert!(
        !response.contract_version.is_empty(),
        "contract_version MUST NOT be empty"
    );
}

/// Acceptance: GIVEN health command WHEN system healthy THEN exits 0.
#[test]
fn test_health_command_exits_zero_when_healthy() {
    let response = check_health("test_build");

    // Healthy response MUST have ok=true
    assert!(response.ok);

    // Exit code MUST be 0 for healthy
    let code = exit_code(&response);
    assert_eq!(code, EXIT_HEALTHY, "healthy system MUST exit with code 0");
}

/// Exit code 1 for unhealthy response.
#[test]
fn test_health_command_exits_one_when_unhealthy() {
    let response = HealthResponse::unhealthy("test_build");

    // Unhealthy response has ok=false
    assert!(!response.ok);

    // Exit code MUST be 1 for unhealthy
    let code = exit_code(&response);
    assert_eq!(
        code, EXIT_UNHEALTHY,
        "unhealthy system MUST exit with code 1"
    );
}

/// Contract version matches the expected value from CONTRACT.md.
#[test]
fn test_contract_version_is_5_2() {
    assert_eq!(CONTRACT_VERSION, "5.2", "CONTRACT_VERSION MUST be 5.2");
}

/// HealthResponse constructors produce consistent results.
#[test]
fn test_health_response_constructors() {
    let healthy = HealthResponse::healthy("build_a");
    let unhealthy = HealthResponse::unhealthy("build_b");

    assert!(healthy.ok);
    assert!(!unhealthy.ok);

    assert_eq!(healthy.contract_version, unhealthy.contract_version);
    assert_eq!(healthy.contract_version, CONTRACT_VERSION);
}
