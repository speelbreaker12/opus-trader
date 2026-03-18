import { v } from "convex/values";

export const Metric = v.union(v.number(), v.null());

export const ThresholdState = v.union(v.literal("OK"), v.literal("WARN"), v.literal("CRIT"), v.literal("UNKNOWN"));

export const DashboardSnapshotSchema = v.object({
  schema_version: v.literal("dashboard_status_snapshot.v1"),
  snapshot_hash: v.string(),
  source: v.object({
    instance_id: v.string(),
    service: v.string(),
    env: v.string(),
    head_commit: v.string(),
  }),
  times: v.object({
    generated_at: v.string(),
    published_at: v.string(),
  }),
  safety: v.object({
    trading_mode: v.union(
      v.literal("NORMAL"),
      v.literal("REDUCE_ONLY"),
      v.literal("PAUSED"),
      v.literal("SHADOW"),
      v.literal("KILL"),
    ),
    risk_state: v.union(v.literal("HEALTHY"), v.literal("DEGRADED"), v.literal("MAINTENANCE"), v.literal("KILL")),
    mode_reasons: v.array(v.string()),
    latches: v.object({
      open_permission_latched_off: v.boolean(),
      market_truth_latched: v.boolean(),
    }),
    f1_cert_state: v.object({
      status: v.union(v.literal("VALID"), v.literal("BLOCKED"), v.literal("UNKNOWN")),
      reason_codes: v.array(v.string()),
      last_certified_at: v.union(v.string(), v.null()),
    }),
    owner_view: v.object({
      unblock_steps: v.array(v.string()),
    }),
  }),
  metrics: v.object({
    mm_util: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
    disk_used_pct: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
    wal_queue_depth: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
    ws_event_lag: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
    http_429_count: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
    deribit_10028_count: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
    deribit_http_p95: v.object({
      value: Metric,
      unit: v.string(),
      threshold_state: ThresholdState,
      reason: v.string(),
      updated_at: v.string(),
    }),
  }),
  freshness: v.object({
    expected_publish_interval_s: v.number(),
    stale_after_s: v.number(),
  }),
  publisher: v.object({
    attempt: v.number(),
    publisher_version: v.string(),
  }),
});

export type DashboardSnapshot = {
  schema_version: "dashboard_status_snapshot.v1";
  snapshot_hash: string;
  source: {
    instance_id: string;
    service: string;
    env: string;
    head_commit: string;
  };
  times: { generated_at: string; published_at: string };
  safety: {
    trading_mode: "NORMAL" | "REDUCE_ONLY" | "PAUSED" | "SHADOW" | "KILL";
    risk_state: "HEALTHY" | "DEGRADED" | "MAINTENANCE" | "KILL";
    mode_reasons: string[];
    latches: {
      open_permission_latched_off: boolean;
      market_truth_latched: boolean;
    };
    f1_cert_state: {
      status: "VALID" | "BLOCKED" | "UNKNOWN";
      reason_codes: string[];
      last_certified_at: string | null;
    };
    owner_view: { unblock_steps: string[] };
  };
  metrics: {
    mm_util: MetricObject;
    disk_used_pct: MetricObject;
    wal_queue_depth: MetricObject;
    ws_event_lag: MetricObject;
    http_429_count: MetricObject;
    deribit_10028_count: MetricObject;
    deribit_http_p95: MetricObject;
  };
  freshness: {
    expected_publish_interval_s: number;
    stale_after_s: number;
  };
  publisher: {
    attempt: number;
    publisher_version: string;
  };
};

export type MetricObject = {
  value: number | null;
  unit: string;
  threshold_state: "OK" | "WARN" | "CRIT" | "UNKNOWN";
  reason: string;
  updated_at: string;
};

export type DataFreshnessState = {
  state: "FRESH" | "STALE" | "UNKNOWN";
  reason: string;
  last_generated_at: string | null;
};

export type UpsertResult = {
  duplicate: boolean;
  snapshot_hash: string;
};

type UpsertSnapshotRecord = {
  snapshot_id: string;
  snapshot_hash: string;
  snapshot: DashboardSnapshot;
};

type LatestPointer = {
  instance_id: string;
  snapshot_id: string;
  snapshot_hash: string;
  updated_at: string;
};

export type StatusState = {
  snapshots: Map<string, UpsertSnapshotRecord>;
  pointersByInstance: Map<string, LatestPointer>;
  nextSnapshotId: number;
};

export function createStatusState(): StatusState {
  return {
    snapshots: new Map(),
    pointersByInstance: new Map(),
    nextSnapshotId: 1,
  };
}

