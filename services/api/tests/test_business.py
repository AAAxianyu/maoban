from concurrent.futures import ThreadPoolExecutor
from uuid import uuid4

from conftest import activate, complete
from sqlalchemy import func, select, text

from app.db import base
from app.db import models as m


def assert_reconciled(sid):
    with base.SessionLocal() as db:
        for w in db.scalars(select(m.Wallet).where(m.Wallet.space_id == sid)):
            total = db.scalar(
                select(func.coalesce(func.sum(m.Ledger.delta), 0)).where(
                    m.Ledger.space_id == sid, m.Ledger.user_id == w.user_id
                )
            )
            assert w.balance == total
        events = list(db.scalars(select(m.Event.seq).where(m.Event.space_id == sid).order_by(m.Event.seq)))
        assert events == list(range(1, len(events) + 1))
        assert db.get(m.Space, sid).seq == len(events)


def test_35_repeat_reverse_restore(planned):
    a, b, sid, items = planned
    complete(b, sid, items)
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 35
    i = items[-1]
    for _ in range(3):
        r = b.post(
            f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 0}
        )
        assert r.status_code == 200
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 35
    r = b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": False, "expected_version": 1})
    assert r.json()["wallet"]["balance"] == 35 - i["points"] - 5
    assert b.get(f"/spaces/{sid}/growth").json()["permanent_xp"] == 3
    r = b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": True, "expected_version": 2})
    assert r.json()["wallet"]["balance"] == 35
    assert b.get(f"/spaces/{sid}/growth").json()["permanent_xp"] == 3
    assert (
        a.post(
            f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": False, "expected_version": 3}
        ).status_code
        == 403
    )
    assert_reconciled(sid)


def test_same_task_concurrent_distinct_keys(planned):
    _, b, sid, items = planned
    i = items[0]
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(
            executor.map(
                lambda _: b.post(
                    f"/spaces/{sid}/instances/{i['id']}/checkin",
                    {"desired_state": True, "expected_version": 0},
                ),
                range(16),
            )
        )
    assert all(r.status_code == 200 for r in results)
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == i["points"]
    assert b.get(f"/spaces/{sid}/growth").json()["permanent_xp"] == 1
    assert_reconciled(sid)


def test_idempotency_and_stale_opposite(planned):
    _, b, sid, items = planned
    path = f"/spaces/{sid}/instances/{items[0]['id']}/checkin"
    key = str(uuid4())
    payload = {"desired_state": True, "expected_version": 0}
    first = b.post(path, payload, key)
    assert b.post(path, payload, key).json() == first.json()
    assert b.post(path, {"desired_state": False, "expected_version": 0}, key).status_code == 409
    assert b.post(path, {"desired_state": False, "expected_version": 0}).json()["code"] == "VERSION_CONFLICT"
    assert_reconciled(sid)


def make_reward(a, b, sid, price=20, stock=1):
    r = a.post(
        f"/spaces/{sid}/rewards",
        {
            "recipient_id": b.id,
            "title": "一杯饮料",
            "description": "约好时间",
            "price": price,
            "stock": stock,
            "published": True,
        },
    )
    assert r.status_code == 200, r.text
    return r.json()


def test_last_inventory_and_once_refund(planned):
    a, b, sid, items = planned
    complete(b, sid, items)
    reward = make_reward(a, b, sid)
    path = f"/spaces/{sid}/rewards/{reward['id']}/redeem"
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda _: b.post(path, {"confirmed_price": 20}), range(8)))
    assert sum(r.status_code == 200 for r in results) == 1
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 15
    order = next(r.json()["order"] for r in results if r.status_code == 200)
    cmd = f"/spaces/{sid}/orders/{order['id']}/command"
    with ThreadPoolExecutor(max_workers=8) as executor:
        results = list(
            executor.map(lambda _: b.post(cmd, {"action": "cancel", "expected_version": 1}), range(8))
        )
    assert all(r.status_code == 200 for r in results)
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 35
    assert b.get(f"/spaces/{sid}/rewards").json()[0]["stock"] == 1
    assert_reconciled(sid)


def test_two_spends_competing_balance(planned):
    a, b, sid, items = planned
    complete(b, sid, items)
    reward = make_reward(a, b, sid, stock=None)
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(
            executor.map(
                lambda _: b.post(f"/spaces/{sid}/rewards/{reward['id']}/redeem", {"confirmed_price": 20}),
                range(2),
            )
        )
    assert sorted(r.status_code for r in results) == [200, 409]
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 15
    assert len(b.get(f"/spaces/{sid}/orders").json()) == 1
    assert_reconciled(sid)


