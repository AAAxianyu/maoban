from app.db import models as m
from app.domain.common import award, dump, emit, entity, member, require, wallet_view


def save_reward(db, space, actor, data, rid=None):
    member(db, space.id, data["recipient_id"])
    require(data["recipient_id"] != actor, "INVALID_RECIPIENT", "奖品只能提供给另一位成员", 400)
    if rid:
        reward = entity(db, m.Reward, space.id, rid)
        require(reward.provider_id == actor)
        require(reward.version == data.pop("expected_version"), "VERSION_CONFLICT", "奖品已更新", 409)
        for k, v in data.items():
            setattr(reward, k, v)
        reward.version += 1
    else:
        reward = m.Reward(space_id=space.id, provider_id=actor, **data)
        db.add(reward)
    db.flush()
    emit(db, space, actor, "reward.saved", reward.id, reward.version)
    return dump(reward)


def redeem(db, space, actor, rid, price):
    r = entity(db, m.Reward, space.id, rid)
    require(r.recipient_id == actor and r.provider_id != actor)
    require(r.published, "REWARD_UNAVAILABLE", "奖品已下架", 409)
    require(r.price == price, "PRICE_CHANGED", "价格已变化，请重新确认", 409, price=r.price)
    require(r.stock is None or r.stock > 0, "REWARD_OUT_OF_STOCK", "奖品已售罄", 409)
    w = db.get(m.Wallet, (space.id, actor))
    require(w.balance >= r.price, "INSUFFICIENT_POINTS", "可用小鱼干不足", 409)
    order = m.Order(
        space_id=space.id,
        reward_id=r.id,
        provider_id=r.provider_id,
        recipient_id=actor,
        title=r.title,
        description=r.description,
        price=r.price,
        finite_stock=r.stock is not None,
    )
    db.add(order)
    db.flush()
    if r.stock is not None:
        r.stock -= 1
    award(db, space.id, actor, "order:" + order.id, -r.price, actor, "兑换：" + r.title)
    emit(db, space, actor, "order.redeemed", order.id)
    return {"order": dump(order), "wallet": wallet_view(db, space.id, actor)}


def refund(db, space, actor, o):
    o.status, o.version = "cancelled", o.version + 1
    if o.reward_id:
        if o.finite_stock:
            r = entity(db, m.Reward, space.id, o.reward_id)
            # Inventory mode cannot erase reservation history: return only to a finite pool.
            if r.stock is not None:
                r.stock += 1
        award(db, space.id, o.recipient_id, "order:" + o.id, 0, actor, "取消退款：" + o.title)


def order_action(db, space, actor, oid, action, expected, reason=""):
    o = entity(db, m.Order, space.id, oid)
    require(actor in (o.provider_id, o.recipient_id))
    if action == "cancel" and o.status == "cancelled":
        return {"order": dump(o), "wallet": wallet_view(db, space.id, o.recipient_id)}
    if action == "fulfill" and o.status in ("fulfilled", "completed") and actor == o.provider_id:
        return {"order": dump(o)}
    if action == "confirm" and o.status == "completed" and actor == o.recipient_id:
        return {"order": dump(o)}
    require(o.version == expected, "VERSION_CONFLICT", "订单已更新", 409, order=dump(o))
    if action == "fulfill":
        require(actor == o.provider_id)
        require(o.status == "pending", "INVALID_STATE", "订单当前不可兑现", 409)
        o.status = "fulfilled"
        o.ever_fulfilled = True
        o.version += 1
    elif action == "confirm":
        require(actor == o.recipient_id)
        require(o.status == "fulfilled", "INVALID_STATE", "请等待对方兑现", 409)
        o.status = "completed"
        o.version += 1
    elif action == "cancel":
        require(o.status == "pending", "REFUND_REQUIRES_AGREEMENT", "已兑现订单须双方同意退款", 409)
        require(not o.milestone_id, "MILESTONE_ORDER", "阶段赠品通过目标更正处理", 409)
        o.cancel_reason = reason
        refund(db, space, actor, o)
    elif action == "request_cancel":
        require(o.status == "fulfilled", "INVALID_STATE", "当前不能申请退款", 409)
        require(bool(reason.strip()), "REASON_REQUIRED", "请说明未收到或退款原因", 400)
        require(o.cancel_requested_by is None, "CANCELLATION_PENDING", "已有待处理申请", 409)
        o.cancel_requested_by, o.cancel_reason = actor, reason
        o.version += 1
    elif action in ("approve_cancel", "reject_cancel"):
        require(
            o.status == "fulfilled" and o.cancel_requested_by is not None,
            "INVALID_STATE",
            "没有待处理退款申请",
            409,
        )
        require(actor != o.cancel_requested_by)
        if action == "approve_cancel":
            refund(db, space, actor, o)
        else:
            o.version += 1
        o.cancel_requested_by = None
    emit(db, space, actor, "order." + action, o.id, o.version)
    return {"order": dump(o), "wallet": wallet_view(db, space.id, o.recipient_id)}