export function computeDataFreshness(snapshot: DashboardSnapshot, nowMs = Date.now()): DataFreshnessState {
  const generatedMs = Date.parse(snapshot.times.generated_at);
  const staleAfterMs = snapshot.freshness.stale_after_s * 1000;

  if (Number.isNaN(generatedMs)) {
    return {
      state: "UNKNOWN",
      reason: `generated_at is not parseable: ${snapshot.times.generated_at}`,
      last_generated_at: snapshot.times.generated_at,
    };
  }

  const age = nowMs - generatedMs;
  if (!Number.isFinite(staleAfterMs) || age <= staleAfterMs) {
    return {
      state: "FRESH",
      reason: `generated_at age = ${age}ms`,
      last_generated_at: snapshot.times.generated_at,
    };
  }

  return {
    state: "STALE",
    reason: `Snapshot age ${Math.max(0, age / 1000)}s exceeds stale_after_s=${snapshot.freshness.stale_after_s}`,
    last_generated_at: snapshot.times.generated_at,
  };
}

export function dataFreshnessReasonable(payload: DashboardSnapshot["freshness"], generatedAt: string, nowMs = Date.now()): string {
  const age = nowMs - Date.parse(generatedAt);
  if (Number.isNaN(age)) {
    return "Unknown generated_at timestamp";
  }
  if (age <= payload.stale_after_s * 1000) {
    return "Snapshot is within freshness window";
  }
  return `Snapshot age ${Math.max(0, age / 1000)}s exceeds stale_after_s=${payload.stale_after_s}`;
}

export function applyUpsertStatus(state: StatusState, payload: DashboardSnapshot): { state: StatusState; result: UpsertResult } {
  const existing = state.snapshots.get(payload.snapshot_hash);
  if (existing) {
    if (
      existing.snapshot.source.instance_id === payload.source.instance_id
      && !state.pointersByInstance.has(payload.source.instance_id)
    ) {
      const updatedPointers = new Map(state.pointersByInstance);
      updatedPointers.set(payload.source.instance_id, {
        instance_id: payload.source.instance_id,
        snapshot_id: existing.snapshot_id,
        snapshot_hash: payload.snapshot_hash,
        updated_at: payload.times.published_at,
      });
      return {
        state: {
          snapshots: state.snapshots,
          pointersByInstance: updatedPointers,
          nextSnapshotId: state.nextSnapshotId,
        },
        result: {
          duplicate: true,
          snapshot_hash: payload.snapshot_hash,
        },
      };
    }

    return {
      state,
      result: {
        duplicate: true,
        snapshot_hash: payload.snapshot_hash,
      },
    };
  }

  const snapshotId = `snapshot:${state.nextSnapshotId}`;
  const updatedSnapshots = new Map(state.snapshots);
  updatedSnapshots.set(payload.snapshot_hash, {
    snapshot_id: snapshotId,
    snapshot_hash: payload.snapshot_hash,
    snapshot: payload,
  });

  const updatedPointers = new Map(state.pointersByInstance);
  updatedPointers.set(payload.source.instance_id, {
    instance_id: payload.source.instance_id,
    snapshot_id: snapshotId,
    snapshot_hash: payload.snapshot_hash,
    updated_at: payload.times.published_at,
  });

  return {
    state: {
      snapshots: updatedSnapshots,
      pointersByInstance: updatedPointers,
      nextSnapshotId: state.nextSnapshotId + 1,
    },
    result: {
      duplicate: false,
      snapshot_hash: payload.snapshot_hash,
    },
  };
}

export function getLatestStatus(
  state: StatusState,
  instanceId: string,
  nowMs = Date.now(),
): {
  data: DashboardSnapshot | null;
  data_freshness: DataFreshnessState;
} {
  const pointer = state.pointersByInstance.get(instanceId);
  if (!pointer) {
    return {
      data: null,
      data_freshness: {
        state: "UNKNOWN",
        reason: "No latest status pointer for instance",
        last_generated_at: null,
      },
    };
  }

  const snapshot = [...state.snapshots.values()].find((row) => row.snapshot_id === pointer.snapshot_id)?.snapshot ?? null;
  if (!snapshot) {
    return {
      data: null,
      data_freshness: {
        state: "UNKNOWN",
        reason: "Latest snapshot document missing",
        last_generated_at: null,
      },
    };
  }

  const freshness = computeDataFreshness(snapshot, nowMs);
  return {
    data: snapshot,
    data_freshness: {
      state: freshness.state,
      reason: freshness.reason,
      last_generated_at: freshness.last_generated_at,
    },
  };
}
