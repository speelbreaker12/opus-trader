from __future__ import annotations

from datetime import datetime, timezone
import json
from hashlib import sha256
from typing import Any, Dict, Optional


class SnapshotBuilderError(Exception):
  pass


RUNTIME_STATE_VERSION = "runtime_state.v1"


def _utc_iso(ts_ms: Optional[object] = None) -> str:
  if isinstance(ts_ms, (int, float)) and ts_ms > 0:
    try:
      return datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    except (OverflowError, OSError, ValueError):
      pass

  if isinstance(ts_ms, str) and ts_ms:
    return ts_ms

  return datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _safe_bool(value: object) -> Optional[bool]:
  return value if isinstance(value, bool) else None


def _safe_float(value: object) -> Optional[float]:
  if isinstance(value, bool):
    return None
  if isinstance(value, int):
    return float(value)
  if isinstance(value, float):
    return value
  return None


def _safe_int(value: object) -> Optional[int]:
  if isinstance(value, bool):
    return None
  if isinstance(value, int):
    return value
  if isinstance(value, float) and value.is_integer():
    return int(value)
  return None


def _safe_str(value: object) -> Optional[str]:
  return value if isinstance(value, str) else None


def _safe_str_list(value: object) -> list[str]:
  if not isinstance(value, list):
    return []
  return [item for item in value if isinstance(item, str)]


def _metric_state(value: Optional[float], warn: float, crit: float) -> str:
  if value is None:
    return "UNKNOWN"
  if value >= crit:
    return "CRIT"
  if value >= warn:
    return "WARN"
  return "OK"


def _metric_reason(name: str, value: Optional[float], state: str, warn: float, crit: float) -> str:
  if value is None:
    return "Metric unavailable"
  if state == "OK":
    return f"{name} within expected range"
  if state == "WARN":
    return f"{name} above warn threshold {warn}"
  if state == "CRIT":
    return f"{name} above critical threshold {crit}"
  return "Metric unavailable"


def _build_metric(
  value: Optional[float],
  unit: str,
  updated_at_ms: object,
  warn: float,
  crit: float,
) -> Dict[str, Any]:
  state = _metric_state(value, warn, crit)
  return {
    "value": value,
    "unit": unit,
    "threshold_state": "UNKNOWN" if value is None else state,
    "reason": _metric_reason(unit, value, state, warn, crit),
    "updated_at": _utc_iso(updated_at_ms),
  }


def _enforce_unavailable_metric(value: Optional[float], unit: str, updated_at_ms: object) -> Dict[str, Any]:
  if value is None:
    return {
      "value": None,
      "unit": unit,
      "threshold_state": "UNKNOWN",
      "reason": "Metric unavailable",
      "updated_at": _utc_iso(updated_at_ms),
    }
  return _build_metric(value, unit, updated_at_ms, warn=0.0, crit=0.0)


def _map_trading_mode(raw: object) -> str:
  if raw == "Active":
    return "NORMAL"
  if raw == "ReduceOnly":
    return "REDUCE_ONLY"
  if raw == "Kill":
    return "KILL"
  if raw in {"ReduceOnly", "REDUCE_ONLY", "REDUCEONLY"}:
    return "REDUCE_ONLY"
  if raw in {"Paused", "PAUSED"}:
    return "PAUSED"
  if raw in {"Normal", "NORMAL", "normal"}:
    return "NORMAL"
  if raw in {"Shadow", "SHADOW", "shadow"}:
    return "SHADOW"
  raise SnapshotBuilderError(f"unsupported trading_mode '{raw}'")


def _map_risk_state(raw: object) -> str:
  if raw in {"Healthy", "HEALTHY", "healthy"}:
    return "HEALTHY"
  if raw in {"Degraded", "DEGRADED", "degraded"}:
    return "DEGRADED"
  if raw in {"Maintenance", "MAINTENANCE", "maintenance"}:
    return "MAINTENANCE"
  if raw in {"KILL", "Kill", "kill"}:
    return "KILL"
  if raw in {"Normal", "NORMAL", "normal"}:
    return "HEALTHY"
  raise SnapshotBuilderError(f"unsupported risk_state '{raw}'")


