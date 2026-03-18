Rust fintech rules (non-negotiable): no f32/f64 for prices/qty/fees; no unwrap() in production; fail-closed defaults (ReduceOnly not Active when uncertain); Arc/Mutex for shared async state.

Success is not "story marked done."
Success is: proof-backed, fail-closed, review-clean, and verifiably compliant.

Never optimize for speed over safety.
Never skip sequence.
If a required artifact/test/proof is missing, stop and report it.

Required Decision Output (if this step changes code or PRD):
  Chosen design | Alternative considered | Why chosen is safer | What can still fail | How failure is detected
