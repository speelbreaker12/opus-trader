from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest

from dashboard.publisher import spool, state
from dashboard.publisher.transform import SnapshotBuilderError, build_snapshot_envelope, hash_snapshot
from dashboard.publisher import publisher
from dashboard.publisher.state import load_state, save_state

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize(
  "fixture_name, should_raise",
  [
    ("runtime_state_v1_valid.json", False),
    ("runtime_state_v1_missing_key.json", True),
  ],
)
def test_runtime_state_contract_validation(fixture_name: str, should_raise: bool) -> None:
  payload = json.loads((ROOT / "tests" / "fixtures" / "runtime_state" / fixture_name).read_text(encoding="utf-8"))

  if should_raise:
    with pytest.raises(SnapshotBuilderError):
      build_snapshot_envelope(
        payload,
        instance_id="soldier-main-01",
        service="soldier_core",
        env="paper",
        head_commit="4a2e6fc",
        expected_publish_interval_s=2,
        stale_after_s=15,
        generated_at=payload.get("generated_at", "2026-02-23T21:10:03Z"),
        publisher_version="status-publisher.v1",
        attempt=1,
      )
    return

  snapshot = build_snapshot_envelope(
    payload,
    instance_id="soldier-main-01",
    service="soldier_core",
    env="paper",
    head_commit="4a2e6fc",
    expected_publish_interval_s=2,
    stale_after_s=15,
    generated_at="2026-02-23T21:10:03Z",
    publisher_version="status-publisher.v1",
    attempt=1,
  )

  assert snapshot["schema_version"] == "dashboard_status_snapshot.v1"
  assert snapshot["source"]["instance_id"] == "soldier-main-01"
  assert snapshot["times"]["generated_at"] == payload["generated_at"]
  assert snapshot["safety"]["trading_mode"] == payload["safety"]["trading_mode"]
  assert snapshot["safety"]["owner_view"]["unblock_steps"] == payload["safety"]["owner_view"]["unblock_steps"]
  assert snapshot["publisher"]["attempt"] == 1
  assert snapshot["snapshot_hash"] == hash_snapshot(payload)


def test_runtime_state_payload_transforms_owner_view_schema_errors() -> None:
  payload = json.loads((ROOT / "tests" / "fixtures" / "runtime_state" / "runtime_state_v1_valid.json").read_text(encoding="utf-8"))
  payload["safety"]["owner_view"] = {"unblock_steps": [1, 2, 3]}

  with pytest.raises(SnapshotBuilderError):
    build_snapshot_envelope(
      payload,
      instance_id="soldier-main-01",
      service="soldier_core",
      env="paper",
      head_commit="4a2e6fc",
      expected_publish_interval_s=2,
      stale_after_s=15,
      generated_at="2026-02-23T21:10:03Z",
      publisher_version="status-publisher.v1",
      attempt=1,
    )


def test_sidecar_state_counters(tmp_path: Path) -> None:
  temp_state = tmp_path / "status_publisher_state_test.json"
  baseline = load_state(temp_state, "soldier-main-01")
  seen = baseline.with_seen("h1", "2026-02-23T21:10:03Z", 1)
  deduped = seen.with_dedup().with_last_error("SNAPSHOT_DUPLICATE_SKIPPED")
  queued = deduped.with_queued()
  sent = queued.with_send_success("h2", "2026-02-23T21:10:04Z")
  failed = sent.with_send_failure("CONVEX_RATE_LIMITED", permanent=False)

  assert baseline.totals == state.SidecarTotals(seen=0, deduped=0, queued=0, sent=0, failed=0)
  assert seen.totals.seen == 1
  assert deduped.totals.deduped == 1
  assert queued.totals.queued == 1
  assert sent.last_sent_snapshot_hash == "h2"
  assert sent.totals.sent == 1
  assert sent.totals.failed == 0
  assert failed.totals.failed == 1
  assert failed.consecutive_failures == sent.consecutive_failures + 1

  save_state(temp_state, failed)
  restored = load_state(temp_state, "soldier-main-01")
  assert restored.totals == failed.totals
  assert restored.last_seen_snapshot_seq == 1


