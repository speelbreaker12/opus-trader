from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from http.client import HTTPConnection, HTTPSConnection
import json
import logging
import os
import random
import socket
import time
from pathlib import Path
from typing import Any, Dict, Optional
from urllib.parse import urlparse

from .spool import SpoolStore
from .state import SidecarState, load_state, save_state
from .transform import (
  RUNTIME_STATE_VERSION,
  SnapshotBuilderError,
  build_snapshot_envelope,
  hash_snapshot,
)


LOG = logging.getLogger("status_publisher")


RUNTIME_FILE_MISSING = "RUNTIME_FILE_MISSING"
RUNTIME_FILE_READ_ERROR = "RUNTIME_FILE_READ_ERROR"
RUNTIME_JSON_PARSE_ERROR = "RUNTIME_JSON_PARSE_ERROR"
RUNTIME_SCHEMA_UNSUPPORTED = "RUNTIME_SCHEMA_UNSUPPORTED"
RUNTIME_SCHEMA_INVALID = "RUNTIME_SCHEMA_INVALID"
RUNTIME_SNAPSHOT_STALE = "RUNTIME_SNAPSHOT_STALE"
RUNTIME_HEAD_COMMIT_INVALID = "RUNTIME_HEAD_COMMIT_INVALID"

SNAPSHOT_HASH_COMPUTE_ERROR = "SNAPSHOT_HASH_COMPUTE_ERROR"
SNAPSHOT_DUPLICATE_SKIPPED = "SNAPSHOT_DUPLICATE_SKIPPED"
SNAPSHOT_NORMALIZE_ERROR = "SNAPSHOT_NORMALIZE_ERROR"

SPOOL_DB_OPEN_ERROR = "SPOOL_DB_OPEN_ERROR"
SPOOL_INSERT_ERROR = "SPOOL_INSERT_ERROR"
SPOOL_UPDATE_ERROR = "SPOOL_UPDATE_ERROR"
SPOOL_QUERY_ERROR = "SPOOL_QUERY_ERROR"

STATE_FILE_WRITE_ERROR = "STATE_FILE_WRITE_ERROR"

HTTP_CONNECT_TIMEOUT = "HTTP_CONNECT_TIMEOUT"
HTTP_READ_TIMEOUT = "HTTP_READ_TIMEOUT"
HTTP_REQUEST_ERROR = "HTTP_REQUEST_ERROR"
HTTP_STATUS_4XX = "HTTP_STATUS_4XX"
HTTP_STATUS_429 = "HTTP_STATUS_429"
HTTP_STATUS_5XX = "HTTP_STATUS_5XX"

CONVEX_AUTH_ERROR = "CONVEX_AUTH_ERROR"
CONVEX_RATE_LIMITED = "CONVEX_RATE_LIMITED"
CONVEX_RESPONSE_INVALID = "CONVEX_RESPONSE_INVALID"
CONVEX_UPSERT_REJECTED = "CONVEX_UPSERT_REJECTED"

PERM_SCHEMA_MISMATCH = "PERM_SCHEMA_MISMATCH"
PERM_MISSING_REQUIRED_FIELD = "PERM_MISSING_REQUIRED_FIELD"
PERM_INVALID_ENUM = "PERM_INVALID_ENUM"
PERM_INVALID_TIMESTAMP = "PERM_INVALID_TIMESTAMP"


def _utc_now_iso() -> str:
  return datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _parse_positive_int(name: str, default: int) -> int:
  raw = os.getenv(name)
  if raw is None:
    return default
  try:
    value = int(raw)
  except (TypeError, ValueError):
    return default
  return value if value > 0 else default


def _parse_positive_float(name: str, default: float) -> float:
  raw = os.getenv(name)
  if raw is None:
    return default
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return default
  return value if value > 0 else default


