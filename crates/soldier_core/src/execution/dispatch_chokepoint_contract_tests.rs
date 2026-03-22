//! CI tests proving the single dispatch chokepoint invariant.
//!
//! CONTRACT.md CSP.5.2: All dispatch must route through the
//! WAL-safe chokepoint wrappers in `build_order_intent.rs`.
//! These tests scan source code to enforce architectural constraints.
//!
//! AT-935: No module other than build_order_intent.rs may construct ChokeResult::Approved.
//! VR-014: Dispatch function visibility is restricted to the chokepoint module.

use std::fs;
use std::path::{Path, PathBuf};

const CHOKEPOINT_RELATIVE_PATH: &str = "execution/build_order_intent.rs";
const APPROVAL_SENTINEL: &str = "record_approved();";

/// Locate the soldier_core/src directory relative to the test binary.
fn src_dir() -> PathBuf {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest.join("src")
}

/// Read all `.rs` files under a directory recursively.
fn collect_rs_files(dir: &std::path::Path) -> Vec<(PathBuf, String)> {
    let mut files = Vec::new();
    if !dir.exists() {
        return files;
    }
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(err) => panic!("read_dir failed for {}: {}", dir.display(), err),
    };
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(err) => panic!("entry failed for {}: {}", dir.display(), err),
        };
        let path = entry.path();
        if path.is_dir() {
            files.extend(collect_rs_files(&path));
        } else if path.extension().is_some_and(|e| e == "rs") {
            let content = read_file_or_panic(&path, "read file failed");
            files.push((path, content));
        }
    }
    files
}

fn read_file_or_panic(path: &Path, context: &str) -> String {
    match fs::read_to_string(path) {
        Ok(content) => content,
        Err(err) => panic!("{context} for {}: {}", path.display(), err),
    }
}

fn filename_or_panic(path: &Path) -> &str {
    match path.file_name().and_then(|name| name.to_str()) {
        Some(filename) => filename,
        None => panic!("path has no UTF-8 filename: {}", path.display()),
    }
}

fn is_unit_test_module(path: &std::path::Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.ends_with("_tests.rs"))
}

// ─── Test: Only build_order_intent.rs may construct ChokeResult::Approved ──

