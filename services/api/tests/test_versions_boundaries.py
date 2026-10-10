from concurrent.futures import ThreadPoolExecutor

import pytest
from conftest import activate, complete
from sqlalchemy import select
from starlette.websockets import WebSocketDisconnect
from test_time_growth_auth import relogin

from app.db import base
from app.db import models as m


def goal_data(b, points=25):
    return {
        "executor_id": b.id,
        "title": "三个练习",
        "standard": "三个有效完成",
        "metric": "tasks",
        "tag": "c",
        "target": 3,
        "starts_on": "2026-10-09",
        "ends_on": "2026-10-30",
        "reward_points": points,
        "gift_title": None,
    }


def test_milestone_versions_keep_old_terms_until_approval_and_diff_award(planned):
    a, b, sid, items = planned
    data = goal_data(b)
    gid = a.post(f"/spaces/{sid}/milestones", data).json()["id"]
    assert b.post(f"/spaces/{sid}/milestones/{gid}/decision", {"accepted": True}).status_code == 200
    complete(b, sid, items)
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 60
    proposal = a.post(f"/spaces/{sid}/milestones/{gid}/versions", {**data, "reward_points": 40}).json()
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 60
    assert (
        a.post(f"/spaces/{sid}/milestone-versions/{proposal['id']}/decision", {"accepted": True}).status_code
        == 403
    )
    assert (
        b.post(f"/spaces/{sid}/milestone-versions/{proposal['id']}/decision", {"accepted": True}).status_code
        == 200
    )
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 75
    rejected = a.post(f"/spaces/{sid}/milestones/{gid}/versions", {**data, "reward_points": 99}).json()
    assert (
        b.post(
            f"/spaces/{sid}/milestone-versions/{rejected['id']}/decision",
            {"accepted": False, "reason": "保留已接受约定"},
        ).status_code
        == 200
    )
    versions = b.get(f"/spaces/{sid}/milestones/{gid}/versions").json()
    assert [v["data"]["reward_points"] for v in versions] == [25, 40, 99]
    assert [v["status"] for v in versions] == ["accepted", "accepted", "rejected"]
    assert versions[0]["accepted_at"] is not None
    with base.SessionLocal() as db:
        entries = list(db.scalars(select(m.Ledger).where(m.Ledger.source == "milestone:" + gid)))
        assert sorted(x.delta for x in entries) == [15, 25]


def test_delivered_then_refunded_gift_never_becomes_a_second_delivery(planned):
    a, b, sid, items = planned
    data = {**goal_data(b), "reward_points": None, "gift_title": "一起喝茶"}
    gid = a.post(f"/spaces/{sid}/milestones", data).json()["id"]
    b.post(f"/spaces/{sid}/milestones/{gid}/decision", {"accepted": True})
    complete(b, sid, items)
    order = b.get(f"/spaces/{sid}/orders").json()[0]
    path = f"/spaces/{sid}/orders/{order['id']}/command"
    order = a.post(path, {"action": "fulfill", "expected_version": order["version"]}).json()["order"]
    order = b.post(
        path, {"action": "request_cancel", "reason": "双方改约", "expected_version": order["version"]}
    ).json()["order"]
    order = a.post(path, {"action": "approve_cancel", "expected_version": order["version"]}).json()["order"]
    assert order["status"] == "cancelled" and order["ever_fulfilled"]
    i = items[0]
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": False, "expected_version": 1})
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 2})
    orders = b.get(f"/spaces/{sid}/orders").json()
    assert len(orders) == 1 and orders[0]["id"] == order["id"] and orders[0]["status"] == "cancelled"
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 35


def test_cancel_and_fulfill_race_has_one_transition(planned):
    a, b, sid, items = planned
    complete(b, sid, items)
    rid = a.post(
        f"/spaces/{sid}/rewards",
        {
            "recipient_id": b.id,
            "title": "咖啡",
            "description": "一杯",
            "price": 20,
            "stock": 1,
            "published": True,
        },
    ).json()["id"]
    order = b.post(f"/spaces/{sid}/rewards/{rid}/redeem", {"confirmed_price": 20}).json()["order"]
    with ThreadPoolExecutor(max_workers=2) as ex:
        results = list(
            ex.map(
                lambda args: args[0].post(
                    f"/spaces/{sid}/orders/{order['id']}/command", {"action": args[1], "expected_version": 1}
                ),
                [(a, "fulfill"), (b, "cancel")],
            )
        )
    assert sorted(r.status_code for r in results) == [200, 409]
    current = b.get(f"/spaces/{sid}/orders").json()[0]
    balance = b.get(f"/spaces/{sid}/wallet").json()["balance"]
    assert (current["status"], balance) in [("cancelled", 35), ("fulfilled", 15)]


def test_login_limit_is_durable_and_expires(client, clock):
    activate(client, "alice")
    data = {"username": "alice", "password": "Wrong-password-123"}
    for _ in range(10):
        assert client.post("/api/v1/auth/login", json=data).status_code == 401
    assert client.post("/api/v1/auth/login", json=data).status_code == 429
    clock.advance(minutes=16)
    assert client.post("/api/v1/auth/login", json=data).status_code == 401


def test_revoked_and_expired_invites_and_unauthorized_socket(pair, client, clock):
    a, b, sid = pair
    outsider = activate(client, "carol")
    empty = a.post("/spaces", {"name": "邀请检查", "timezone": "UTC"}).json()["id"]
    invite = a.post(f"/spaces/{empty}/invitations").json()
    a.post(f"/spaces/{empty}/invitations/{invite['id']}/revoke")
    assert outsider.post("/invitations/claim", {"token": invite["token"]}).status_code == 409
    with pytest.raises(WebSocketDisconnect) as error:
        with client.websocket_connect(
            f"/api/v1/spaces/{sid}/ws", headers={"Authorization": "Bearer " + outsider.token}
        ):
            pass
    assert error.value.code == 4403
    invite = a.post(f"/spaces/{empty}/invitations").json()
    clock.advance(days=3)
    relogin(outsider, "carol")
    assert outsider.post("/invitations/claim", {"token": invite["token"]}).status_code == 409


def test_notification_detail_checks_owner_and_pagination(pair):
    a, b, sid = pair
    inbox = a.get("/notifications").json()
    assert inbox
    nid = inbox[0]["id"]
    assert a.get(f"/notifications/{nid}").status_code == 200
    assert b.get(f"/notifications/{nid}").status_code == 404
    assert a.post(f"/notifications/{nid}/read").json()["read"]
