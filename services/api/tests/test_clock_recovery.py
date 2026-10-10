from datetime import UTC, datetime

from conftest import activate
from test_time_growth_auth import relogin

from app.config import settings
from app.db import base
from app.db import models as m
from app.domain.common import one, rows
from app.jobs import worker
from app.jobs.push import PushFailure


def test_utc_shanghai_future_change_preserves_historical_zone(client, clock):
    a, b = activate(client, "alice"), activate(client, "bob")
    sid = a.post("/spaces", {"name": "日期边界", "timezone": "UTC"}).json()["id"]
    invite = a.post(f"/spaces/{sid}/invitations").json()["token"]
    b.post("/invitations/claim", {"token": invite})
    rule = a.post(
        f"/spaces/{sid}/rules",
        {"timezone": "Asia/Shanghai", "attendance_points": 5, "effective_date": "2026-10-09"},
    ).json()
    b.post(f"/spaces/{sid}/rules/{rule['id']}/decision", {"accepted": True})
    clock.value = datetime(2026, 10, 8, 23, 59, tzinfo=UTC)
    relogin(b, "bob")
    daily = b.get(f"/spaces/{sid}/daily").json()
    assert daily["date"] == "2026-10-08" and daily["plans"][0]["timezone"] == "UTC"
    clock.value = datetime(2026, 10, 9, 0, tzinfo=UTC)
    relogin(b, "bob")
    current = b.get(f"/spaces/{sid}/daily").json()
    assert current["date"] == "2026-10-09" and current["plans"][0]["timezone"] == "Asia/Shanghai"
    assert b.get(f"/spaces/{sid}/daily?day=2026-10-08").json()["plans"][0]["timezone"] == "UTC"
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 0


def test_outbox_retry_persists_between_worker_calls_and_logout_stops_device(pair, clock, monkeypatch):
    a, b, sid = pair
    monkeypatch.setattr(worker, "now", clock.now)
    monkeypatch.setattr(settings(), "push_provider", "configured")
    with base.SessionLocal.begin() as db:
        session = one(db, m.AuthSession, user_id=a.id)
        db.add(
            m.Device(
                user_id=a.id, session_id=session.id, token="test-retry-token", platform="ios", provider="apns"
            )
        )
        for item in rows(db, m.Outbox):
            item.next_attempt = clock.now()

    class Temporary:
        def send(self, *args):
            raise PushFailure("temporary_unavailable")

    assert worker.tick(lambda _: Temporary())
    with base.SessionLocal() as db:
        item = rows(db, m.Outbox)[0]
        assert item.status == "retry" and item.attempts == 1
        identifier, due = item.id, item.next_attempt
    assert a.post("/auth/logout").status_code == 200
    clock.value = due

    class MustNotSend:
        def send(self, *args):
            raise AssertionError("Old logged-out session received a push")

    assert worker.tick(lambda _: MustNotSend())
    with base.SessionLocal() as db:
        assert db.get(m.Outbox, identifier).status == "no_device"
        assert not rows(db, m.Device)[0].active
        assert all(not n.read for n in rows(db, m.Notification))


def test_partial_push_retry_does_not_resend_accepted_device(pair, clock, monkeypatch):
    a, b, sid = pair
    monkeypatch.setattr(worker, "now", clock.now)
    monkeypatch.setattr(settings(), "push_provider", "configured")
    with base.SessionLocal.begin() as db:
        session = one(db, m.AuthSession, user_id=a.id)
        for token in ("test-success-device", "test-retry-device"):
            db.add(
                m.Device(user_id=a.id, session_id=session.id, token=token, platform="ios", provider="apns")
            )
        for item in rows(db, m.Outbox):
            item.next_attempt = clock.now()
    attempts = []

    class Partial:
        def send(self, device, *args):
            attempts.append(device.token)
            if device.token == "test-retry-device":
                raise PushFailure("temporary")

    worker.tick(lambda _: Partial())
    with base.SessionLocal() as db:
        item = rows(db, m.Outbox)[0]
        assert item.status == "retry" and len(rows(db, m.PushReceipt)) == 1
        clock.value = item.next_attempt

    class Success:
        def send(self, device, *args):
            attempts.append(device.token)

    worker.tick(lambda _: Success())
    assert attempts.count("test-success-device") == 1 and attempts.count("test-retry-device") == 2
    with base.SessionLocal() as db:
        assert rows(db, m.Outbox)[0].status == "provider_accepted"
        assert len(rows(db, m.PushReceipt)) == 2
