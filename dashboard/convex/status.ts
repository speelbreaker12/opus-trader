import { query, mutation } from "./_generated/server";
import { v } from "convex/values";
import {
  DashboardSnapshot,
  DashboardSnapshotSchema,
  computeDataFreshness,
  DataFreshnessState,
} from "./status_contract";

export const upsertStatus = mutation({
  args: { payload: DashboardSnapshotSchema },
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
    data_freshness: DataFreshnessState;
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

    const freshness = computeDataFreshness(snapshot);

    return {
      data: snapshot as DashboardSnapshot,
      data_freshness: {
        state: freshness.state,
        reason: freshness.reason,
        last_generated_at: freshness.last_generated_at,
      },
    };
  },
});