def _map_f1_status(raw: object) -> str:
  if raw == "PASS" or raw == "VALID":
    return "VALID"
  if raw in {"FAIL", "INVALID", "MISSING", "STALE", "BLOCKED"}:
    return "BLOCKED"
  if raw in {"UNKNOWN", None, ""}:
    return "UNKNOWN"
  if raw in {"Healthy", "VALID"}:
    return "VALID"
  raise SnapshotBuilderError(f"unsupported f1_cert_state '{raw}'")


def _extract_reason_codes(payload: Dict[str, Any], key: str) -> list[str]:
  value = _safe_str_list(payload.get(key))
  return value


def _owner_view_steps(payload: Dict[str, Any]) -> list[str]:
  owner_view = payload.get("owner_view")
  if not isinstance(owner_view, dict):
    return []

  raw_unblock = owner_view.get("unblock")
  if not isinstance(raw_unblock, list):
    return []

  steps: list[str] = []
  for entry in raw_unblock:
    if not isinstance(entry, dict):
      continue
    condition = _safe_str(entry.get("condition")) or ""
    current = _safe_str(entry.get("current"))
    target = _safe_str(entry.get("target"))
    step_type = _safe_str(entry.get("type"))
    if condition and step_type and current is not None and target is not None:
      steps.append(f"{step_type}: {condition} ({current} -> {target})")
    elif condition:
      steps.append(condition)

  return steps


def hash_snapshot(payload: Dict[str, Any]) -> str:
  return sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _build_metric_from_runtime(metric: object, key: str, default_ts_ms: object) -> Dict[str, Any]:
  if not isinstance(metric, dict):
    return _enforce_unavailable_metric(None, key, default_ts_ms)
  value = _safe_float(metric.get("value"))
  if value is None and "value" not in metric:
    value = None

  unit = _safe_str(metric.get("unit")) or ""
  threshold_state = _safe_str(metric.get("threshold_state")) or ("UNKNOWN" if value is None else "UNKNOWN")
  if threshold_state not in {"OK", "WARN", "CRIT", "UNKNOWN"}:
    threshold_state = "UNKNOWN"
  reason = _safe_str(metric.get("reason")) or ("Metric unavailable" if value is None else f"{key} unavailable")
  updated_at = metric.get("updated_at", default_ts_ms)

  return {
    "value": value,
    "unit": unit,
    "threshold_state": threshold_state,
    "reason": reason,
    "updated_at": _utc_iso(updated_at),
  }


