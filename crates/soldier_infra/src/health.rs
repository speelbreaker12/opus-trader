//! Health endpoint implementation for Phase 0.
//!
//! Returns minimal health information: ok, build_id, contract_version.
//! Per CONTRACT.md §7.0 AT-022: response MUST include ok, build_id, contract_version.

/// Contract version as defined in CONTRACT.md.
pub const CONTRACT_VERSION: &str = "5.2";

/// Health response for the `/api/v1/health` endpoint.
///
/// Per CONTRACT.md: `/health` response MUST include (minimum):
/// - `ok` (bool; MUST be true when process is up)
/// - `build_id` (string)
/// - `contract_version` (string)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HealthResponse {
    /// True when the process is up and healthy.
    pub ok: bool,
    /// Git commit SHA or build identifier.
    pub build_id: String,
    /// Contract version (e.g., "5.2").
    pub contract_version: String,
}

impl HealthResponse {
    /// Create a healthy response with the given build_id.
    ///
    /// # Arguments
    /// * `build_id` - Git commit SHA or build identifier.
    pub fn healthy(build_id: impl Into<String>) -> Self {
        Self {
            ok: true,
            build_id: build_id.into(),
            contract_version: CONTRACT_VERSION.to_string(),
        }
    }

    /// Create an unhealthy response with the given build_id.
    ///
    /// # Arguments
    /// * `build_id` - Git commit SHA or build identifier.
    pub fn unhealthy(build_id: impl Into<String>) -> Self {
        Self {
            ok: false,
            build_id: build_id.into(),
            contract_version: CONTRACT_VERSION.to_string(),
        }
    }
}

/// Check system health and return a HealthResponse.
///
/// In Phase 0, this simply returns healthy if the process is running.
/// Future phases will add additional checks (config, connections, etc.).
pub fn check_health(build_id: &str) -> HealthResponse {
    // Phase 0: process is up = healthy
    // Future: add config validation, connection checks, etc.
    HealthResponse::healthy(build_id)
}

/// Exit code for healthy system.
pub const EXIT_HEALTHY: i32 = 0;
/// Exit code for unhealthy system.
pub const EXIT_UNHEALTHY: i32 = 1;
/// Exit code when health cannot be determined.
pub const EXIT_ERROR: i32 = 2;

/// Get the exit code for a health response.
pub fn exit_code(response: &HealthResponse) -> i32 {
    if response.ok {
        EXIT_HEALTHY
    } else {
        EXIT_UNHEALTHY
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_healthy_response_has_required_fields() {
        let resp = HealthResponse::healthy("abc123");
        assert!(resp.ok);
        assert_eq!(resp.build_id, "abc123");
        assert_eq!(resp.contract_version, CONTRACT_VERSION);
    }

    #[test]
    fn test_unhealthy_response_has_required_fields() {
        let resp = HealthResponse::unhealthy("abc123");
        assert!(!resp.ok);
        assert_eq!(resp.build_id, "abc123");
        assert_eq!(resp.contract_version, CONTRACT_VERSION);
    }

    #[test]
    fn test_check_health_returns_healthy() {
        let resp = check_health("build_xyz");
        assert!(resp.ok);
        assert_eq!(resp.build_id, "build_xyz");
        assert_eq!(resp.contract_version, CONTRACT_VERSION);
    }

    #[test]
    fn test_exit_code_healthy() {
        let resp = HealthResponse::healthy("test");
        assert_eq!(exit_code(&resp), EXIT_HEALTHY);
    }

    #[test]
    fn test_exit_code_unhealthy() {
        let resp = HealthResponse::unhealthy("test");
        assert_eq!(exit_code(&resp), EXIT_UNHEALTHY);
    }
}