def test_extract_snapshot_seq_invalid() -> None:
  with pytest.raises(publisher.PublisherError) as exc:
    publisher._extract_snapshot_seq({"snapshot_seq": -1})
  assert exc.value.code == publisher.RUNTIME_SCHEMA_INVALID

  with pytest.raises(publisher.PublisherError):
    publisher._extract_snapshot_seq({})

  assert publisher._extract_snapshot_seq({"snapshot_seq": 7}) == 7


def test_process_once_enforces_snapshot_seq_monotonicity(tmp_path: Path) -> None:
  source = json.loads((ROOT / "tests" / "fixtures" / "runtime_state" / "runtime_state_v1_valid.json").read_text(encoding="utf-8"))
  source["snapshot_seq"] = 10
  source_path = tmp_path / "runtime_state.json"
  source_path.write_text(json.dumps(source, indent=2), encoding="utf-8")

  cfg = publisher.PublisherConfig(
    source_snapshot_path=source_path,
    state_path=tmp_path / "state.json",
    spool_db_path=tmp_path / "spool.db",
    log_path=tmp_path / "publisher.log",
    convex_endpoint="http://localhost:1",
    convex_secret=None,
    instance_id="soldier-main-01",
    service="soldier_core",
    env="paper",
    head_commit="4a2e6fc",
    expected_publish_interval_s=2,
    stale_after_s=15,
    poll_interval_s=2,
    publisher_version="status-publisher.v1",
    max_attempts=6,
    connect_timeout_s=2.0,
    read_timeout_s=5.0,
    request_total_timeout_s=8.0,
  )

  state_obj = publisher.load_state(cfg.state_path, cfg.instance_id)
  state_obj = state_obj.with_seen("baseline", "2026-02-23T21:10:03Z", 20)
  outbox = spool.SpoolStore(cfg.spool_db_path)
  try:
    with pytest.raises(publisher.PublisherError) as exc:
      publisher._process_once(cfg, outbox, state_obj)
    assert exc.value.code == publisher.RUNTIME_SCHEMA_INVALID
  finally:
    outbox.close()


def test_spool_retention_removes_expired_sent_and_failed_perm_rows(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
  spool_path = tmp_path / "status_publisher_spool_test.db"

  store = spool.SpoolStore(spool_path)

  now = datetime(2026, 2, 23, 22, 0, 0, tzinfo=timezone.utc)

  class FrozenDateTime(datetime):
    @classmethod
    def now(cls, tz=None):
      return now if tz is None else now.astimezone(tz)

  monkeypatch.setattr(spool, "datetime", FrozenDateTime)

  def iso(value: datetime) -> str:
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")

  def insert_row(*, status: str, created_days_ago: int, seen_days_ago: int, attempt_count: int = 0, snapshot_hash: str = "h", generated_at: str = "2026-02-23T21:10:03Z") -> None:
    created_at = iso(now - timedelta(days=created_days_ago))
    next_attempt_at = iso(now - timedelta(days=seen_days_ago))
    store._conn.execute(
      "INSERT INTO outbox (snapshot_hash, instance_id, generated_at, payload_json, status, attempt_count, next_attempt_at, created_at, sent_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      (
        snapshot_hash,
        "soldier-main-01",
        generated_at,
        "{}",
        status,
        attempt_count,
        next_attempt_at,
        created_at,
        None,
      ),
    )
    store._conn.execute("COMMIT")

  insert_row(status="SENT", created_days_ago=30, seen_days_ago=30, snapshot_hash="old-sent")
  insert_row(status="SENT", created_days_ago=1, seen_days_ago=1, snapshot_hash="recent-sent")
  insert_row(status="FAILED_PERM", created_days_ago=40, seen_days_ago=40, snapshot_hash="old-fail")
  insert_row(status="FAILED_PERM", created_days_ago=1, seen_days_ago=1, snapshot_hash="recent-fail")

  store.apply_retention(keep_last_sent=1, failed_perm_keep_days=30)
  rows = store._conn.execute("SELECT snapshot_hash, status FROM outbox ORDER BY snapshot_hash").fetchall()
  status_by_hash = {row[0]: row[1] for row in rows}

  assert status_by_hash == {
    "recent-sent": "SENT",
    "recent-fail": "FAILED_PERM",
  }

  store.close()
