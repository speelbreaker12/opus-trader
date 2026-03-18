from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import json
import sqlite3
from typing import Any, Dict, Optional
from pathlib import Path


@dataclass(frozen=True)
class OutboxRow:
  id: int
  snapshot_hash: str
  instance_id: str
  generated_at: str
  payload_json: str
  status: str
  attempt_count: int
  next_attempt_at: str
  last_error_code: Optional[str]
  last_error_detail: Optional[str]
  created_at: str
  sent_at: Optional[str]

  @property
  def payload(self) -> Dict[str, Any]:
    try:
      return json.loads(self.payload_json)
    except json.JSONDecodeError:
      return {}


class SpoolStore:
  def __init__(self, path: Path):
    self.path = path
    self.path.parent.mkdir(parents=True, exist_ok=True)
    self._conn = sqlite3.connect(str(path), timeout=30.0)
    self._conn.execute("PRAGMA journal_mode=WAL")
    self._conn.row_factory = sqlite3.Row
    self._ensure_schema()

  def close(self) -> None:
    self._conn.close()

  def _ensure_schema(self) -> None:
    self._conn.executescript(
      """
      CREATE TABLE IF NOT EXISTS outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        snapshot_hash TEXT NOT NULL,
        instance_id TEXT NOT NULL,
        generated_at TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT NOT NULL,
        last_error_code TEXT,
        last_error_detail TEXT,
        created_at TEXT NOT NULL,
        sent_at TEXT
      );
      CREATE UNIQUE INDEX IF NOT EXISTS ux_outbox_snapshot_hash
        ON outbox(snapshot_hash);
      CREATE INDEX IF NOT EXISTS ix_outbox_status_next_attempt
        ON outbox(status, next_attempt_at);
      """
    )
    self._conn.commit()

  def enqueue(self, snapshot_hash: str, instance_id: str, generated_at: str, payload_json: str, next_attempt_at: str) -> bool:
    now = datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    cursor = self._conn.execute(
      """
      INSERT OR IGNORE INTO outbox
      (snapshot_hash, instance_id, generated_at, payload_json, status, attempt_count, next_attempt_at, created_at)
      VALUES (?, ?, ?, ?, 'PENDING', 0, ?, ?)
      """,
      (snapshot_hash, instance_id, generated_at, payload_json, next_attempt_at, now),
    )
    self._conn.commit()
    return cursor.rowcount is not None and cursor.rowcount > 0

  def ready_rows(self, limit: int = 10) -> list[OutboxRow]:
    now = datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    cur = self._conn.execute(
      """
      SELECT * FROM outbox
      WHERE status IN ('PENDING', 'FAILED_RETRY')
        AND next_attempt_at <= ?
      ORDER BY id ASC
      LIMIT ?
      """,
      (now, limit),
    )
    return [self._row_to_obj(row) for row in cur.fetchall()]

  def mark_pending(self, row_id: int, *, payload_json: str, status: str, attempt_count: int, next_attempt_at: str,
                  error_code: Optional[str], error_detail: Optional[str], sent_at: Optional[str] = None) -> None:
    self._conn.execute(
      """
      UPDATE outbox
      SET payload_json = ?, status = ?, attempt_count = ?, next_attempt_at = ?,
          last_error_code = ?, last_error_detail = ?, sent_at = COALESCE(?, sent_at)
      WHERE id = ?
      """,
      (payload_json, status, attempt_count, next_attempt_at, error_code, error_detail, sent_at, row_id),
    )
    self._conn.commit()

  def mark_success(self, row_id: int, sent_at: str) -> None:
    self._conn.execute(
      """
      UPDATE outbox
      SET status = 'SENT', sent_at = ?, last_error_code = NULL, last_error_detail = NULL
      WHERE id = ?
      """,
      (sent_at, row_id),
    )
    self._conn.commit()

  def mark_retry(self, row_id: int, attempt_count: int, next_attempt_at: str, error_code: str, detail: str) -> None:
    self._conn.execute(
      """
      UPDATE outbox
      SET status = 'FAILED_RETRY',
          attempt_count = ?,
          next_attempt_at = ?,
          last_error_code = ?,
          last_error_detail = ?
      WHERE id = ?
      """,
      (attempt_count, next_attempt_at, error_code, detail, row_id),
    )
    self._conn.commit()

  def mark_perm_failure(self, row_id: int, attempt_count: int, error_code: str, detail: str) -> None:
    self._conn.execute(
      """
      UPDATE outbox
      SET status = 'FAILED_PERM',
          attempt_count = ?,
          next_attempt_at = next_attempt_at,
          last_error_code = ?,
          last_error_detail = ?
      WHERE id = ?
      """,
      (attempt_count, error_code, detail, row_id),
    )
    self._conn.commit()

  def apply_retention(self, *, sent_keep_days: int = 7, failed_perm_keep_days: int = 30, keep_last_sent: int = 10000) -> None:
    now = datetime.now(tz=timezone.utc)
    sent_cutoff = (now - timedelta(days=sent_keep_days)).isoformat(timespec="seconds").replace("+00:00", "Z")
    fail_cutoff = (now - timedelta(days=failed_perm_keep_days)).isoformat(timespec="seconds").replace("+00:00", "Z")

    keep_ids: list[int] = []
    recent_sent = self._conn.execute(
      "SELECT id FROM outbox WHERE status='SENT' ORDER BY id DESC LIMIT ?",
      (keep_last_sent,),
    ).fetchall()
    keep_ids.extend([row["id"] for row in recent_sent])

    sent_recent = self._conn.execute(
      "SELECT id FROM outbox WHERE status='SENT' AND created_at >= ?",
      (sent_cutoff,),
    ).fetchall()
    keep_ids.extend([row["id"] for row in sent_recent])

    if keep_ids:
      placeholder = ",".join(["?"] * len(keep_ids))
      keep_ids_param = tuple(keep_ids)
      self._conn.execute(
        f"DELETE FROM outbox WHERE status='SENT' AND id NOT IN ({placeholder})",
        keep_ids_param,
      )

    self._conn.execute(
      "DELETE FROM outbox WHERE status='FAILED_PERM' AND created_at < ?",
      (fail_cutoff,),
    )

    self._conn.commit()

  def _row_to_obj(self, row: sqlite3.Row) -> OutboxRow:
    return OutboxRow(
      id=row["id"],
      snapshot_hash=row["snapshot_hash"],
      instance_id=row["instance_id"],
      generated_at=row["generated_at"],
      payload_json=row["payload_json"],
      status=row["status"],
      attempt_count=row["attempt_count"],
      next_attempt_at=row["next_attempt_at"],
      last_error_code=row["last_error_code"],
      last_error_detail=row["last_error_detail"],
      created_at=row["created_at"],
      sent_at=row["sent_at"],
    )
