from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
import logging
import os
from pathlib import Path
import time
from typing import Any, Dict, Optional

import urllib.error
import urllib.request

from .spool import SpoolStore
from .state import SidecarState, load_state, save_state
from .transform import (
  RUNTIME_STATE_VERSION,
  SnapshotBuilderError,
  build_snapshot_envelope,
  hash_snapshot,
)


LOG = logging.getLogger("status_publisher")


def _utc_now_iso() -> str:
  return datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


@dataclass(frozen=True)
class PublisherConfig:
  source_snapshot_path: Path
  state_path: Path
  spool_db_path: Path
  log_path: Path
  convex_endpoint: str
  convex_secret: str | None
  instance_id: str
  service: str
  env: str
  head_commit: str
  expected_publish_interval_s: int
  stale_after_s: int
  poll_interval_s: int
  publisher_version: str
  max_attempts: int
  request_timeout_s: float


def _load_config() -> PublisherConfig:
  repo_root = Path(__file__).resolve().parents[1]
  return PublisherConfig(
    source_snapshot_path=Path(
      os.getenv(
        "STATUS_SOURCE_PATH",
        str(repo_root / "var" / "runtime" / "runtime_state.json"),
      )
    ),
    state_path=Path(os.getenv("STATUS_PUBLISHER_STATE_PATH", str(repo_root / "var" / "status_publisher" / "state.json"))),
    spool_db_path=Path(os.getenv("STATUS_PUBLISHER_SPOOL_DB_PATH", str(repo_root / "var" / "status_publisher" / "spool.db"))),
    log_path=Path(os.getenv("STATUS_PUBLISHER_LOG_PATH", str(repo_root / "var" / "status_publisher" / "logs" / "publisher.log"))),
    convex_endpoint=os.getenv("CONVEX_PUBLISH_ENDPOINT", ""),
    convex_secret=os.getenv("CONVEX_PUBLISH_SECRET") or None,
    instance_id=os.getenv("STATUS_PUBLISHER_INSTANCE_ID", os.getenv("HOSTNAME", "soldier-main-01")),
    service=os.getenv("STATUS_PUBLISHER_SERVICE", "soldier_core"),
    env=os.getenv("STATUS_PUBLISHER_ENV", os.getenv("ENVIRONMENT", "paper")),
    head_commit=os.getenv("STATUS_PUBLISHER_HEAD_COMMIT", os.getenv("HEAD_COMMIT", "unknown")),
    expected_publish_interval_s=int(os.getenv("STATUS_PUBLISHER_EXPECTED_INTERVAL_S", "2")),
    stale_after_s=int(os.getenv("STATUS_PUBLISHER_STALE_AFTER_S", "15")),
    poll_interval_s=int(os.getenv("STATUS_PUBLISHER_POLL_INTERVAL_S", "2")),
    publisher_version=os.getenv("STATUS_PUBLISHER_VERSION", "status-publisher.v1"),
    max_attempts=int(os.getenv("STATUS_PUBLISHER_MAX_ATTEMPTS", "6")),
    request_timeout_s=float(os.getenv("STATUS_PUBLISHER_REQUEST_TIMEOUT", "5.0")),
  )


def _configure_logging(log_path: Path) -> None:
  LOG.setLevel(logging.INFO)
  log_path.parent.mkdir(parents=True, exist_ok=True)
  file_handler = logging.FileHandler(log_path)
  stream_handler = logging.StreamHandler()
  formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
  file_handler.setFormatter(formatter)
  stream_handler.setFormatter(formatter)
  LOG.addHandler(file_handler)
  LOG.addHandler(stream_handler)
  LOG.propagate = False


def _load_source_snapshot(path: Path) -> Dict[str, Any]:
  try:
    raw = json.loads(path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError) as exc:
    raise RuntimeError(f"failed reading source snapshot: {exc}")
  if not isinstance(raw, dict):
    raise RuntimeError("source snapshot must be an object")
  return raw


def _attempt_backoff(base_seconds: int, attempt: int) -> int:
  return min(base_seconds * (2 ** max(attempt - 1, 0)), 60)


def _http_post_envelope(endpoint: str, secret: Optional[str], payload: Dict[str, Any], timeout: float) -> tuple[bool, bool, str]:
  data = json.dumps(payload, sort_keys=True).encode("utf-8")
  req = urllib.request.Request(
    endpoint,
    data=data,
    method="POST",
    headers={"Content-Type": "application/json"},
  )
  if secret:
    req.add_header("Authorization", f"Bearer {secret}")

  try:
    with urllib.request.urlopen(req, timeout=timeout) as response:
      status_code = response.getcode() or 0
      body = response.read()
      if status_code >= 200 and status_code < 300:
        return True, False, str(status_code)
      if status_code == 409:
        return True, False, f"HTTP {status_code}: {body.decode('utf-8', errors='ignore')}".strip()
      retryable = status_code in {429, 500, 502, 503, 504}
      return False, retryable, f"HTTP {status_code}: {body.decode('utf-8', errors='ignore')}".strip()
  except urllib.error.URLError as exc:
    return False, True, f"URLError: {exc}"
  except Exception as exc:
    return False, True, f"ERROR: {exc}"


