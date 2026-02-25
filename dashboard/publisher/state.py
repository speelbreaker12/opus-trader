from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import os
from typing import Any, Dict


STATE_SCHEMA_VERSION = "status_publisher_state.v1"


def _utc_now_iso() -> str:
  return datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _coerce_non_negative_int(value: Any) -> int | None:
  if isinstance(value, bool):
    return None
  if isinstance(value, int):
    return value if value >= 0 else None
  return None


@dataclass(frozen=True)
class SidecarTotals:
  seen: int
  deduped: int
  queued: int
  sent: int
  failed: int

  def to_dict(self) -> Dict[str, int]:
    return {
      "seen": self.seen,
      "deduped": self.deduped,
      "queued": self.queued,
      "sent": self.sent,
      "failed": self.failed,
    }


@dataclass(frozen=True)
class SidecarState:
  schema_version: str
  instance_id: str
  last_seen_snapshot_hash: str | None
  last_seen_snapshot_seq: int | None
  last_sent_snapshot_hash: str | None
  last_seen_generated_at: str | None
  last_success_at: str | None
  last_error_at: str | None
  last_error_code: str | None
  consecutive_failures: int
  totals: SidecarTotals

  def with_seen(
    self,
    snapshot_hash: str,
    generated_at: str | None,
    snapshot_seq: int | None,
  ) -> "SidecarState":
    return SidecarState(
      schema_version=self.schema_version,
      instance_id=self.instance_id,
      last_seen_snapshot_hash=snapshot_hash,
      last_seen_snapshot_seq=snapshot_seq,
      last_sent_snapshot_hash=self.last_sent_snapshot_hash,
      last_seen_generated_at=generated_at,
      last_success_at=self.last_success_at,
      last_error_at=self.last_error_at,
      last_error_code=self.last_error_code,
      consecutive_failures=self.consecutive_failures,
      totals=SidecarTotals(
        seen=self.totals.seen + 1,
        deduped=self.totals.deduped,
        queued=self.totals.queued,
        sent=self.totals.sent,
        failed=self.totals.failed,
      ),
    )

  def with_dedup(self) -> "SidecarState":
    return SidecarState(
      schema_version=self.schema_version,
      instance_id=self.instance_id,
      last_seen_snapshot_hash=self.last_seen_snapshot_hash,
      last_seen_snapshot_seq=self.last_seen_snapshot_seq,
      last_sent_snapshot_hash=self.last_sent_snapshot_hash,
      last_seen_generated_at=self.last_seen_generated_at,
      last_success_at=self.last_success_at,
      last_error_at=self.last_error_at,
      last_error_code=self.last_error_code,
      consecutive_failures=self.consecutive_failures,
      totals=SidecarTotals(
        seen=self.totals.seen,
        deduped=self.totals.deduped + 1,
        queued=self.totals.queued,
        sent=self.totals.sent,
        failed=self.totals.failed,
      ),
    )

  def with_queued(self) -> "SidecarState":
    return SidecarState(
      schema_version=self.schema_version,
      instance_id=self.instance_id,
      last_seen_snapshot_hash=self.last_seen_snapshot_hash,
      last_seen_snapshot_seq=self.last_seen_snapshot_seq,
      last_sent_snapshot_hash=self.last_sent_snapshot_hash,
      last_seen_generated_at=self.last_seen_generated_at,
      last_success_at=self.last_success_at,
      last_error_at=self.last_error_at,
      last_error_code=self.last_error_code,
      consecutive_failures=self.consecutive_failures,
      totals=SidecarTotals(
        seen=self.totals.seen,
        deduped=self.totals.deduped,
        queued=self.totals.queued + 1,
        sent=self.totals.sent,
        failed=self.totals.failed,
      ),
    )

  def with_send_success(self, snapshot_hash: str, published_at: str) -> "SidecarState":
    return SidecarState(
      schema_version=self.schema_version,
      instance_id=self.instance_id,
      last_seen_snapshot_hash=self.last_seen_snapshot_hash,
      last_seen_snapshot_seq=self.last_seen_snapshot_seq,
      last_sent_snapshot_hash=snapshot_hash,
      last_seen_generated_at=self.last_seen_generated_at,
      last_success_at=published_at,
      last_error_at=None,
      last_error_code=None,
      consecutive_failures=0,
      totals=SidecarTotals(
        seen=self.totals.seen,
        deduped=self.totals.deduped,
        queued=self.totals.queued,
        sent=self.totals.sent + 1,
        failed=self.totals.failed,
      ),
    )

  def with_send_failure(self, code: str, *, permanent: bool = False) -> "SidecarState":
    return SidecarState(
      schema_version=self.schema_version,
      instance_id=self.instance_id,
      last_seen_snapshot_hash=self.last_seen_snapshot_hash,
      last_seen_snapshot_seq=self.last_seen_snapshot_seq,
      last_sent_snapshot_hash=self.last_sent_snapshot_hash,
      last_seen_generated_at=self.last_seen_generated_at,
      last_success_at=self.last_success_at,
      last_error_at=_utc_now_iso(),
      last_error_code=code,
      consecutive_failures=self.consecutive_failures + 1,
      totals=SidecarTotals(
        seen=self.totals.seen,
        deduped=self.totals.deduped,
        queued=self.totals.queued,
        sent=self.totals.sent,
        failed=self.totals.failed + 1,
      ),
    )

  def with_last_error(self, code: str) -> "SidecarState":
    return SidecarState(
      schema_version=self.schema_version,
      instance_id=self.instance_id,
      last_seen_snapshot_hash=self.last_seen_snapshot_hash,
      last_seen_snapshot_seq=self.last_seen_snapshot_seq,
      last_sent_snapshot_hash=self.last_sent_snapshot_hash,
      last_seen_generated_at=self.last_seen_generated_at,
      last_success_at=self.last_success_at,
      last_error_at=_utc_now_iso(),
      last_error_code=code,
      consecutive_failures=self.consecutive_failures,
      totals=self.totals,
    )

  def to_json(self) -> Dict[str, Any]:
    return {
      "schema_version": self.schema_version,
      "instance_id": self.instance_id,
      "last_seen_snapshot_hash": self.last_seen_snapshot_hash,
      "last_seen_snapshot_seq": self.last_seen_snapshot_seq,
      "last_sent_snapshot_hash": self.last_sent_snapshot_hash,
      "last_seen_generated_at": self.last_seen_generated_at,
      "last_success_at": self.last_success_at,
      "last_error_at": self.last_error_at,
      "last_error_code": self.last_error_code,
      "consecutive_failures": self.consecutive_failures,
      "totals": self.totals.to_dict(),
    }


