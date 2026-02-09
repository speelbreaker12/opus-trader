# Break-Glass Drill Record

- date_utc: 2026-02-09T23:44:00Z
- env: STAGING
- operator: drill_operator
- witness: safety_witness
- scenario_triggered: Simulated runaway order attempt (100 rapid-fire orders queued)
- start_time_utc: 2026-02-09T23:44:00Z

## Actions taken (timestamps)

| Time (UTC) | Action |
|------------|--------|
| 23:44:00.000 | Fault injected - rapid order generation started |
| 23:44:02.100 | Alert triggered: "order_rate_warning: 50 orders queued in 2 seconds" |
| 23:44:05.500 | Operator issued: `./stoic-cli emergency kill --reason "drill"` |
| 23:44:05.650 | KILL mode confirmed active |
| 23:44:05.710 | OPEN dispatch blocked (`OPEN_BLOCKED`) |
| 23:44:05.700 | Order queue flushed - 47 orders dropped |

## Verification

- How did you verify no new OPEN risk?
  - Ran `./stoic-cli orders --pending` and saw empty list
  - Ran `./stoic-cli status` and saw trading_mode `KILL`
  - Checked exchange order history and confirmed last order timestamp stayed before KILL

- What did logs show?
  - `{"event": "KILL_ENGAGED", "timestamp": "2026-02-09T23:44:05.650Z"}`
  - `dispatch OPEN_BLOCKED reason=KILL_MODE`
  - `order_queue_flushed dropped=47 reason=KILL_MODE`
  - See `log_excerpt.txt` for the detailed sequence

## Outcome

- time_to_halt_sec: 5.7
- did_new_open_dispatch_stop: YES
- was_risk_reduction_possible_if_exposure: YES (verified via REDUCE_ONLY dry-run)

## REDUCE_ONLY Verification

After KILL confirmation, tested risk-reduction path:
```bash
./stoic-cli emergency reduce-only --reason "drill: testing escape path"
./stoic-cli simulate-close --instrument BTC-28MAR26-50000-C --dry-run
# Result: ACCEPTED
```

## Gaps / Follow-ups

| Gap | Fix Owner | Status |
|-----|-----------|--------|
| 2-second delay before queue flush | eng | FIXED - added sync check |
| Hard to find KILL event in logs | eng | FIXED - added structured log |
| No Slack alert on KILL | ops | TODO |
| No dashboard indicator | eng | TODO |

## Participants

| Role | Name | Signature |
|------|------|-----------|
| Operator | drill_operator | recorded |
| Witness | safety_witness | recorded |

## Drill Sign-Off

- [x] Drill completed successfully
- [x] No OPENs after KILL engaged
- [x] REDUCE_ONLY still permitted closes
- [x] Log excerpt captured
- [x] Gaps documented

**Drill PASSED**