def _derive_generated_at(payload: Dict[str, Any], source_mtime_ms: float) -> str:
  if payload.get("schema_version") == RUNTIME_STATE_VERSION and isinstance(payload.get("generated_at"), str):
    return payload["generated_at"]

  for key in ("generated_at", "last_policy_update_ts", "last_policy_update_ts_ms", "loop_tick_last_ts_ms"):
    value = payload.get(key)
    if value is None:
      continue
    if isinstance(value, str) and value:
      return value
    if isinstance(value, (int, float)) and value > 0:
      try:
        from datetime import datetime

        return datetime.fromtimestamp(value / 1000.0, tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
      except (OverflowError, OSError, ValueError):
        break
  return datetime.fromtimestamp(source_mtime_ms / 1000.0, tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _validate_csp_payload_like(payload: Dict[str, Any]) -> list[str]:
  issues: list[str] = []

  if payload.get("status_schema_version") != 1:
    issues.append("status_schema_version must be 1")

  if not isinstance(payload.get("contract_version"), str):
    issues.append("contract_version must be a string")

  if payload.get("trading_mode") not in {"Active", "ReduceOnly", "Kill"}:
    issues.append("trading_mode must be Active|ReduceOnly|Kill")

  if payload.get("risk_state") not in {"Healthy", "Degraded", "Maintenance"}:
    issues.append("risk_state invalid")

  return issues


def _process_once(config: PublisherConfig, spool: SpoolStore, state: SidecarState) -> SidecarState:
  source = _load_source_snapshot(config.source_snapshot_path)
  mtime = config.source_snapshot_path.stat().st_mtime
  issues: list[str] = []
  if source.get("schema_version") != RUNTIME_STATE_VERSION:
    issues = validate_csp_payload_like(source)

  if issues:
    LOG.warning("source validation failed: %s", ", ".join(issues))
    return state.with_send_failure(
      code="VALIDATION_ERROR",
      permanent=True,
    )

  generated_at = _derive_generated_at(source, mtime)
  try:
    snapshot = build_snapshot_envelope(
      source,
      instance_id=config.instance_id,
      service=config.service,
      env=config.env,
      head_commit=config.head_commit,
      expected_publish_interval_s=config.expected_publish_interval_s,
      stale_after_s=config.stale_after_s,
      generated_at=generated_at,
      publisher_version=config.publisher_version,
      attempt=1,
    )
  except SnapshotBuilderError as exc:
    LOG.error("snapshot build failed: %s", exc)
    return state.with_send_failure(code="BUILD_ERROR", permanent=True)

  snapshot_hash = hash_snapshot(source)
  state = state.with_seen(snapshot_hash, generated_at)

  payload_json = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
  now = _utc_now_iso()
  inserted = spool.enqueue(
    snapshot_hash=snapshot_hash,
    instance_id=config.instance_id,
    generated_at=generated_at,
    payload_json=payload_json,
    next_attempt_at=now,
  )
  if not inserted:
    state = state.with_dedup()
    save_state(config.state_path, state)
    LOG.info("duplicate snapshot_hash=%s", snapshot_hash)
    return state

  state = state.with_queued()
  save_state(config.state_path, state)
  LOG.info("queued snapshot_hash=%s", snapshot_hash)

  rows = spool.ready_rows(limit=10)
  for row in rows:
    attempt = row.attempt_count + 1
    payload = dict(row.payload)
    publisher_info = payload.get("publisher")
    if isinstance(publisher_info, dict):
      publisher_info["attempt"] = attempt
    else:
      payload["publisher"] = {"attempt": attempt, "publisher_version": config.publisher_version}
    ok, retryable, detail = _http_post_envelope(
      config.convex_endpoint,
      config.convex_secret,
      payload,
      timeout=config.request_timeout_s,
    )
    if ok:
      sent_at = _utc_now_iso()
      spool.mark_success(row.id, sent_at)
      state = state.with_send_success(row.snapshot_hash, sent_at)
      LOG.info("sent snapshot_hash=%s", row.snapshot_hash)
      continue

    error_code = detail.split(":", maxsplit=1)[0].strip().replace(" ", "_") or "TRANSIENT_ERROR"
    delay = _attempt_backoff(5, attempt)
    next_attempt = datetime.fromtimestamp(time.time() + delay, tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    if retryable and attempt < config.max_attempts:
      spool.mark_retry(row.id, attempt, next_attempt, error_code, detail)
      state = state.with_send_failure(error_code, permanent=False)
      LOG.warning("retry snapshot_hash=%s attempt=%s", row.snapshot_hash, attempt)
      continue

    spool.mark_perm_failure(row.id, attempt, error_code, detail)
    state = state.with_send_failure(error_code, permanent=True)
    LOG.error("permanent failure snapshot_hash=%s", row.snapshot_hash)

  spool.apply_retention()
  save_state(config.state_path, state)
  return state


def run_loop(config: PublisherConfig) -> None:
  _configure_logging(config.log_path)
  spool = SpoolStore(config.spool_db_path)
  try:
    state = load_state(config.state_path, config.instance_id)
    while True:
      state = _process_once(config, spool, state)
      save_state(config.state_path, state)
      time.sleep(config.poll_interval_s)
  finally:
    spool.close()


def main() -> int:
  config = _load_config()
  if not config.convex_endpoint:
    LOG.error("missing CONVEX_PUBLISH_ENDPOINT")
    return 1
  run_loop(config)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
