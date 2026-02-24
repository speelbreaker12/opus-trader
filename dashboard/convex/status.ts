import { query, mutation } from "./_generated/server";
import { v } from "convex/values";

type DashboardSnapshot = {
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

type MetricObject = {
  value: number | null;
  unit: string;
  threshold_state: "OK" | "WARN" | "CRIT" | "UNKNOWN";
  reason: string;
  updated_at: string;
};

const Metric = v.union(v.number(), v.null());

const ThresholdState = v.union(v.literal("OK"), v.literal("WARN"), v.literal("CRIT"), v.literal("UNKNOWN"));

const SnapshotArgs = v.object({
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

function computeFreshness(snapshot: DashboardSnapshot) {
  const generatedMs = Date.parse(snapshot.times.generated_at);
  const staleAfterMs = snapshot.freshness.stale_after_s * 1000;
  if (Number.isNaN(generatedMs)) {
    return {
      state: "UNKNOWN" as const,
      reason: `generated_at is not parseable: ${snapshot.times.generated_at}`,
      last_generated_at: snapshot.times.generated_at,
    };
  }

  const age = Date.now() - generatedMs;
  if (!Number.isFinite(staleAfterMs) || age <= staleAfterMs) {
    return {
      state: "FRESH" as const,
      reason: `generated_at age = ${age}ms`,
      last_generated_at: snapshot.times.generated_at,
    };
  }

  return {
    state: "STALE" as const,
    reason: `generated_at age ${age}ms exceeds stale_after_s=${snapshot.freshness.stale_after_s}`,
    last_generated_at: snapshot.times.generated_at,
  };
}

function dataFreshnessReasonable(payload: DashboardSnapshot["freshness"], generatedAt: string) {
  const age = Date.now() - Date.parse(generatedAt);
  if (Number.isNaN(age)) {
    return "Unknown generated_at timestamp";
  }
  if (age <= payload.stale_after_s * 1000) {
    return "Snapshot is within freshness window";
  }
  return `Snapshot age ${Math.max(0, age / 1000)}s exceeds stale_after_s=${payload.stale_after_s}`;
}

export const upsertStatus = mutation({
  args: { payload: SnapshotArgs },
  handler: async (ctx: any, args: { payload: DashboardSnapshot }) => {
    const existing = await ctx.db
      .query("statusSnapshots")
      .withIndex("by_snapshot_hash", (q: any) => q.eq("snapshot_hash", args.payload.snapshot_hash))
      .unique();

    if (existing !== null) {
      return { duplicate: true, snapshot_hash: args.payload.snapshot_hash };
    }

    const inserted = await ctx.db.insert("statusSnapshots", args.payload);
    const latest = await ctx.db
      .query("latestStatusPointers")
      .withIndex("by_instance", (q: any) => q.eq("instance_id", args.payload.source.instance_id))
      .unique();

    const pointer = {
      instance_id: args.payload.source.instance_id,
      snapshot_id: inserted,
      snapshot_hash: args.payload.snapshot_hash,
      updated_at: args.payload.times.published_at,
    };

    if (latest === null) {
      await ctx.db.insert("latestStatusPointers", pointer);
    } else {
      await ctx.db.replace(latest._id, pointer);
    }

    return { duplicate: false, snapshot_hash: args.payload.snapshot_hash };
  },
});

export const getLatestStatus = query({
  args: { instance_id: v.string() },
  handler: async (ctx: any, args: { instance_id: string }): Promise<{
    data: DashboardSnapshot | null;
    data_freshness: {
      state: "FRESH" | "STALE" | "UNKNOWN";
      reason: string;
      last_generated_at: string | null;
    };
  }> => {
    const pointer = await ctx.db
      .query("latestStatusPointers")
      .withIndex("by_instance", (q: any) => q.eq("instance_id", args.instance_id))
      .unique();
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

    const snapshot = await ctx.db.get(pointer.snapshot_id);
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

    const freshness = computeFreshness(snapshot);
    const reason = dataFreshnessReasonable(snapshot.freshness, snapshot.times.generated_at);

    return {
      data: snapshot as DashboardSnapshot,
      data_freshness: {
        state: freshness.state,
        reason: reason || freshness.reason,
        last_generated_at: freshness.last_generated_at,
      },
    };
  },
});
