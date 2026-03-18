# test_break_glass_kill_blocks_open_allows_reduce

## Purpose

Prove the documented primary break-glass action halts new risk while preserving risk reduction.

## Procedure

1. Simulate runaway OPEN order generation.
   - Example: `STOIC_DRILL_MODE=1 ./stoic-cli simulate-open --instrument BTC-28MAR26-50000-C --count 3`
2. Trigger the exact primary break-glass action documented in the runbook.
   - Example: `./stoic-cli emergency kill --reason "phase0 drill"`
3. Verify the documented runtime safety state and empty pending queue.
   - `./stoic-cli status --format json`
   - `./stoic-cli orders --pending --format json`
4. Attempt an OPEN order (must fail in KILL).
5. Attempt a REDUCE_ONLY order (or equivalent risk-reducing action).
   - Example: `./stoic-cli emergency reduce-only --reason "test reduce path"`
   - Example: `STOIC_DRILL_MODE=1 ./stoic-cli simulate-close --instrument BTC-28MAR26-50000-C --dry-run`
6. If using external runtime state path, require explicit two-key override for mutating commands:
   - `STOIC_ALLOW_EXTERNAL_RUNTIME_STATE=1`
   - `STOIC_UNSAFE_EXTERNAL_STATE_ACK=I_UNDERSTAND`

## Pass Criteria

- The documented primary action matches the exercised runtime control path.
- The documented runtime safety state is reached within one control-plane tick.
- OPEN attempt fails immediately once Kill is active.
- Risk-reducing action remains available and succeeds.
- The runbook includes one bounded fallback action if the primary action is unavailable.
- Evidence of the drill is recorded with timestamp and operator.
