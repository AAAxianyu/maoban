from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime

from conftest import activate, complete
from sqlalchemy import select

from app.db import base
from app.db import models as m


def relogin(who, username):
    r = who.client.post(
        "/api/v1/auth/login", json={"username": username, "password": "Strong-test-password-123"}
    )
    who.token = r.json()["access_token"]


def test_stage_points_and_gift_restore(planned):
    a, b, sid, items = planned
    goals = []
    for gift in (False, True):
        r = a.post(
            f"/spaces/{sid}/milestones",
            {
                "executor_id": b.id,
                "title": "三次练习",
                "standard": "完成三次 C 练习",
                "metric": "tasks",
                "tag": "c",
                "target": 3,
                "starts_on": "2026-10-09",
                "ends_on": "2026-10-20",
                "reward_points": None if gift else 25,
                "gift_title": "一起看电影" if gift else None,
            },
        )
        assert r.status_code == 200, r.text
        gid = r.json()["id"]
        goals.append(gid)
        assert b.post(f"/spaces/{sid}/milestones/{gid}/decision", {"accepted": True}).status_code == 200
    complete(b, sid, items)
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 60
    orders = b.get(f"/spaces/{sid}/orders").json()
    assert len(orders) == 1 and orders[0]["price"] == 0 and orders[0]["milestone_id"] == goals[1]
    i = items[0]
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": False, "expected_version": 1})
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 35 - i["points"] - 5
    assert b.get(f"/spaces/{sid}/orders").json()[0]["status"] == "cancelled"
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 2})
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 60
    o = b.get(f"/spaces/{sid}/orders").json()[0]
    assert o["id"] == orders[0]["id"] and o["status"] == "pending"
    a.post(f"/spaces/{sid}/orders/{o['id']}/command", {"action": "fulfill", "expected_version": o["version"]})
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": False, "expected_version": 3})
    corrected = b.get(f"/spaces/{sid}/orders").json()[0]
    assert corrected["status"] == "fulfilled" and corrected["corrected"]
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 4})
    assert len(b.get(f"/spaces/{sid}/orders").json()) == 1
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 60


def test_midday_task_is_optional_and_rest_is_future(pair, clock):
    a, b, sid = pair
    r = a.post(
        f"/spaces/{sid}/tasks",
        {
            "executor_id": b.id,
            "title": "新练习",
            "standard": "一次练习",
            "points": 10,
            "starts_on": "2026-10-08",
        },
    )
    assert b.get(f"/spaces/{sid}/daily").json()["instances"] == []
    proposal = r.json()["proposal"]["id"]
    assert a.post(f"/spaces/{sid}/task-versions/{proposal}/decision", {"accepted": True}).status_code == 403
    assert b.post(f"/spaces/{sid}/task-versions/{proposal}/decision", {"accepted": True}).status_code == 200
    i = b.get(f"/spaces/{sid}/daily").json()["instances"][0]
    assert not i["required"]
    complete(b, sid, [i])
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 10
    assert b.post(f"/spaces/{sid}/rest-dates", {"date": "2026-10-08", "rest": True}).status_code == 400
    assert b.post(f"/spaces/{sid}/rest-dates", {"date": "2026-10-09", "rest": True}).status_code == 200
    clock.advance(days=1)
    relogin(b, "bob")
    daily = b.get(f"/spaces/{sid}/daily").json()
    assert not daily["instances"] and next(p for p in daily["plans"] if p["user_id"] == b.id)["rest"]


def test_version_rejection_and_midday_freeze(planned):
    a, b, sid, items = planned
    with base.SessionLocal() as db:
        task_id = db.get(m.Instance, items[0]["id"]).task_id
    data = {
        "executor_id": b.id,
        "title": "改成新标题",
        "standard": "新标准",
        "points": 99,
        "starts_on": "2026-10-09",
    }
    proposal = a.post(f"/spaces/{sid}/tasks/{task_id}/versions", data).json()["proposal"]
    assert (
        b.post(
            f"/spaces/{sid}/task-versions/{proposal['id']}/decision",
            {"accepted": False, "reason": "今天保持原约定"},
        ).status_code
        == 200
    )
    assert b.get(f"/spaces/{sid}/daily").json()["instances"][0]["points"] in (5, 10, 15)
    proposal = a.post(f"/spaces/{sid}/tasks/{task_id}/versions", data).json()["proposal"]
    assert (
        b.post(f"/spaces/{sid}/task-versions/{proposal['id']}/decision", {"accepted": True}).status_code
        == 200
    )
    instance = next(i for i in b.get(f"/spaces/{sid}/daily").json()["instances"] if i["task_id"] == task_id)
    assert instance["title"] != "改成新标题" and instance["points"] == items[0]["points"]