def _parse_total_timeout(default: float = 8.0) -> float:
  raw = os.getenv("STATUS_PUBLISHER_REQUEST_TIMEOUT")
  if raw is None:
    return default
  try:
    value = float(raw)
  except (TypeError, ValueError):
    return default
  return value if value > 0 else default


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
  connect_timeout_s: float
  read_timeout_s: float
  request_total_timeout_s: float


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
    expected_publish_interval_s=_parse_positive_int("STATUS_PUBLISHER_EXPECTED_INTERVAL_S", 2),
    stale_after_s=_parse_positive_int("STATUS_PUBLISHER_STALE_AFTER_S", 15),
    poll_interval_s=_parse_positive_int("STATUS_PUBLISHER_POLL_INTERVAL_S", 2),
    publisher_version=os.getenv("STATUS_PUBLISHER_VERSION", "status-publisher.v1"),
    max_attempts=_parse_positive_int("STATUS_PUBLISHER_MAX_ATTEMPTS", 6),
    connect_timeout_s=_parse_positive_float("STATUS_PUBLISH_CONNECT_TIMEOUT", 2.0),
    read_timeout_s=_parse_positive_float("STATUS_PUBLISH_READ_TIMEOUT", 5.0),
    request_total_timeout_s=_parse_total_timeout(8.0),
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


def _parse_utc_timestamp(value: object) -> datetime:
  if not isinstance(value, str) or not value.endswith("Z"):
    raise PublisherError(
      PERM_INVALID_TIMESTAMP,
      "runtime_state.generated_at must be UTC ISO-8601 string ending with Z",
    )
  try:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))
  except (OverflowError, OSError, ValueError) as exc:
    raise PublisherError(PERM_INVALID_TIMESTAMP, f"runtime_state.generated_at is not a valid timestamp: {exc}") from exc


def _is_snapshot_stale(generated_at: datetime, stale_after_s: int) -> bool:
  age_seconds = (datetime.now(tz=timezone.utc) - generated_at).total_seconds()
  return age_seconds > stale_after_s


def _ensure_runtime_schema(payload: Dict[str, Any]) -> None:
  if not isinstance(payload, dict):
    raise PublisherError(RUNTIME_SCHEMA_INVALID, "runtime source must be an object")

  schema_version = payload.get("schema_version")
  if not isinstance(schema_version, str):
    raise PublisherError(RUNTIME_SCHEMA_INVALID, "runtime_state.schema_version missing or not a string")
  if schema_version != RUNTIME_STATE_VERSION:
    raise PublisherError(
      RUNTIME_SCHEMA_UNSUPPORTED,
      f"runtime_state.schema_version must be {RUNTIME_STATE_VERSION}, got {schema_version}",
    )


class PublisherError(Exception):
  def __init__(self, code: str, detail: str, *, permanent: bool = True):
    super().__init__(detail)
    self.code = code
    self.permanent = permanent


def _load_source_snapshot(path: Path) -> Dict[str, Any]:
  if not path.exists():
    raise PublisherError(RUNTIME_FILE_MISSING, f"runtime source file not found: {path}", permanent=False)
  try:
    payload = json.loads(path.read_text(encoding="utf-8"))
  except OSError as exc:
    raise PublisherError(RUNTIME_FILE_READ_ERROR, f"failed to read runtime source file: {exc}", permanent=False)
  except json.JSONDecodeError as exc:
    raise PublisherError(RUNTIME_JSON_PARSE_ERROR, f"runtime source JSON invalid: {exc}", permanent=False)

  if not isinstance(payload, dict):
    raise PublisherError(RUNTIME_SCHEMA_INVALID, "runtime source must be an object")
  return payload


def _classify_snapshot_builder_error(exc: SnapshotBuilderError) -> str:
  message = str(exc).lower()

  if "schema_version" in message and "runtime_state.v1" in message:
    return RUNTIME_SCHEMA_UNSUPPORTED
  if "head_commit" in message and "7-40" in message:
    return RUNTIME_HEAD_COMMIT_INVALID
  if "generated_at" in message and ("iso-8601" in message or "timestamp" in message):
    return PERM_INVALID_TIMESTAMP
  if "must be one of" in message:
    return PERM_INVALID_ENUM
  if "missing required field" in message:
    return PERM_MISSING_REQUIRED_FIELD
  if "must be" in message and "string" in message and "trading_mode" in message:
    return PERM_INVALID_ENUM
  return SNAPSHOT_NORMALIZE_ERROR


def _attempt_delay_seconds(attempt: int) -> float:
  base = 1.0
  cap = 60.0
  delay = min(base * (2 ** max(attempt - 1, 0)), cap)
  return delay * random.uniform(0.8, 1.2)


