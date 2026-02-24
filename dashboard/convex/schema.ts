import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const metricObject = v.object({
  value: v.union(v.number(), v.null()),
  unit: v.string(),
  threshold_state: v.union(v.literal("OK"), v.literal("WARN"), v.literal("CRIT"), v.literal("UNKNOWN")),
  reason: v.string(),
  updated_at: v.string(),
});

const freshnessObject = v.object({
  expected_publish_interval_s: v.number(),
  stale_after_s: v.number(),
});

const safetyObject = v.object({
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
});

const publisherObject = v.object({
  attempt: v.number(),
  publisher_version: v.string(),
});

export default defineSchema({
  statusSnapshots: defineTable({
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
    safety: safetyObject,
    metrics: v.object({
      mm_util: metricObject,
      disk_used_pct: metricObject,
      wal_queue_depth: metricObject,
      ws_event_lag: metricObject,
      http_429_count: metricObject,
      deribit_10028_count: metricObject,
      deribit_http_p95: metricObject,
    }),
    freshness: freshnessObject,
    publisher: publisherObject,
  }).index("by_instance", ["source.instance_id"]).index("by_snapshot_hash", ["snapshot_hash"]),

  latestStatusPointers: defineTable({
    instance_id: v.string(),
    snapshot_id: v.id("statusSnapshots"),
    snapshot_hash: v.string(),
    updated_at: v.string(),
  }).index("by_instance", ["instance_id"]),
});
