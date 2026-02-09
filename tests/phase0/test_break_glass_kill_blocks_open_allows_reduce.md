# test_break_glass_kill_blocks_open_allows_reduce

## Purpose

Prove break-glass authority can halt new risk while preserving risk reduction.

## Procedure

1. Simulate runaway OPEN order generation.
2. Trigger break-glass Kill.
3. Attempt an OPEN order.
4. Attempt a REDUCE_ONLY order (or equivalent risk-reducing action).

## Pass Criteria

- OPEN attempt fails immediately once Kill is active.
- Risk-reducing action remains available and succeeds.
- Evidence of the drill is recorded with timestamp and operator.