def _build_from_runtime_payload(
  payload: Dict[str, Any],
  generated_at: str,
  attempt: int,
  expected_publish_interval_s: int,
  stale_after_s: int,
  publisher_version: str,
) -> Dict[str, Any]:
  safety = payload.get("safety", {})
  metrics = payload.get("metrics", {})
  freshness = payload.get("freshness", {})
  if not isinstance(safety, dict) or not isinstance(metrics, dict) or not isinstance(freshness, dict):
    raise SnapshotBuilderError("runtime_state snapshot missing safety/metrics/freshness")

  source = {
    "instance_id": str(payload.get("instance_id") or ""),
    "service": str(payload.get("service") or ""),
    "env": str(payload.get("env") or ""),
    "head_commit": str(payload.get("head_commit") or ""),
  }
  for field, value in source.items():
    if not value:
      raise SnapshotBuilderError(f"runtime_state snapshot missing {field}")

  now = generated_at
  return {
    "schema_version": "dashboard_status_snapshot.v1",
    "snapshot_hash": hash_snapshot(payload),
    "source": source,
    "times": {
      "generated_at": generated_at,
      "published_at": _utc_iso(),
    },
    "safety": {
      "trading_mode": _map_trading_mode(safety.get("trading_mode")),
      "risk_state": _map_risk_state(safety.get("risk_state")),
      "mode_reasons": _safe_str_list(safety.get("mode_reasons")),
      "latches": {
        "open_permission_latched_off": bool(_safe_bool(safety.get("latches", {}).get("open_permission_latched_off"))),
        "market_truth_latched": bool(_safe_bool(safety.get("latches", {}).get("market_truth_latched"))),
      },
      "f1_cert_state": {
        "status": _map_f1_status(safety.get("f1_cert_state", {}).get("status") if isinstance(safety.get("f1_cert_state"), dict) else safety.get("f1_cert_state")),
        "reason_codes": _safe_str_list(
          safety.get("f1_cert_state", {}).get("reason_codes")
          if isinstance(safety.get("f1_cert_state"), dict)
          else safety.get("f1_cert_state"),
        ),
        "last_certified_at": _utc_iso(
          safety.get("f1_cert_state", {}).get("last_certified_at")
          if isinstance(safety.get("f1_cert_state"), dict)
          else None,
        ),
      },
      "owner_view": {"unblock_steps": _safe_str_list(safety.get("owner_view", {}).get("unblock_steps")) if isinstance(safety.get("owner_view"), dict) else []},
    },
    "metrics": {
      "mm_util": _build_metric_from_runtime(metrics.get("mm_util"), "mm_util", now),
      "disk_used_pct": _build_metric_from_runtime(metrics.get("disk_used_pct"), "disk_used_pct", now),
      "wal_queue_depth": _build_metric_from_runtime(metrics.get("wal_queue_depth"), "wal_queue_depth", now),
      "ws_event_lag": _build_metric_from_runtime(metrics.get("ws_event_lag"), "ws_event_lag", now),
      "http_429_count": _build_metric_from_runtime(metrics.get("http_429_count"), "http_429_count", now),
      "deribit_10028_count": _build_metric_from_runtime(metrics.get("deribit_10028_count"), "deribit_10028_count", now),
      "deribit_http_p95": _build_metric_from_runtime(metrics.get("deribit_http_p95"), "deribit_http_p95", now),
    },
    "freshness": {
      "expected_publish_interval_s": _safe_int(freshness.get("expected_publish_interval_s")) or expected_publish_interval_s,
      "stale_after_s": _safe_int(freshness.get("stale_after_s")) or stale_after_s,
    },
    "publisher": {
      "attempt": attempt,
      "publisher_version": publisher_version,
    },
  }


