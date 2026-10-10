import hashlib
import json
from datetime import date, datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import select

from app.db import models as m
from app.db.base import now


class DomainError(Exception):
    def __init__(self, code, message, status=400, **details):
        self.code, self.message, self.status, self.details = code, message, status, details


def require(condition, code="FORBIDDEN", message="无权进行此操作", status=403, **details):
    if not condition:
        raise DomainError(code, message, status, **details)


def one(db, model, **values):
    return db.scalar(select(model).filter_by(**values))


def rows(db, model, **values):
    return list(db.scalars(select(model).filter_by(**values)))


def page(db, model, offset, limit, **values):
    return list(
        db.scalars(
            select(model).filter_by(**values).order_by(model.created_at, model.id).offset(offset).limit(limit)
        )
    )


def dump(row):
    return {c.name: scalar(getattr(row, c.name)) for c in row.__table__.columns}


def scalar(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def timezone(value):
    try:
        return ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError):
        raise DomainError("INVALID_TIMEZONE", "请选择有效的 IANA 时区") from None


def member(db, sid, user_id):
    require(db.get(m.Member, (sid, user_id)) is not None)


def lock_space(db, sid, user_id):
    member(db, sid, user_id)
    space = db.scalar(select(m.Space).where(m.Space.id == sid).with_for_update())
    require(space is not None, "NOT_FOUND", "小屋不存在", 404)
    return space


def partner(db, sid, user_id):
    return db.scalar(select(m.Member.user_id).where(m.Member.space_id == sid, m.Member.user_id != user_id))


def config(db, sid, day=None):
    configs = rows(db, m.SpaceConfig, space_id=sid, status="accepted")
    require(bool(configs), "RULES_NOT_READY", "小屋规则尚未建立", 409)
    initial = min(configs, key=lambda c: c.effective_date)
    # Changes take effect on their named calendar date in the previously active zone.
    result = initial
    for c in sorted(configs, key=lambda c: (c.effective_date, c.created_at)):
        reference = day or now().astimezone(timezone(result.timezone)).date()
        if c.effective_date <= reference:
            result = c
    return result


def local_today(db, sid):
    return now().astimezone(timezone(config(db, sid).timezone)).date()


def emit(db, space, actor, kind, entity_id, version=1, data=None):
    space.seq += 1
    event = m.Event(
        space_id=space.id,
        seq=space.seq,
        actor_id=actor,
        type=kind,
        entity_id=entity_id,
        entity_version=version,
        data=data or {},
    )
    db.add(event)
    db.flush()
    for recipient in rows(db, m.Member, space_id=space.id):
        if recipient.user_id != actor:
            n = m.Notification(space_id=space.id, user_id=recipient.user_id, event_id=event.id)
            db.add(n)
            db.flush()
            db.add(m.Outbox(notification_id=n.id))
    return event


def mutation(db, sid, actor, key, operation, payload, action):
    require(key and 8 <= len(key) <= 100, "IDEMPOTENCY_REQUIRED", "请提供操作唯一标识", 400)
    space = lock_space(db, sid, actor)
    # A user lock also serializes reuse of the same key across separate spaces.
    db.execute(select(m.User).where(m.User.id == actor).with_for_update())
    fingerprint = digest(json.dumps([sid, operation, payload], sort_keys=True, default=scalar))
    prior = db.get(m.Idempotency, (actor, key))
    if prior:
        require(
            prior.payload_hash == fingerprint, "IDEMPOTENCY_CONFLICT", "同一操作标识不能用于不同内容", 409
        )
        return prior.result
    result = action(space)
    db.flush()
    # Use only JSON-ready values; results are part of the same commit as balances/events.
    result = json.loads(json.dumps(result, default=scalar))
    db.add(m.Idempotency(user_id=actor, key=key, payload_hash=fingerprint, result=result))
    db.flush()
    return result


def award(db, sid, beneficiary, source, expected, actor, reason):
    entitlement = one(db, m.Entitlement, space_id=sid, user_id=beneficiary, source=source)
    if entitlement is None:
        entitlement = m.Entitlement(space_id=sid, user_id=beneficiary, source=source, net=0, revision=0)
        db.add(entitlement)
        db.flush()
    delta = expected - entitlement.net
    if delta:
        wallet = db.get(m.Wallet, (sid, beneficiary))
        wallet.balance += delta
        entitlement.net = expected
        entitlement.revision += 1
        db.add(
            m.Ledger(
                space_id=sid,
                user_id=beneficiary,
                actor_id=actor,
                entitlement_id=entitlement.id,
                source=source,
                revision=entitlement.revision,
                delta=delta,
                balance_after=wallet.balance,
                reason=reason,
            )
        )
    return delta


def wallet_view(db, sid, user_id):
    w = db.get(m.Wallet, (sid, user_id))
    return {"balance": w.balance, "available": max(w.balance, 0), "debt": max(-w.balance, 0)}


def entity(db, model, sid, entity_id):
    row = db.get(model, entity_id)
    require(row is not None and row.space_id == sid, "NOT_FOUND", "记录不存在", 404)
    return row