@dataclass(frozen=True)
class HttpTransportResult:
  ok: bool
  retryable: bool
  code: str
  detail: str


def _http_post_envelope(
  endpoint: str,
  secret: Optional[str],
  payload: Dict[str, Any],
  *,
  connect_timeout_s: float,
  read_timeout_s: float,
  total_timeout_s: float,
) -> HttpTransportResult:
  parsed = urlparse(endpoint)
  if parsed.scheme not in {"http", "https"} or not parsed.hostname:
    return HttpTransportResult(False, False, HTTP_REQUEST_ERROR, f"unsupported endpoint: {endpoint}")

  request_path = parsed.path or "/"
  if parsed.query:
    request_path = f"{request_path}?{parsed.query}"

  conn = (
    HTTPSConnection(parsed.hostname, port=parsed.port, timeout=connect_timeout_s)
    if parsed.scheme == "https"
    else HTTPConnection(parsed.hostname, port=parsed.port, timeout=connect_timeout_s)
  )

  headers = {"Content-Type": "application/json"}
  if secret:
    headers["Authorization"] = f"Bearer {secret}"

  body = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
  headers["Content-Length"] = str(len(body))

  request_started_at = time.monotonic()
  deadline = request_started_at + max(total_timeout_s, 0.001)
  response = None
  phase = "connect"
  try:
    if time.monotonic() >= deadline:
      return HttpTransportResult(False, True, HTTP_READ_TIMEOUT, "total request timeout exceeded before request send")
    conn.request("POST", request_path, body=body, headers=headers)
    phase = "read"
    # response/headers read phase
    if conn.sock is not None:
      remaining = max(0.0, deadline - time.monotonic())
      if remaining <= 0:
        return HttpTransportResult(False, True, HTTP_READ_TIMEOUT, "total request timeout exceeded before read")
      conn.sock.settimeout(min(read_timeout_s, remaining))

    response = conn.getresponse()
    response_body = response.read().decode("utf-8", errors="ignore").strip()
    status_code = response.status
    if time.monotonic() >= deadline:
      return HttpTransportResult(False, True, HTTP_READ_TIMEOUT, "total request timeout exceeded while reading response")

    if status_code >= 200 and status_code < 300:
      try:
        parsed_response = json.loads(response_body or "{}")
      except json.JSONDecodeError as exc:
        return HttpTransportResult(False, False, CONVEX_RESPONSE_INVALID, f"response must be JSON: {exc}")

      if not isinstance(parsed_response, dict):
        return HttpTransportResult(False, False, CONVEX_RESPONSE_INVALID, "response must be an object")
      duplicate_flag = parsed_response.get("duplicate")
      if duplicate_flag not in (True, False):
        return HttpTransportResult(False, False, CONVEX_RESPONSE_INVALID, "response missing duplicate field")
      return HttpTransportResult(True, False, "", response_body)

    if status_code == 409:
      return HttpTransportResult(True, False, "", response_body)
    if status_code == 429:
      return HttpTransportResult(False, True, CONVEX_RATE_LIMITED, f"HTTP {status_code}: {response_body}")
    if status_code in {400, 422}:
      return HttpTransportResult(False, False, CONVEX_UPSERT_REJECTED, f"HTTP {status_code}: {response_body}")
    if status_code in {401, 403}:
      return HttpTransportResult(False, False, CONVEX_AUTH_ERROR, f"HTTP {status_code}: {response_body}")
    if status_code == 404:
      return HttpTransportResult(False, False, HTTP_STATUS_4XX, f"HTTP {status_code}: {response_body}")
    if status_code >= 500 and status_code < 600:
      return HttpTransportResult(False, True, HTTP_STATUS_5XX, f"HTTP {status_code}: {response_body}")

    return HttpTransportResult(False, False, HTTP_STATUS_4XX, f"HTTP {status_code}: {response_body}")
  except socket.timeout as exc:
    if time.monotonic() >= deadline:
      return HttpTransportResult(False, True, HTTP_READ_TIMEOUT, f"total request timeout exceeded: {exc}")
    if phase == "connect":
      return HttpTransportResult(False, True, HTTP_CONNECT_TIMEOUT, f"connect timeout: {exc}")
    return HttpTransportResult(False, True, HTTP_READ_TIMEOUT, f"read timeout: {exc}")
  except Exception as exc:  # pragma: no cover - transport transport errors
    return HttpTransportResult(False, True, HTTP_REQUEST_ERROR, f"transport failure: {exc}")
  finally:
    try:
      if response is not None:
        response.close()
    finally:
      conn.close()