def _build_from_csp_payload(
  payload: Dict[str, Any],
  source_instance_id: str,
  source_service: str,
  source_env: str,
  source_head_commit: str,
  expected_publish_interval_s: int,
  stale_after_s: int,
  generated_at: str,
  publisher_version: str,
  attempt: int = 1,
) -> Dict[str, Any]:
  mm_util = _safe_float(payload.get("mm_util"))
  disk_used_pct = _safe_float(payload.get("disk_used_pct"))
  wal_depth = _safe_float(payload.get("wal_queue_depth"))
  wal_capacity = _safe_float(payload.get("wal_queue_capacity"))
  wal_ratio = None if wal_depth is None or wal_capacity is None or wal_capacity <= 0 else wal_depth / wal_capacity
  ws_event_lag = _safe_float(payload.get("ws_event_lag_ms"))
  http_429 = _safe_float(payload.get("429_count_5m"))
  deribit_10028 = _safe_float(payload.get("10028_count_5m"))
  deribit_http_p95 = _safe_float(payload.get("deribit_http_p95_ms"))

  metric_updated_at = payload.get("loop_tick_last_ts_ms")

  snapshot: Dict[str, Any] = {
    "schema_version": "dashboard_status_snapshot.v1",
    "snapshot_hash": hash_snapshot(payload),
    "source": {
      "instance_id": source_instance_id,
      "service": source_service,
      "env": source_env,
      "head_commit": source_head_commit,
    },
    "times": {
      "generated_at": generated_at,
      "published_at": _utc_iso(),
    },
    "safety": {
      "trading_mode": _map_trading_mode(payload.get("trading_mode")),
      "risk_state": _map_risk_state(payload.get("risk_state")),
      "mode_reasons": _safe_str_list(payload.get("mode_reasons")),
      "latches": {
        "open_permission_latched_off": bool(_safe_bool(payload.get("open_permission_blocked_latch"))),
        "market_truth_latched": bool(_safe_bool(payload.get("connectivity_degraded"))),
      },
      "f1_cert_state": {
        "status": _map_f1_status(payload.get("f1_cert_state")),
        "reason_codes": _extract_reason_codes(payload, "open_permission_reason_codes"),
        "last_certified_at": _utc_iso(payload.get("f1_cert_expires_at")),
      },
      "owner_view": {
        "unblock_steps": _owner_view_steps(payload),
      },
    },
    "metrics": {
      "mm_util": _build_metric(mm_util, "ratio", metric_updated_at, warn=0.70, crit=0.85),
      "disk_used_pct": _build_metric(disk_used_pct, "percent", payload.get("disk_used_last_update_ts_ms"), warn=80.0, crit=90.0),
      "wal_queue_depth": _build_metric(wal_ratio, "count", payload.get("loop_tick_last_ts_ms"), warn=0.70, crit=0.90),
      "ws_event_lag": _build_metric(ws_event_lag, "ms", payload.get("loop_tick_last_ts_ms"), warn=250.0, crit=500.0),
      "http_429_count": _build_metric(http_429, "count", payload.get("loop_tick_last_ts_ms"), warn=1.0, crit=3.0),
      "deribit_10028_count": _build_metric(deribit_10028, "count", payload.get("loop_tick_last_ts_ms"), warn=1.0, crit=3.0),
      "deribit_http_p95": _build_metric(deribit_http_p95, "ms", payload.get("loop_tick_last_ts_ms"), warn=250.0, crit=500.0),
    },
    "freshness": {
      "expected_publish_interval_s": expected_publish_interval_s,
      "stale_after_s": stale_after_s,
    },
    "publisher": {
      "attempt": attempt,
      "publisher_version": publisher_version,
    },
  }

  if disk_used_pct is None:
    snapshot["metrics"]["disk_used_pct"] = _build_metric(None, "percent", payload.get("disk_used_last_update_ts_ms"), warn=80.0, crit=90.0)

  if mm_util is None:
    snapshot["metrics"]["mm_util"] = _enforce_unavailable_metric(None, "ratio", payload.get("mm_util_last_update_ts_ms"))

  if wal_ratio is None:
    snapshot["metrics"]["wal_queue_depth"] = _build_metric(None, "count", payload.get("loop_tick_last_ts_ms"), warn=0.70, crit=0.90)

  if ws_event_lag is None:
    snapshot["metrics"]["ws_event_lag"] = _build_metric(None, "ms", payload.get("loop_tick_last_ts_ms"), warn=250.0, crit=500.0)

  if http_429 is None:
    snapshot["metrics"]["http_429_count"] = _build_metric(None, "count", payload.get("loop_tick_last_ts_ms"), warn=1.0, crit=3.0)

  if deribit_10028 is None:
    snapshot["metrics"]["deribit_10028_count"] = _build_metric(None, "count", payload.get("loop_tick_last_ts_ms"), warn=1.0, crit=3.0)

  if deribit_http_p95 is None:
    snapshot["metrics"]["deribit_http_p95"] = _build_metric(None, "ms", payload.get("loop_tick_last_ts_ms"), warn=250.0, crit=500.0)

  return snapshot


def build_snapshot_envelope(
  payload: Dict[str, Any],
  *,
  instance_id: str,
  service: str,
  env: str,
  head_commit: str,
  expected_publish_interval_s: int,
  stale_after_s: int,
  generated_at: str,
  publisher_version: str,
  attempt: int = 1,
) -> Dict[str, Any]:
  if not isinstance(payload, dict):
    raise SnapshotBuilderError("source payload must be an object")

  if payload.get("schema_version") == RUNTIME_STATE_VERSION:
    return _build_from_runtime_payload(
      payload,
      generated_at=generated_at,
      attempt=attempt,
      expected_publish_interval_s=expected_publish_interval_s,
      stale_after_s=stale_after_s,
      publisher_version=publisher_version,
    )

  return _build_from_csp_payload(
    payload=payload,
    source_instance_id=instance_id,
    source_service=service,
    source_env=env,
    source_head_commit=head_commit,
    expected_publish_interval_s=expected_publish_interval_s,
    stale_after_s=stale_after_s,
    generated_at=generated_at,
    publisher_version=publisher_version,
    attempt=attempt,
  )