def _default_state(instance_id: str) -> SidecarState:
  return SidecarState(
    schema_version=STATE_SCHEMA_VERSION,
    instance_id=instance_id,
    last_seen_snapshot_hash=None,
    last_seen_snapshot_seq=None,
    last_sent_snapshot_hash=None,
    last_seen_generated_at=None,
    last_success_at=None,
    last_error_at=None,
    last_error_code=None,
    consecutive_failures=0,
    totals=SidecarTotals(seen=0, deduped=0, queued=0, sent=0, failed=0),
  )


def load_state(path: Path, instance_id: str) -> SidecarState:
  if not path.exists():
    return _default_state(instance_id)

  try:
    raw = json.loads(path.read_text(encoding="utf-8"))
  except (OSError, json.JSONDecodeError):
    return _default_state(instance_id)

  if raw.get("schema_version") != STATE_SCHEMA_VERSION:
    return _default_state(instance_id)

  totals = raw.get("totals") if isinstance(raw.get("totals"), dict) else {}
  return SidecarState(
    schema_version=STATE_SCHEMA_VERSION,
    instance_id=raw.get("instance_id", instance_id),
    last_seen_snapshot_hash=raw.get("last_seen_snapshot_hash"),
    last_seen_snapshot_seq=_coerce_non_negative_int(raw.get("last_seen_snapshot_seq")),
    last_sent_snapshot_hash=raw.get("last_sent_snapshot_hash"),
    last_seen_generated_at=raw.get("last_seen_generated_at"),
    last_success_at=raw.get("last_success_at"),
    last_error_at=raw.get("last_error_at"),
    last_error_code=raw.get("last_error_code"),
    consecutive_failures=int(raw.get("consecutive_failures", 0)),
    totals=SidecarTotals(
      seen=int((totals.get("seen", 0))),
      deduped=int((totals.get("deduped", 0))),
      queued=int((totals.get("queued", 0))),
      sent=int((totals.get("sent", 0))),
      failed=int((totals.get("failed", 0))),
    ),
  )


def _atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
  path.parent.mkdir(parents=True, exist_ok=True)
  tmp = path.with_name(path.name + ".tmp")
  try:
    serialized = json.dumps(payload, indent=2, sort_keys=True).encode("utf-8")
    with open(tmp, "wb") as handle:
      handle.write(serialized)
      handle.flush()
      os.fsync(handle.fileno())

    tmp.chmod(0o600)
    tmp.replace(path)

    dir_fd = os.open(str(path.parent), os.O_RDONLY)
    try:
      os.fsync(dir_fd)
    finally:
      os.close(dir_fd)
  finally:
    if tmp.exists():
      # best effort cleanup
      tmp.unlink(missing_ok=True)


def save_state(path: Path, state: SidecarState) -> None:
  _atomic_write_json(path, state.to_json())