def _safe_spool_enqueue(
  spool: SpoolStore,
  *,
  snapshot_hash: str,
  instance_id: str,
  generated_at: str,
  payload_json: str,
  next_attempt_at: str,
) -> bool:
  try:
    return spool.enqueue(
      snapshot_hash=snapshot_hash,
      instance_id=instance_id,
      generated_at=generated_at,
      payload_json=payload_json,
      next_attempt_at=next_attempt_at,
    )
  except Exception as exc:
    raise PublisherError(SPOOL_INSERT_ERROR, f"spool enqueue failed: {exc}", permanent=False) from exc


def _safe_ready_rows(spool: SpoolStore, *, limit: int) -> list:
  try:
    return spool.ready_rows(limit=limit)
  except Exception as exc:
    raise PublisherError(SPOOL_QUERY_ERROR, f"spool query failed: {exc}", permanent=False) from exc


def _safe_mark_success(spool: SpoolStore, row_id: int, sent_at: str) -> None:
  try:
    spool.mark_success(row_id, sent_at)
  except Exception as exc:
    raise PublisherError(SPOOL_UPDATE_ERROR, f"spool mark_success failed: {exc}", permanent=False) from exc


def _safe_mark_retry(
  spool: SpoolStore,
  row_id: int,
  attempt_count: int,
  next_attempt_at: str,
  error_code: str,
  detail: str,
) -> None:
  try:
    spool.mark_retry(row_id, attempt_count, next_attempt_at, error_code, detail)
  except Exception as exc:
    raise PublisherError(SPOOL_UPDATE_ERROR, f"spool mark_retry failed: {exc}", permanent=False) from exc


def _safe_mark_perm_failure(spool: SpoolStore, row_id: int, attempt_count: int, error_code: str, detail: str) -> None:
  try:
    spool.mark_perm_failure(row_id, attempt_count, error_code, detail)
  except Exception as exc:
    raise PublisherError(SPOOL_UPDATE_ERROR, f"spool mark_perm_failure failed: {exc}", permanent=False) from exc


def _safe_apply_retention(spool: SpoolStore) -> None:
  try:
    spool.apply_retention()
  except Exception as exc:
    raise PublisherError(SPOOL_UPDATE_ERROR, f"spool retention failed: {exc}", permanent=False) from exc


def _safe_save_state(path: Path, state: SidecarState) -> None:
  try:
    save_state(path, state)
  except Exception as exc:
    raise PublisherError(STATE_FILE_WRITE_ERROR, f"failed to write state file: {exc}", permanent=False) from exc


