from datetime import UTC, datetime

from conftest import complete
from sqlalchemy import select
from test_time_growth_auth import relogin

from app.config import settings
from app.db import base
from app.db import models as m
from app.domain.common import rows
from app.jobs import worker


def test_all_five_badges_and_four_permanent_decorations(planned, clock):
    a, b, sid, _ = planned
    for n in range(7):
        proposal = a.post(
            f"/spaces/{sid}/tasks",
            {
                "executor_id": a.id,
                "title": f"我的 C 练习 {n}",
                "standard": "一次有效练习",
                "points": 0,
                "tag": "c",
                "starts_on": "2026-10-10",
            },
        )
        assert proposal.status_code == 200, proposal.text
    for _ in range(10):
        clock.advance(days=1)
        relogin(a, "alice")
        relogin(b, "bob")
        instances = a.get(f"/spaces/{sid}/daily").json()["instances"]
        complete(a, sid, [i for i in instances if i["user_id"] == a.id])
        complete(b, sid, [i for i in instances if i["user_id"] == b.id])
    growth = b.get(f"/spaces/{sid}/growth").json()
    assert growth["permanent_xp"] == 100 and growth["level"] == 5
    assert {d["decoration"] for d in growth["decorations"]} == {"lamp", "cat_bed", "plant", "bookshelf"}
    assert {a["code"] for a in growth["achievements"] if a["user_id"] == b.id} == {
        "first",
        "seven_days",
        "c_ten",
        "together",
        "thirty",
    }
    last = next(i for i in instances if i["user_id"] == b.id)
    b.post(f"/spaces/{sid}/instances/{last['id']}/checkin", {"desired_state": False, "expected_version": 1})
    changed = b.get(f"/spaces/{sid}/growth").json()
    assert changed["permanent_xp"] == 100 and changed["stats"][b.id]["effective_completions"] == 29
    assert len(changed["decorations"]) == 4


def test_worker_missing_configuration_and_quiet_hours(planned, clock, monkeypatch):
    a, b, sid, items = planned
    monkeypatch.setattr(worker, "now", clock.now)
    complete(b, sid, [items[0]])
    # All inbox rows persist even if remote push cannot be configured in this environment.
    with base.SessionLocal.begin() as db:
        for item in rows(db, m.Outbox):
            item.next_attempt = clock.now()
    assert worker.tick()
    with base.SessionLocal() as db:
        statuses = {i.status for i in rows(db, m.Outbox)}
        assert "configuration_missing" in statuses
        assert all(not n.read for n in rows(db, m.Notification))
    prefs = {"quiet_start": "22:00", "quiet_end": "08:00"}
    assert worker.quiet_until(datetime(2026, 10, 9, 23, tzinfo=UTC), prefs) == datetime(
        2026, 10, 10, 8, tzinfo=UTC
    )
    assert worker.quiet_until(datetime(2026, 10, 9, 7, tzinfo=UTC), prefs) == datetime(
        2026, 10, 9, 8, tzinfo=UTC
    )
    assert worker.quiet_until(datetime(2026, 10, 9, 12, tzinfo=UTC), prefs) is None


def test_invalid_push_device_is_disabled_and_no_read_claim(pair, clock, monkeypatch):
    a, b, sid = pair
    monkeypatch.setattr(worker, "now", clock.now)
    monkeypatch.setattr(settings(), "push_provider", "configured")
    with base.SessionLocal.begin() as db:
        from app.domain.common import one

        session = one(db, m.AuthSession, user_id=a.id)
        db.add(
            m.Device(
                user_id=a.id,
                session_id=session.id,
                token="test-invalid-device-token",
                platform="ios",
                provider="apns",
            )
        )
        for item in rows(db, m.Outbox):
            item.next_attempt = clock.now()

    class Invalid:
        def send(self, *args):
            from app.jobs.push import PushFailure

            raise PushFailure("Unregistered", invalid=True)

    assert worker.tick(lambda _: Invalid())
    with base.SessionLocal() as db:
        assert not rows(db, m.Device)[0].active
        assert all(not n.read for n in rows(db, m.Notification))


def test_missing_credentials_does_not_exhaust_retry_budget(pair, clock, monkeypatch):
    a, _, _ = pair
    monkeypatch.setattr(worker, "now", clock.now)
    monkeypatch.setattr(settings(), "push_provider", "configured")
    with base.SessionLocal.begin() as db:
        session = db.scalar(select(m.AuthSession).where(m.AuthSession.user_id == a.id))
        db.add(
            m.Device(
                user_id=a.id,
                session_id=session.id,
                token="fixture-config-device",
                platform="ios",
                provider="apns",
            )
        )
        for item in rows(db, m.Outbox):
            item.next_attempt = clock.now()

    class Missing:
        def send(self, *args):
            from app.jobs.push import PushFailure

            raise PushFailure("configuration_missing")

    for _ in range(12):
        clock.advance(minutes=11)
        assert worker.tick(lambda _: Missing())
    with base.SessionLocal() as db:
        item = rows(db, m.Outbox)[0]
        assert item.status == "configuration_missing" and item.attempts == 0
        assert not rows(db, m.Notification)[0].read

    class Configured:
        def send(self, *args):
            pass

    clock.advance(minutes=11)
    assert worker.tick(lambda _: Configured())
    with base.SessionLocal() as db:
        assert rows(db, m.Outbox)[0].status == "provider_accepted"
        assert len(rows(db, m.PushReceipt)) == 1
        assert not rows(db, m.Notification)[0].read