def test_debt_and_fulfill_refund_agreement(planned):
    a, b, sid, items = planned
    complete(b, sid, items)
    r = make_reward(a, b, sid, price=30, stock=2)
    o = b.post(f"/spaces/{sid}/rewards/{r['id']}/redeem", {"confirmed_price": 30}).json()["order"]
    i = next(i for i in items if i["points"] == 15)
    b.post(f"/spaces/{sid}/instances/{i['id']}/checkin", {"desired_state": False, "expected_version": 1})
    assert b.get(f"/spaces/{sid}/wallet").json() == {"balance": -15, "available": 0, "debt": 15}
    assert b.post(f"/spaces/{sid}/rewards/{r['id']}/redeem", {"confirmed_price": 30}).status_code == 409
    path = f"/spaces/{sid}/orders/{o['id']}/command"
    assert a.post(path, {"action": "fulfill", "expected_version": 1}).status_code == 200
    assert b.post(path, {"action": "cancel", "expected_version": 2}).status_code == 409
    assert (
        b.post(path, {"action": "request_cancel", "expected_version": 2, "reason": "未收到"}).status_code
        == 200
    )
    assert b.post(path, {"action": "approve_cancel", "expected_version": 3}).status_code == 403
    assert a.post(path, {"action": "approve_cancel", "expected_version": 3}).status_code == 200
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 15
    assert_reconciled(sid)


def test_order_snapshot_and_confirm(planned):
    a, b, sid, items = planned
    complete(b, sid, items)
    r = make_reward(a, b, sid)
    assert (
        b.post(f"/spaces/{sid}/rewards/{r['id']}/redeem", {"confirmed_price": 19}).json()["code"]
        == "PRICE_CHANGED"
    )
    o = b.post(f"/spaces/{sid}/rewards/{r['id']}/redeem", {"confirmed_price": 20}).json()["order"]
    edit = {k: r[k] for k in ("recipient_id", "title", "description", "price", "stock", "published", "icon")}
    edit.update(price=99, title="改价后饮料", expected_version=1)
    assert a.put(f"/spaces/{sid}/rewards/{r['id']}", edit).status_code == 200
    assert b.get(f"/spaces/{sid}/orders").json()[0]["price"] == 20
    path = f"/spaces/{sid}/orders/{o['id']}/command"
    assert b.post(path, {"action": "fulfill", "expected_version": 1}).status_code == 403
    assert a.post(path, {"action": "fulfill", "expected_version": 1}).status_code == 200
    assert b.post(path, {"action": "confirm", "expected_version": 2}).status_code == 200
    assert b.post(path, {"action": "cancel", "expected_version": 3}).status_code == 409
    assert_reconciled(sid)


def test_permissions_capacity_export(pair, client):
    a, b, sid = pair
    outsider = activate(client, "third")
    assert outsider.get(f"/spaces/{sid}/snapshot").status_code == 403
    assert outsider.get(f"/spaces/{sid}/export").status_code == 403
    assert a.post(f"/spaces/{sid}/invitations").json()["code"] == "SPACE_FULL"
    export = a.get(f"/spaces/{sid}/export")
    assert export.status_code == 200
    assert "password" not in export.text and "token" not in export.text
    assert len(export.json()["memberships"]) == 2


def test_rollback_has_no_half_ledger(planned, monkeypatch):
    _, b, sid, items = planned
    from app.domain import tasks

    original = tasks.emit

    def fail(*args, **kwargs):
        original(*args, **kwargs)
        raise RuntimeError("injected transaction failure")

    monkeypatch.setattr(tasks, "emit", fail)
    import pytest

    with pytest.raises(RuntimeError):
        b.post(
            f"/spaces/{sid}/instances/{items[0]['id']}/checkin",
            {"desired_state": True, "expected_version": 0},
        )
    assert b.get(f"/spaces/{sid}/wallet").json()["balance"] == 0
    assert b.get(f"/spaces/{sid}/growth").json()["permanent_xp"] == 0
    with base.SessionLocal() as db:
        assert db.scalar(select(func.count()).select_from(m.Ledger)) == 0
    assert_reconciled(sid)


def test_database_is_postgres():
    with base.engine.connect() as c:
        assert "PostgreSQL 18" in c.scalar(text("SELECT version()"))
