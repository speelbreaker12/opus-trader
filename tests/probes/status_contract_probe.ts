import {
  DashboardSnapshot,
  applyUpsertStatus,
  createStatusState,
  getLatestStatus,
} from "../../dashboard/convex/status_contract";

function buildSnapshot(overrides: Partial<DashboardSnapshot>): DashboardSnapshot {
  const baseMetrics = {
    mm_util: {
      value: 0.78,
      unit: "ratio",
      threshold_state: "OK",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
    disk_used_pct: {
      value: 67.4,
      unit: "percent",
      threshold_state: "OK",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
    wal_queue_depth: {
      value: 42,
      unit: "count",
      threshold_state: "OK",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
    ws_event_lag: {
      value: 320,
      unit: "ms",
      threshold_state: "WARN",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
    http_429_count: {
      value: 3,
      unit: "count",
      threshold_state: "WARN",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
    deribit_10028_count: {
      value: 0,
      unit: "count",
      threshold_state: "OK",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
    deribit_http_p95: {
      value: 185,
      unit: "ms",
      threshold_state: "OK",
      reason: "baseline",
      updated_at: "2026-02-23T21:10:02Z",
    },
  };

  return {
    schema_version: "dashboard_status_snapshot.v1",
    snapshot_hash: "snapshot-hash",
    source: {
      instance_id: "soldier-main-01",
      service: "soldier_core",
      env: "paper",
      head_commit: "4a2e6fc",
    },
    times: {
      generated_at: "2026-02-23T21:10:03Z",
      published_at: "2026-02-23T21:10:04Z",
    },
    safety: {
      trading_mode: "REDUCE_ONLY",
      risk_state: "DEGRADED",
      mode_reasons: ["REDUCEONLY_OPEN_PERMISSION_LATCHED"],
      latches: {
        open_permission_latched_off: false,
        market_truth_latched: false,
      },
      f1_cert_state: {
        status: "BLOCKED",
        reason_codes: ["AT_225_FAILING"],
        last_certified_at: "2026-02-23T20:55:00Z",
      },
      owner_view: {
        unblock_steps: ["Run verify.sh", "Clear latch after successful reconcile"],
      },
    },
    metrics: baseMetrics,
    freshness: {
      expected_publish_interval_s: 2,
      stale_after_s: 15,
    },
    publisher: {
      attempt: 1,
      publisher_version: "status-publisher.v1",
    },
    ...overrides,
  };
}

function assertMode(name: string, value: unknown): void {
  if (value === null || value === undefined) {
    throw new Error(`missing probe output for ${name}`);
  }
}

const mode = process.argv[2] ?? "idempotent";
const nowMs = Date.parse("2026-02-23T21:10:20Z");

if (mode === "idempotent") {
  const stateA = createStatusState();
  const first = applyUpsertStatus(stateA, buildSnapshot({ snapshot_hash: "h-1", times: { generated_at: "2026-02-23T21:10:03Z", published_at: "2026-02-23T21:10:04Z" } }));
  const duplicate = applyUpsertStatus(first.state, buildSnapshot({ snapshot_hash: "h-1", times: { generated_at: "2026-02-23T21:10:03Z", published_at: "2026-02-23T21:10:04Z" } }));
  const advanced = applyUpsertStatus(duplicate.state, buildSnapshot({
    snapshot_hash: "h-2",
    times: { generated_at: "2026-02-23T21:10:06Z", published_at: "2026-02-23T21:10:07Z" },
  }));
  const latest = getLatestStatus(advanced.state, "soldier-main-01", nowMs);

  const output = {
    first: first.result,
    duplicate: duplicate.result,
    advanced: advanced.result,
    snapshot_count: advanced.state.snapshots.size,
    pointer_count: advanced.state.pointersByInstance.size,
    latest_snapshot: latest.data?.snapshot_hash,
    latest_state: latest.data_freshness.state,
    latest_last_generated_at: latest.data_freshness.last_generated_at,
  };
  assertMode("latest_snapshot", output.latest_snapshot);
  console.log(JSON.stringify(output));
  process.exit(0);
}

if (mode === "freshness") {
  const now = Date.parse("2026-02-23T21:10:20Z");
  const freshSnapshot = buildSnapshot({
    snapshot_hash: "fresh-1",
    times: { generated_at: "2026-02-23T21:10:10Z", published_at: "2026-02-23T21:10:11Z" },
    freshness: { expected_publish_interval_s: 2, stale_after_s: 15 },
  });
  const staleSnapshot = buildSnapshot({
    snapshot_hash: "stale-1",
    times: { generated_at: "2026-02-23T21:10:00Z", published_at: "2026-02-23T21:10:01Z" },
    freshness: { expected_publish_interval_s: 2, stale_after_s: 5 },
  });
  const invalidTimestampSnapshot = buildSnapshot({
    snapshot_hash: "invalid-1",
    times: { generated_at: "bad-timestamp", published_at: "2026-02-23T21:10:04Z" },
    freshness: { expected_publish_interval_s: 2, stale_after_s: 15 },
  });

  const freshState = getLatestStatus(
    applyUpsertStatus(createStatusState(), freshSnapshot).state,
    "soldier-main-01",
    now,
  );
  const staleState = getLatestStatus(
    applyUpsertStatus(createStatusState(), staleSnapshot).state,
    "soldier-main-01",
    now,
  );
  const invalidState = getLatestStatus(
    applyUpsertStatus(createStatusState(), invalidTimestampSnapshot).state,
    "soldier-main-01",
    now,
  );

  const output = {
    fresh: freshState.data_freshness.state,
    stale: staleState.data_freshness.state,
    invalid: invalidState.data_freshness.state,
    invalid_reason: invalidState.data_freshness.reason,
  };
  assertMode("fresh", output.fresh);
  console.log(JSON.stringify(output));
  process.exit(0);
}

throw new Error(`unknown mode: ${mode}`);