def test_makeup_window_and_partner_review(planned, clock):
    a, b, sid, items = planned
    clock.advance(days=1)
    relogin(a, "alice")
    relogin(b, "bob")
    i = items[0]
    assert (
        b.post(
            f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 0}
        ).json()["code"]
        == "DATE_REQUIRES_REVIEW"
    )
    r = b.post(
        f"/spaces/{sid}/instances/{i['id']}/corrections",
        {"desired_state": True, "expected_version": 0, "reason": "昨日离线完成"},
    )
    assert r.status_code == 200, r.text
    cid = r.json()["id"]
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 0
    assert b.post(f"/spaces/{sid}/corrections/{cid}/decision", {"accepted": True}).status_code == 403
    assert a.post(f"/spaces/{sid}/corrections/{cid}/decision", {"accepted": True}).status_code == 200
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == i["points"]
    clock.advance(hours=2)
    relogin(b, "bob")
    r = b.post(
        f"/spaces/{sid}/instances/{items[1]['id']}/corrections",
        {"desired_state": True, "expected_version": 0, "reason": "超过中午"},
    )
    assert r.json()["code"] == "MAKEUP_WINDOW_CLOSED"


def test_dst_repeated_hour_one_instance(pair, clock):
    a, b, sid = pair
    clock.value = datetime(2026, 10, 31, 17, tzinfo=UTC)
    relogin(a, "alice")
    relogin(b, "bob")
    r = a.post(
        f"/spaces/{sid}/tasks",
        {
            "executor_id": b.id,
            "title": "夏令时练习",
            "standard": "一次",
            "points": 10,
            "starts_on": "2026-11-01",
        },
    )
    assert (
        b.post(
            f"/spaces/{sid}/task-versions/{r.json()['proposal']['id']}/decision", {"accepted": True}
        ).status_code
        == 200
    )
    clock.value = datetime(2026, 11, 1, 8, 30, tzinfo=UTC)
    relogin(b, "bob")
    i = b.get(f"/spaces/{sid}/daily").json()["instances"][0]
    complete(b, sid, [i])
    clock.value = datetime(2026, 11, 1, 9, 30, tzinfo=UTC)
    relogin(b, "bob")
    again = b.get(f"/spaces/{sid}/daily").json()["instances"]
    assert len(again) == 1 and again[0]["id"] == i["id"] and again[0]["completed"]
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 10


def test_invite_atomic_capacity_and_invite_activation(client, clock):
    a = activate(client, "alice")
    b = activate(client, "bob")
    c = activate(client, "carol")
    sid = a.post("/spaces", {"name": "两人屋", "timezone": "Asia/Shanghai"}).json()["id"]
    invitation = a.post(f"/spaces/{sid}/invitations").json()
    invitation2 = a.post(f"/spaces/{sid}/invitations").json()
    with ThreadPoolExecutor(max_workers=2) as ex:
        rs = list(
            ex.map(
                lambda args: args[0].post("/invitations/claim", {"token": args[1]}),
                [(b, invitation["token"]), (c, invitation2["token"])],
            )
        )
    assert sorted(r.status_code for r in rs) == [200, 409]
    with base.SessionLocal() as db:
        assert len(list(db.scalars(select(m.Member).where(m.Member.space_id == sid)))) == 2
        assert not any("token" in x.result for x in db.scalars(select(m.Idempotency)))
    sid2 = a.post("/spaces", {"name": "新小屋", "timezone": "UTC"}).json()["id"]
    secret = a.post(f"/spaces/{sid2}/invitations").json()["token"]
    r = client.post(
        "/api/v1/auth/activate",
        json={
            "token": secret,
            "username": "dana",
            "password": "Strong-test-password-123",
            "nickname": "第四位",
        },
    )
    assert r.status_code == 200, r.text
    with base.SessionLocal() as db:
        assert db.get(m.Member, (sid2, r.json()["user_id"]))
    assert (
        client.post(
            "/api/v1/auth/activate",
            json={
                "token": secret,
                "username": "extra",
                "password": "Strong-test-password-123",
                "nickname": "第三人",
            },
        ).status_code
        == 409
    )


def test_refresh_replay_revokes_and_logout(client, clock):
    who = activate(client, "alice")
    login = client.post(
        "/api/v1/auth/login", json={"username": "alice", "password": "Strong-test-password-123"}
    ).json()
    first = client.post("/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]})
    assert first.status_code == 200
    assert (
        client.post("/api/v1/auth/refresh", json={"refresh_token": login["refresh_token"]}).status_code == 401
    )
    assert (
        client.get(
            "/api/v1/auth/me", headers={"Authorization": "Bearer " + first.json()["access_token"]}
        ).status_code
        == 401
    )
    assert who.post("/auth/logout").status_code == 200
    assert who.get("/auth/me").status_code == 401


def test_immutable_ledger(planned):
    _, b, sid, items = planned
    complete(b, sid, items)
    import pytest
    from sqlalchemy import text
    from sqlalchemy.exc import DBAPIError

    with pytest.raises(DBAPIError):
        with base.engine.begin() as connection:
            connection.execute(text("UPDATE ledger_entries SET delta=999"))
