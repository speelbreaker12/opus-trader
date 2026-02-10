# test_break_glass_kill_blocks_open_allows_reduce

## Purpose

Prove break-glass authority can halt new risk while preserving risk reduction.

## Procedure

1. Simulate runaway OPEN order generation.
   - Example: `./stoic-cli simulate-open --instrument BTC-28MAR26-50000-C --count 3`
2. Trigger break-glass Kill.
   - Example: `./stoic-cli emergency kill --reason "phase0 drill"`
3. Verify KILL authority state and empty pending queue.
   - `./stoic-cli status --format json`
   - `./stoic-cli orders --pending --format json`
4. Attempt an OPEN order (must fail in KILL).
5. Attempt a REDUCE_ONLY order (or equivalent risk-reducing action).
   - Example: `./stoic-cli emergency reduce-only --reason "test reduce path"`
   - Example: `./stoic-cli simulate-close --instrument BTC-28MAR26-50000-C --dry-run`

## Pass Criteria

- OPEN attempt fails immediately once Kill is active.
- Risk-reducing action remains available and succeeds.
- Evidence of the drill is recorded with timestamp and operator.
