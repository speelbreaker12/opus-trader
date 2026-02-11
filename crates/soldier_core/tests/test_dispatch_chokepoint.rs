//! CI tests proving the single dispatch chokepoint invariant.
//!
//! CONTRACT.md CSP.5.2: All dispatch must route through `build_order_intent()`.
//! These tests scan source code to enforce architectural constraints.
//!
//! AT-935: No module other than build_order_intent.rs may construct ChokeResult::Approved.
//! VR-014: Dispatch function visibility is restricted to the chokepoint module.

use std::fs;
use std::path::PathBuf;

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
    for entry in fs::read_dir(dir).expect("read_dir failed") {
        let entry = entry.expect("entry failed");
        let path = entry.path();
        if path.is_dir() {
            files.extend(collect_rs_files(&path));
        } else if path.extension().is_some_and(|e| e == "rs") {
            let content = fs::read_to_string(&path).expect("read file failed");
            files.push((path, content));
        }
    }
    files
}

// ─── Test: Only build_order_intent.rs may construct ChokeResult::Approved ──

#[test]
fn test_dispatch_chokepoint_no_bypass_approved() {
    let src = src_dir();
    let files = collect_rs_files(&src);

    let chokepoint_file = "build_order_intent.rs";
    let mut violations = Vec::new();

    for (path, content) in &files {
        let filename = path.file_name().unwrap().to_str().unwrap();
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
        let filename = path.file_name().unwrap().to_str().unwrap();
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

// ─── Test: No direct exchange dispatch usage outside approved boundary ──

#[test]
fn test_dispatch_chokepoint_no_direct_exchange_client_usage() {
    let src = src_dir();
    let files = collect_rs_files(&src);
    let mut violations = Vec::new();

    for (path, content) in &files {
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
        // execution/mod.rs re-exports symbols and is not a call site.
        if rel_str == "execution/mod.rs" {
            continue;
        }

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();
            if trimmed.starts_with("//") || trimmed.starts_with("///") {
                continue;
            }

            if line.contains("map_to_dispatch(") || line.contains("validate_and_dispatch(") {
                violations.push(format!(
                    "{}:{}: directly calls dispatch mapping outside chokepoint boundary",
                    path.display(),
                    line_num + 1,
                ));
            }

            if line.contains("DispatchRequest {") {
                violations.push(format!(
                    "{}:{}: directly constructs DispatchRequest outside dispatch_map/chokepoint boundary",
                    path.display(),
                    line_num + 1,
                ));
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
        let filename = path.file_name().unwrap().to_str().unwrap();
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
        let filename = path.file_name().unwrap().to_str().unwrap();
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

// ─── Test: Chokepoint module exists and exports build_order_intent ────────

#[test]
fn test_chokepoint_module_exists() {
    let chokepoint_path = src_dir().join("execution").join("build_order_intent.rs");

    assert!(
        chokepoint_path.exists(),
        "Chokepoint module must exist at execution/build_order_intent.rs"
    );

    let content = fs::read_to_string(&chokepoint_path).expect("read chokepoint");

    assert!(
        content.contains("pub fn build_order_intent("),
        "Chokepoint must export build_order_intent() as pub fn"
    );

    // Verify it's the single chokepoint — must reference CSP.5.2
    assert!(
        content.contains("CSP.5.2"),
        "Chokepoint module must reference CONTRACT.md CSP.5.2"
    );
}

// ─── Test: mod.rs re-exports build_order_intent ──────────────────────────

#[test]
fn test_chokepoint_reexported_from_execution() {
    let mod_path = src_dir().join("execution").join("mod.rs");
    let content = fs::read_to_string(&mod_path).expect("read mod.rs");

    assert!(
        content.contains("pub mod build_order_intent"),
        "execution/mod.rs must declare pub mod build_order_intent"
    );

    assert!(
        content.contains("build_order_intent,"),
        "execution/mod.rs must re-export build_order_intent function"
    );
}

// ─── Test: Chokepoint metrics mutators are not publicly callable ───────

#[test]
fn test_chokepoint_metrics_mutators_not_public() {
    let chokepoint_path = src_dir().join("execution").join("build_order_intent.rs");
    let content = fs::read_to_string(&chokepoint_path).expect("read chokepoint");

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
