# R5b Receipt Summary: devils-advocate

- Status: completed
- Head commit: e04a39f9150316caa2a97a5e371cbb5ab7284f5a
- Started: 2026-02-24T20:34:27Z
- Ended: 2026-02-24T20:34:27Z
- Finding counts: P0=0, P1=1, P2=2, INFO=0
- Finding summary: Mutation/attack-surface review identifies malformed-key/probe handling and test isolation gaps that can undercut causal proof on privilege handling.

## Evidence References
- stoic-cli:996-1003
- crates/soldier_infra/tests/test_phase0_runtime.rs:200-273
- stoic-cli:362-385
- crates/soldier_infra/tests/test_phase0_runtime.rs:632-696

## Findings
- [P1] DA-1: keys-check permissive/malformed probe inputs can bypass intended privilege checks.
- [P2] DA-2: Key privilege tests are not sufficiently isolated for precise causal proof.
- [P2] DA-3: AT-022 still not covered at transport endpoint level.
