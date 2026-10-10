import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

os.environ["ENVIRONMENT"] = "test"
os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL", "postgresql+psycopg://miaoban_test:isolated-test-only@127.0.0.1:55433/miaoban_test"
)
if not os.environ["DATABASE_URL"].endswith("/miaoban_test"):
    raise RuntimeError("Tests refuse any database not named miaoban_test")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.api import auth, routes
from app.db import base
from app.db import models as m
from app.domain import common, tasks
from app.main import app


@pytest.fixture(autouse=True)
def clean_database():
    with base.engine.begin() as c:
        names = ",".join('"' + t + '"' for t in base.Base.metadata.tables)
        c.execute(text("TRUNCATE " + names + " CASCADE"))


@pytest.fixture
def clock(monkeypatch):
    class Clock:
        value = datetime(2026, 10, 8, 17, 0, tzinfo=UTC)

        def advance(self, **kwargs):
            self.value += timedelta(**kwargs)

        def now(self):
            return self.value

    clock = Clock()
    for module in (base, auth, routes, common, tasks):
        monkeypatch.setattr(module, "now", clock.now)
    return clock


class Actor:
    def __init__(self, client, user_id, access_token):
        self.client, self.id, self.token = client, user_id, access_token

    def get(self, url, **kwargs):
        return self.client.get("/api/v1" + url, headers={"Authorization": "Bearer " + self.token}, **kwargs)

    def post(self, url, data=None, key=None, **kwargs):
        return self.client.post(
            "/api/v1" + url,
            json=data,
            headers={"Authorization": "Bearer " + self.token, "Idempotency-Key": key or str(uuid4())},
            **kwargs,
        )

    def put(self, url, data, key=None):
        return self.client.put(
            "/api/v1" + url,
            json=data,
            headers={"Authorization": "Bearer " + self.token, "Idempotency-Key": key or str(uuid4())},
        )


@pytest.fixture
def client():
    return TestClient(app)


def activate(client, username):
    from app.domain.common import digest

    secret = "activation-" + str(uuid4())
    with base.SessionLocal.begin() as db:
        db.add(m.Activation(token_hash=digest(secret), expires_at=auth.now() + timedelta(days=2)))
    result = client.post(
        "/api/v1/auth/activate",
        json={
            "token": secret,
            "username": username,
            "password": "Strong-test-password-123",
            "nickname": username,
        },
    )
    assert result.status_code == 200, result.text
    login = client.post(
        "/api/v1/auth/login", json={"username": username, "password": "Strong-test-password-123"}
    )
    assert login.status_code == 200, login.text
    return Actor(client, result.json()["user_id"], login.json()["access_token"])


@pytest.fixture
def pair(client, clock):
    a, b = activate(client, "alice"), activate(client, "bob")
    r = a.post("/spaces", {"name": "我们的自习室", "timezone": "America/Los_Angeles"})
    assert r.status_code == 200, r.text
    sid = r.json()["id"]
    r = a.post(f"/spaces/{sid}/invitations")
    assert r.status_code == 200, r.text
    r = b.post("/invitations/claim", {"token": r.json()["token"]})
    assert r.status_code == 200, r.text
    return a, b, sid


@pytest.fixture
def planned(pair, clock):
    a, b, sid = pair
    day = "2026-10-09"
    rule = a.post(
        f"/spaces/{sid}/rules",
        {"timezone": "America/Los_Angeles", "attendance_points": 5, "effective_date": day},
    )
    assert rule.status_code == 200, rule.text
    assert b.post(f"/spaces/{sid}/rules/{rule.json()['id']}/decision", {"accepted": True}).status_code == 200
    for n, points in enumerate((10, 5, 15)):
        r = a.post(
            f"/spaces/{sid}/tasks",
            {
                "executor_id": b.id,
                "title": f"学习{n}",
                "standard": "完成练习",
                "points": points,
                "tag": "c",
                "starts_on": day,
            },
        )
        assert r.status_code == 200, r.text
        assert (
            b.post(
                f"/spaces/{sid}/task-versions/{r.json()['proposal']['id']}/decision", {"accepted": True}
            ).status_code
            == 200
        )
    clock.advance(days=1)
    # Access expires after 15 minutes; get new short-lived sessions after advancing time.
    for who, username in ((a, "alice"), (b, "bob")):
        login = who.client.post(
            "/api/v1/auth/login", json={"username": username, "password": "Strong-test-password-123"}
        )
        who.token = login.json()["access_token"]
    r = b.get(f"/spaces/{sid}/daily")
    assert r.status_code == 200, r.text
    return a, b, sid, r.json()["instances"]


def complete(b, sid, items):
    for i in items:
        r = b.post(
            f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 0}
        )
        assert r.status_code == 200, r.text