def _process_once(config: PublisherConfig, spool: SpoolStore, state: SidecarState) -> SidecarState:
  source = _load_source_snapshot(config.source_snapshot_path)
  _ensure_runtime_schema(source)

  generated_at = source.get("generated_at")
  generated_at_dt = _parse_utc_timestamp(generated_at)
  try:
    snapshot_hash = hash_snapshot(source)
  except Exception as exc:
    raise PublisherError(SNAPSHOT_HASH_COMPUTE_ERROR, f"failed to hash snapshot: {exc}", permanent=False) from exc

  previous_last_seen_hash = state.last_seen_snapshot_hash
  state = state.with_seen(snapshot_hash, generated_at)

  if snapshot_hash == previous_last_seen_hash:
    LOG.info("%s snapshot_hash=%s", SNAPSHOT_DUPLICATE_SKIPPED, snapshot_hash)
    return state.with_dedup().with_last_error(SNAPSHOT_DUPLICATE_SKIPPED)

  if _is_snapshot_stale(generated_at_dt, config.stale_after_s):
    raise PublisherError(
      RUNTIME_SNAPSHOT_STALE,
      f"snapshot older than stale_after_s={config.stale_after_s}s",
      permanent=False,
    )

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
    code = _classify_snapshot_builder_error(exc)
    raise PublisherError(code, f"snapshot build failed: {exc}", permanent=True) from exc

  payload_json = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
  inserted = _safe_spool_enqueue(
    spool,
    snapshot_hash=snapshot_hash,
    instance_id=config.instance_id,
    generated_at=generated_at,
    payload_json=payload_json,
    next_attempt_at=_utc_now_iso(),
  )
  if not inserted:
    LOG.info("%s snapshot_hash=%s", SNAPSHOT_DUPLICATE_SKIPPED, snapshot_hash)
    return state.with_dedup().with_last_error(SNAPSHOT_DUPLICATE_SKIPPED)

  state = state.with_queued()

  rows = _safe_ready_rows(spool, limit=1)
  if not rows:
    return state

  row = rows[0]
  attempt = row.attempt_count + 1
  payload = dict(row.payload)
  publisher_info = payload.get("publisher")
  if isinstance(publisher_info, dict):
    publisher_info["attempt"] = attempt
  else:
    payload["publisher"] = {"attempt": attempt, "publisher_version": config.publisher_version}

  result = _http_post_envelope(
    config.convex_endpoint,
    config.convex_secret,
    payload,
    connect_timeout_s=config.connect_timeout_s,
    read_timeout_s=config.read_timeout_s,
    total_timeout_s=config.request_total_timeout_s,
  )

  if result.ok:
    sent_at = _utc_now_iso()
    _safe_mark_success(spool, row.id, sent_at)
    LOG.info("sent snapshot_hash=%s", row.snapshot_hash)
    return state.with_send_success(row.snapshot_hash, sent_at)

  if result.retryable and attempt < config.max_attempts:
    delay = _attempt_delay_seconds(attempt)
    next_attempt = datetime.fromtimestamp(
      time.time() + delay,
      tz=timezone.utc,
    ).isoformat(timespec="seconds").replace("+00:00", "Z")
    _safe_mark_retry(spool, row.id, attempt, next_attempt, result.code, result.detail)
    return state.with_send_failure(result.code, permanent=False)

  _safe_mark_perm_failure(spool, row.id, attempt, result.code, result.detail)
  LOG.error("permanent delivery failure snapshot_hash=%s code=%s detail=%s", row.snapshot_hash, result.code, result.detail)
  return state.with_send_failure(result.code, permanent=True)


def run_loop(config: PublisherConfig) -> None:
  _configure_logging(config.log_path)
  state = load_state(config.state_path, config.instance_id)
  while True:
    try:
      spool = SpoolStore(config.spool_db_path)
    except Exception as exc:
      state = state.with_send_failure(SPOOL_DB_OPEN_ERROR, permanent=False)
      LOG.error("failed to open spool db: %s", exc)
      try:
        _safe_save_state(config.state_path, state)
      except PublisherError as save_error:
        LOG.error("state write error code=%s detail=%s", save_error.code, save_error)
        state = state.with_send_failure(save_error.code, permanent=False)
      time.sleep(config.poll_interval_s)
      continue

    try:
      try:
        state = _process_once(config, spool, state)
      except PublisherError as exc:
        state = state.with_send_failure(exc.code, permanent=exc.permanent)
        LOG.error("processing error code=%s detail=%s", exc.code, exc)
      try:
        _safe_apply_retention(spool)
      except PublisherError as exc:
        state = state.with_send_failure(exc.code, permanent=False)
        LOG.error("state retention error code=%s detail=%s", exc.code, exc)
    except Exception as exc:  # pragma: no cover - defensive
      state = state.with_send_failure(HTTP_REQUEST_ERROR, permanent=False)
      LOG.exception("unexpected processing error: %s", exc)
    finally:
      spool.close()

    try:
      _safe_save_state(config.state_path, state)
    except PublisherError as exc:
      LOG.error("state write error code=%s detail=%s", exc.code, exc)
      state = state.with_send_failure(exc.code, permanent=False)
    time.sleep(config.poll_interval_s)


def main() -> int:
  config = _load_config()
  if not config.convex_endpoint:
    LOG.error("missing CONVEX_PUBLISH_ENDPOINT")
    return 1
  run_loop(config)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