#[test]
fn test_dispatch_chokepoint_no_bypass_approved() {
    let src = src_dir();
    let files = collect_rs_files(&src);

    let chokepoint_file = "build_order_intent.rs";
    let mut violations = Vec::new();

    for (path, content) in &files {
        if is_unit_test_module(path) {
            continue;
        }
        let filename = filename_or_panic(path);
        // Skip the chokepoint module itself — it's allowed to construct Approved
        if filename == chokepoint_file {
            continue;
        }

        // Check for ChokeResult::Approved construction outside chokepoint
        for (line_num, line) in content.lines().enumerate() {
            // Skip comments
            let trimmed = line.trim();
            if trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }
            if line.contains("ChokeResult::Approved") {
                violations.push(format!(
                    "{}:{}: constructs ChokeResult::Approved outside chokepoint",
                    path.display(),
                    line_num + 1,
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "ChokeResult::Approved must only be constructed in {chokepoint_file}.\n\
         Violations:\n{}",
        violations.join("\n")
    );
}

// ─── Test: Only build_order_intent.rs may call metrics.record_approved() ──

#[test]
fn test_dispatch_chokepoint_no_bypass_metrics() {
    let src = src_dir();
    let files = collect_rs_files(&src);

    let chokepoint_file = "build_order_intent.rs";
    let mut violations = Vec::new();

    for (path, content) in &files {
        if is_unit_test_module(path) {
            continue;
        }
        let filename = filename_or_panic(path);
        if filename == chokepoint_file {
            continue;
        }

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();
            if trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }
            // record_approved is the chokepoint's sole approval signal
            if line.contains("record_approved") {
                violations.push(format!(
                    "{}:{}: calls record_approved() outside chokepoint",
                    path.display(),
                    line_num + 1,
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "record_approved() must only be called in {chokepoint_file}.\n\
         Violations:\n{}",
        violations.join("\n")
    );
}

// ─── Test: Chokepoint keeps the approval sentinel call ────────────────────

#[test]
fn test_dispatch_chokepoint_approval_sentinel_present() {
    let chokepoint_path = src_dir().join(CHOKEPOINT_RELATIVE_PATH);
    let content = read_file_or_panic(&chokepoint_path, "read chokepoint");

    assert!(
        content.contains(APPROVAL_SENTINEL),
        "chokepoint must contain approval sentinel `{APPROVAL_SENTINEL}` in {CHOKEPOINT_RELATIVE_PATH}",
    );
}

#[test]
fn test_routing_no_gate_configured_uses_chokepoint_event_sink() {
    let routing_path = src_dir().join("execution/routing.rs");
    let content = read_file_or_panic(&routing_path, "read routing source");

    assert!(
        !content.contains("bump_wal_nonblocking_allowed_total("),
        "routing.rs must not bypass the chokepoint WAL-nonblocking sink; route through build_order_intent event emission instead",
    );
    assert!(
        !content.contains("source = \"no_gate_configured\""),
        "routing.rs must not log the no_gate_configured WAL path directly; the chokepoint sink owns that diagnostic",
    );
}

// ─── Test: No direct exchange dispatch usage outside approved boundary ──

#[test]
fn test_dispatch_chokepoint_no_direct_exchange_client_usage() {
    let src = src_dir();
    let files = collect_rs_files(&src);
    let mut violations = Vec::new();
    let forbidden_dispatch_symbols = [
        "map_to_dispatch",
        "validate_and_dispatch",
        "DispatchRequest",
        "DispatchMapError",
        "ValidatedDispatch",
    ];

    for (path, content) in &files {
        if is_unit_test_module(path) {
            continue;
        }
        let rel = path.strip_prefix(&src).unwrap_or(path);
        let rel_str = rel.to_string_lossy();
        // dispatch_map defines DispatchRequest and dispatch helpers.
        if rel_str == "execution/dispatch_map.rs" {
            continue;
        }
        // build_order_intent is the chokepoint boundary.
        if rel_str == "execution/build_order_intent.rs" {
            continue;
        }
        // intent_assembly is the production assembly helper that wires
        // derive_instrument_kind + build_order_size + validate_and_dispatch
        // into the pipeline path (feeds evaluate_intent_pipeline).
        if rel_str == "execution/intent_assembly.rs" {
            continue;
        }
        // execution/mod.rs re-exports symbols and is not a call site.
        if rel_str == "execution/mod.rs" {
            continue;
        }

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();
            if trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }

            for sym in &forbidden_dispatch_symbols {
                if line.contains(sym) {
                    violations.push(format!(
                        "{}:{}: references forbidden dispatch boundary symbol `{sym}` outside dispatch_map/chokepoint boundary",
                        path.display(),
                        line_num + 1,
                    ));
                }
            }
        }
    }

    assert!(
        violations.is_empty(),
        "Direct exchange dispatch usage is only allowed via the chokepoint boundary.\n\
         Violations:\n{}",
        violations.join("\n")
    );
}

// ─── Test: build_order_intent is the only function returning ChokeResult ──

#[test]
fn test_dispatch_visibility_is_restricted() {
    let src = src_dir();
    let files = collect_rs_files(&src);

    let chokepoint_file = "build_order_intent.rs";
    let mut violations = Vec::new();

    for (path, content) in &files {
        if is_unit_test_module(path) {
            continue;
        }
        let filename = filename_or_panic(path);
        if filename == chokepoint_file || filename == "mod.rs" {
            continue;
        }

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();
            if trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }
            // No other module should define a function returning ChokeResult
            if line.contains("-> ChokeResult") {
                violations.push(format!(
                    "{}:{}: defines function returning ChokeResult outside chokepoint",
                    path.display(),
                    line_num + 1,
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "Only build_order_intent.rs may define functions returning ChokeResult.\n\
         Violations:\n{}",
        violations.join("\n")
    );
}

// ─── Test: No direct GateResults construction outside tests and chokepoint ──

#[test]
fn test_no_direct_gate_results_construction_in_production() {
    let src = src_dir();
    let files = collect_rs_files(&src);

    let chokepoint_file = "build_order_intent.rs";
    let mut violations = Vec::new();

    for (path, content) in &files {
        if is_unit_test_module(path) {
            continue;
        }
        let filename = filename_or_panic(path);
        // The chokepoint module defines GateResults — skip it
        if filename == chokepoint_file {
            continue;
        }

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();
            if trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }
            // GateResults { ... } construction outside chokepoint in src/
            // (tests are allowed to construct for testing)
            if line.contains("GateResults {") && !line.contains("GateResults::default") {
                violations.push(format!(
                    "{}:{}: constructs GateResults outside chokepoint module",
                    path.display(),
                    line_num + 1,
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "GateResults construction in production code must only be in the chokepoint module.\n\
         Violations:\n{}",
        violations.join("\n")
    );
}

// ─── Test: Chokepoint module exists and exports WAL-safe entrypoints ──────

#[test]
fn test_chokepoint_module_exists() {
    let chokepoint_path = src_dir().join("execution").join("build_order_intent.rs");

    assert!(
        chokepoint_path.exists(),
        "Chokepoint module must exist at execution/build_order_intent.rs"
    );

    let content = read_file_or_panic(&chokepoint_path, "read chokepoint");

    assert!(
        content.contains("pub fn build_order_intent_with_wal_gate("),
        "Chokepoint must export build_order_intent_with_wal_gate() as pub fn"
    );
    assert!(
        content.contains("pub fn build_order_intent_with_optional_wal_gate("),
        "Chokepoint must export build_order_intent_with_optional_wal_gate() as pub fn"
    );

    // Verify it's the single chokepoint — must reference CSP.5.2
    assert!(
        content.contains("CSP.5.2"),
        "Chokepoint module must reference CONTRACT.md CSP.5.2"
    );
}

// ─── Test: Chokepoint symbols are reachable via the execution facade ─────

#[test]
fn chokepoint_symbols_reachable_via_execution_facade() {
    #[allow(unused_imports)]
    use crate::execution::build_order_intent::{
        build_gate_results, build_order_intent_with_optional_wal_gate,
        build_order_intent_with_wal_gate,
    };
}

// ─── Test: Chokepoint metrics mutators are not publicly callable ───────

#[test]
fn test_chokepoint_metrics_mutators_not_public() {
    let chokepoint_path = src_dir().join("execution").join("build_order_intent.rs");
    let content = read_file_or_panic(&chokepoint_path, "read chokepoint");

    assert!(
        !content.contains("pub fn record_approved"),
        "record_approved must not be public outside chokepoint module"
    );
    assert!(
        !content.contains("pub fn record_rejected"),
        "record_rejected must not be public outside chokepoint module"
    );
    assert!(
        !content.contains("pub fn record_rejected_risk_state"),
        "record_rejected_risk_state must not be public outside chokepoint module"
    );
}
