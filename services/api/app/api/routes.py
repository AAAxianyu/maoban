import secrets
from datetime import date, timedelta

from fastapi import APIRouter, Depends, Header, Query
from sqlalchemy import select

from app.api import schemas as s
from app.api.auth import authenticate, current
from app.db import models as m
from app.db.base import get_db, now
from app.domain import growth, rewards, tasks
from app.domain.common import (
    config,
    digest,
    dump,
    emit,
    entity,
    local_today,
    lock_space,
    member,
    mutation,
    one,
    page,
    partner,
    require,
    rows,
    timezone,
    wallet_view,
)

router = APIRouter(tags=["spaces"])


def run(db, sid, user, key, operation, data, action):
    payload = data.model_dump() if hasattr(data, "model_dump") else data
    result = mutation(db, sid, user.id, key, operation, payload, action)
    db.commit()
    return result


@router.post("/spaces")
def create_space(
    data: s.CreateSpace, user=Depends(current), db=Depends(get_db), key: str = Header(alias="Idempotency-Key")
):
    timezone(data.timezone)
    db.execute(select(m.User).where(m.User.id == user.id).with_for_update())
    fingerprint = digest("create_space:" + data.model_dump_json())
    prior = db.get(m.Idempotency, (user.id, key))
    if prior:
        require(prior.payload_hash == fingerprint, "IDEMPOTENCY_CONFLICT", "操作标识已使用", 409)
        return prior.result
    space = m.Space(name=data.name, creator_id=user.id)
    db.add(space)
    db.flush()
    db.add_all(
        [
            m.Member(space_id=space.id, user_id=user.id, slot=1),
            m.Wallet(space_id=space.id, user_id=user.id),
            m.SpaceConfig(
                space_id=space.id,
                proposer_id=user.id,
                timezone=data.timezone,
                effective_date=now().astimezone(timezone(data.timezone)).date(),
                status="accepted",
                attendance_points=0,
                accepted_at=now(),
            ),
        ]
    )
    result = dump(space)
    db.add(m.Idempotency(user_id=user.id, key=key, payload_hash=fingerprint, result=result))
    db.commit()
    return result


@router.post("/spaces/{sid}/invitations")
def invite(sid: str, user=Depends(current), db=Depends(get_db), key: str = Header(alias="Idempotency-Key")):
    issued = None

    def action(space):
        nonlocal issued
        require(len(rows(db, m.Member, space_id=sid)) < 2, "SPACE_FULL", "小屋已满", 409)
        token = secrets.token_urlsafe(32)
        issued = token
        # Store only the hash. The idempotent response intentionally excludes the secret:
        # an invitation lost before receipt should be revoked and recreated.
        i = m.Invitation(
            space_id=sid, creator_id=user.id, token_hash=digest(token), expires_at=now() + timedelta(hours=48)
        )
        db.add(i)
        db.flush()
        emit(db, space, user.id, "invitation.created", i.id)
        return {"id": i.id, "expires_at": i.expires_at.isoformat()}

    result = run(db, sid, user, key, "invite", {}, action)
    return {**result, **({"token": issued} if issued else {"reissue_required": True})}


@router.post("/spaces/{sid}/invitations/{iid}/revoke")
def revoke_invite(
    sid: str, iid: str, user=Depends(current), db=Depends(get_db), key: str = Header(alias="Idempotency-Key")
):
    def action(space):
        i = entity(db, m.Invitation, sid, iid)
        require(i.creator_id == user.id)
        i.revoked = True
        emit(db, space, user.id, "invitation.revoked", iid)
        return {"revoked": True}

    return run(db, sid, user, key, "revoke_invite", {"id": iid}, action)


@router.post("/invitations/claim")
def claim(data: s.Join, user=Depends(current), db=Depends(get_db)):
    i = one(db, m.Invitation, token_hash=digest(data.token))
    require(i is not None, "INVITE_INVALID", "邀请码无效", 400)
    space = db.scalar(select(m.Space).where(m.Space.id == i.space_id).with_for_update())
    db.refresh(i)
    if i.used_by == user.id:
        return dump(space)
    require(not i.revoked and not i.used_by, "INVITE_INVALID", "邀请已使用或撤销", 409)
    require(i.expires_at > now(), "INVITE_EXPIRED", "邀请已过期", 409)
    require(len(rows(db, m.Member, space_id=space.id)) < 2, "SPACE_FULL", "小屋已满", 409)
    require(not db.get(m.Member, (space.id, user.id)), "ALREADY_MEMBER", "你已在小屋中", 409)
    db.add_all(
        [m.Member(space_id=space.id, user_id=user.id, slot=2), m.Wallet(space_id=space.id, user_id=user.id)]
    )
    i.used_by = user.id
    emit(db, space, user.id, "member.joined", user.id)
    db.commit()
    return dump(space)


@router.get("/spaces/{sid}")
def space_info(sid: str, user=Depends(current), db=Depends(get_db)):
    member(db, sid, user.id)
    return {
        "space": dump(db.get(m.Space, sid)),
        "config": dump(config(db, sid)),
        "members": [
            {
                "id": who.user_id,
                "nickname": db.get(m.User, who.user_id).nickname,
                "avatar": db.get(m.User, who.user_id).avatar,
            }
            for who in rows(db, m.Member, space_id=sid)
        ],
        "rules": [dump(c) for c in rows(db, m.SpaceConfig, space_id=sid)],
        "today": local_today(db, sid).isoformat(),
    }


@router.post("/spaces/{sid}/rules")
def propose_rule(
    sid: str,
    data: s.Rule,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    timezone(data.timezone)

    def action(space):
        require(data.effective_date > local_today(db, sid), "INVALID_DATE", "小屋规则次日或以后生效", 400)
        require(partner(db, sid, user.id), "PARTNER_REQUIRED", "需另一位成员接受奖励规则", 409)
        c = m.SpaceConfig(space_id=sid, proposer_id=user.id, **data.model_dump())
        db.add(c)
        db.flush()
        emit(db, space, user.id, "rules.proposed", c.id)
        return dump(c)

    return run(db, sid, user, key, "rule.propose", data, action)


@router.post("/spaces/{sid}/rules/{rid}/decision")
def rule_decision(
    sid: str,
    rid: str,
    data: s.Decision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        c = entity(db, m.SpaceConfig, sid, rid)
        require(user.id != c.proposer_id)
        require(c.status == "pending", "INVALID_STATE", "规则已处理", 409)
        require(c.effective_date > local_today(db, sid), "INVALID_DATE", "请重新提议未来生效日期", 409)
        c.status, c.accepted_at = (
            "accepted" if data.accepted else "rejected",
            now() if data.accepted else None,
        )
        emit(db, space, user.id, "rules." + c.status, c.id)
        return dump(c)

    return run(db, sid, user, key, "rule.decide:" + rid, data, action)


@router.get("/spaces/{sid}/tasks")
def task_list(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [
        {
            "task": dump(t),
            "versions": [dump(v) for v in rows(db, m.TaskVersion, task_id=t.id)],
            "schedule": [dump(c) for c in rows(db, m.ScheduleChange, task_id=t.id)],
        }
        for t in page(db, m.Task, offset, limit, space_id=sid)
    ]


@router.post("/spaces/{sid}/tasks")
def task_create(
    sid: str,
    data: s.TaskData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "task.create",
        data,
        lambda space: tasks.propose(db, space, user.id, data.model_dump()),
    )


@router.post("/spaces/{sid}/tasks/{tid}/versions")
def task_edit(
    sid: str,
    tid: str,
    data: s.TaskData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "task.version:" + tid,
        data,
        lambda space: tasks.propose(db, space, user.id, data.model_dump(), tid),
    )


@router.post("/spaces/{sid}/task-versions/{vid}/decision")
def task_decision(
    sid: str,
    vid: str,
    data: s.Decision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "task.decision:" + vid,
        data,
        lambda space: tasks.decide(db, space, user.id, vid, data.accepted, data.reason),
    )


@router.post("/spaces/{sid}/tasks/{tid}/schedule")
def schedule(
    sid: str,
    tid: str,
    data: s.Schedule,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        t = entity(db, m.Task, sid, tid)
        require(user.id in (t.proposer_id, t.executor_id))
        require(data.effective_date > local_today(db, sid), "INVALID_DATE", "暂停和归档只影响未来日期", 400)
        c = m.ScheduleChange(task_id=tid, **data.model_dump())
        db.add(c)
        db.flush()
        emit(db, space, user.id, "task.schedule", tid, data=data.model_dump(mode="json"))
        return dump(c)

    return run(db, sid, user, key, "schedule:" + tid, data, action)


@router.post("/spaces/{sid}/rest-dates")
def rest(
    sid: str,
    data: s.Rest,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        require(data.date > local_today(db, sid), "INVALID_DATE", "休息日需提前安排", 400)
        r = db.get(m.RestDate, (sid, user.id, data.date))
        if data.rest and r is None:
            db.add(m.RestDate(space_id=sid, user_id=user.id, date=data.date))
        elif not data.rest and r:
            db.delete(r)
        emit(db, space, user.id, "rest.changed", user.id, data=data.model_dump(mode="json"))
        return data.model_dump(mode="json")

    return run(db, sid, user, key, "rest", data, action)


@router.get("/spaces/{sid}/daily")
def daily(sid: str, day: date | None = None, user=Depends(current), db=Depends(get_db)):
    space = lock_space(db, sid, user.id)
    result = tasks.daily(db, space, day or local_today(db, sid))
    db.commit()
    return result


@router.post("/spaces/{sid}/instances/{iid}/checkin")
def checkin(
    sid: str,
    iid: str,
    data: s.Checkin,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "checkin:" + iid,
        data,
        lambda space: tasks.checkin(
            db, space, user.id, iid, data.desired_state, data.expected_version, data.note
        ),
    )


@router.post("/spaces/{sid}/instances/{iid}/note")
def note(
    sid: str,
    iid: str,
    data: s.Note,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        i = entity(db, m.Instance, sid, iid)
        require(i.user_id == user.id)
        require(i.version == data.expected_version, "VERSION_CONFLICT", "记录已更新", 409)
        i.note, i.version = data.note, i.version + 1
        emit(db, space, user.id, "checkin.note", iid, i.version)
        return dump(i)

    return run(db, sid, user, key, "note:" + iid, data, action)


@router.post("/spaces/{sid}/instances/{iid}/corrections")
def correction(
    sid: str,
    iid: str,
    data: s.CorrectionData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "correction:" + iid,
        data,
        lambda space: tasks.correction(db, space, user.id, iid, data.model_dump()),
    )


@router.get("/spaces/{sid}/corrections")
def correction_list(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [dump(x) for x in page(db, m.Correction, offset, limit, space_id=sid)]


@router.post("/spaces/{sid}/corrections/{cid}/decision")
def correction_decision(
    sid: str,
    cid: str,
    data: s.Decision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "correction.decision:" + cid,
        data,
        lambda space: tasks.decide_correction(db, space, user.id, cid, data.accepted),
    )


@router.get("/spaces/{sid}/wallet")
def wallet(sid: str, user=Depends(current), db=Depends(get_db)):
    member(db, sid, user.id)
    return wallet_view(db, sid, user.id)


@router.get("/spaces/{sid}/ledger")
def ledger(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [
        dump(x)
        for x in db.scalars(
            select(m.Ledger)
            .where(m.Ledger.space_id == sid, m.Ledger.user_id == user.id)
            .order_by(m.Ledger.created_at, m.Ledger.id)
            .offset(offset)
            .limit(limit)
        )
    ]


@router.get("/spaces/{sid}/rewards")
def reward_list(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [dump(x) for x in page(db, m.Reward, offset, limit, space_id=sid)]


@router.post("/spaces/{sid}/rewards")
def reward_create(
    sid: str,
    data: s.RewardData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "reward.create",
        data,
        lambda space: rewards.save_reward(db, space, user.id, data.model_dump()),
    )


@router.put("/spaces/{sid}/rewards/{rid}")
def reward_edit(
    sid: str,
    rid: str,
    data: s.RewardUpdate,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "reward.edit:" + rid,
        data,
        lambda space: rewards.save_reward(db, space, user.id, data.model_dump(), rid),
    )


@router.post("/spaces/{sid}/rewards/{rid}/redeem")
def redeem(
    sid: str,
    rid: str,
    data: s.Redemption,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "redeem:" + rid,
        data,
        lambda space: rewards.redeem(db, space, user.id, rid, data.confirmed_price),
    )


@router.get("/spaces/{sid}/orders")
def orders(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [dump(x) for x in page(db, m.Order, offset, limit, space_id=sid)]


@router.post("/spaces/{sid}/orders/{oid}/command")
def order_command(
    sid: str,
    oid: str,
    data: s.OrderCommand,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "order.command:" + oid,
        data,
        lambda space: rewards.order_action(
            db, space, user.id, oid, data.action, data.expected_version, data.reason
        ),
    )


@router.get("/spaces/{sid}/wishes")
def wishes(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [dump(x) for x in page(db, m.Wish, offset, limit, space_id=sid)]


@router.post("/spaces/{sid}/wishes")
def wish_create(
    sid: str,
    data: s.WishData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        w = m.Wish(space_id=sid, requester_id=user.id, **data.model_dump())
        db.add(w)
        db.flush()
        emit(db, space, user.id, "wish.created", w.id)
        return dump(w)

    return run(db, sid, user, key, "wish.create", data, action)


@router.post("/spaces/{sid}/wishes/{wid}/decision")
def wish_decision(
    sid: str,
    wid: str,
    data: s.WishDecision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        w = entity(db, m.Wish, sid, wid)
        require(user.id != w.requester_id)
        require(w.status == "pending", "INVALID_STATE", "愿望已处理", 409)
        if data.accepted:
            r = entity(db, m.Reward, sid, data.reward_id)
            require(r.provider_id == user.id and r.recipient_id == w.requester_id)
            w.reward_id = r.id
        w.status = "accepted" if data.accepted else "rejected"
        emit(db, space, user.id, "wish." + w.status, wid)
        return dump(w)

    return run(db, sid, user, key, "wish.decision:" + wid, data, action)


@router.get("/spaces/{sid}/milestones")
def goals(
    sid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [
        {**dump(g), "progress": growth.milestone_progress(db, g)}
        for g in page(db, m.Milestone, offset, limit, space_id=sid)
    ]


@router.post("/spaces/{sid}/milestones")
def goal_create(
    sid: str,
    data: s.GoalData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    return run(
        db,
        sid,
        user,
        key,
        "milestone.create",
        data,
        lambda space: growth.propose_goal(db, space, user.id, data.model_dump()),
    )


@router.post("/spaces/{sid}/milestones/{gid}/decision")
def goal_decision(
    sid: str,
    gid: str,
    data: s.Decision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        g = entity(db, m.Milestone, sid, gid)
        approver = g.executor_id if g.proposer_id != g.executor_id else g.approver_id
        require(user.id == approver and user.id != g.proposer_id)
        require(g.status == "pending", "INVALID_STATE", "目标已处理", 409)
        g.status, g.version = "accepted" if data.accepted else "rejected", g.version + 1
        v = one(db, m.MilestoneVersion, milestone_id=gid, version=1)
        if v:
            v.status = g.status
            v.accepted_at = now() if data.accepted else None
            v.rejection_reason = None if data.accepted else data.reason
        emit(db, space, user.id, "milestone." + g.status, gid, g.version)
        growth.recompute_goal(db, space, user.id, g)
        return dump(g)

    return run(db, sid, user, key, "milestone.decision:" + gid, data, action)


@router.post("/spaces/{sid}/milestones/{gid}/evidence")
def evidence(
    sid: str,
    gid: str,
    data: s.Evidence,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        g = entity(db, m.Milestone, sid, gid)
        require(g.executor_id == user.id and g.metric == "manual")
        require(
            g.status == "accepted" and g.starts_on <= local_today(db, sid) <= g.ends_on,
            "INVALID_STATE",
            "目标尚未生效或已过期",
            409,
        )
        require(g.version == data.expected_version, "VERSION_CONFLICT", "目标已更新", 409)
        require(not g.manual_confirmed, "INVALID_STATE", "目标已经确认", 409)
        g.evidence, g.version = data.evidence, g.version + 1
        emit(db, space, user.id, "milestone.evidence", gid, g.version)
        return dump(g)

    return run(db, sid, user, key, "milestone.evidence:" + gid, data, action)


@router.post("/spaces/{sid}/milestones/{gid}/confirm")
def goal_confirm(
    sid: str,
    gid: str,
    data: s.Decision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        g = entity(db, m.Milestone, sid, gid)
        require(user.id == g.approver_id and user.id != g.executor_id)
        require(
            g.status == "accepted" and g.metric == "manual" and bool(g.evidence),
            "INVALID_STATE",
            "没有待确认的目标证据",
            409,
        )
        g.manual_confirmed, g.version = data.accepted, g.version + 1
        growth.recompute_goal(db, space, user.id, g)
        emit(
            db,
            space,
            user.id,
            "milestone.confirmed" if data.accepted else "milestone.corrected",
            gid,
            g.version,
        )
        return dump(g)

    return run(db, sid, user, key, "milestone.confirm:" + gid, data, action)


@router.get("/spaces/{sid}/growth")
def growth_info(sid: str, user=Depends(current), db=Depends(get_db)):
    member(db, sid, user.id)
    return growth.growth_view(db, sid)


@router.get("/spaces/{sid}/events")
def events(
    sid: str,
    after_seq: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    return [
        dump(x)
        for x in db.scalars(
            select(m.Event)
            .where(m.Event.space_id == sid, m.Event.seq > after_seq)
            .order_by(m.Event.seq)
            .limit(limit)
        )
    ]


@router.post("/spaces/{sid}/events/{eid}/reactions")
def react(
    sid: str,
    eid: str,
    data: s.ReactionData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        event = entity(db, m.Event, sid, eid)
        require(event.actor_id != user.id, "SELF_REACTION", "请鼓励对方的动态", 400)
        prior = one(db, m.Reaction, event_id=eid, user_id=user.id, kind=data.kind)
        if prior:
            return dump(prior)
        recent = db.scalar(
            select(m.Event.id).where(
                m.Event.space_id == sid,
                m.Event.actor_id == user.id,
                m.Event.type == "interaction.reaction",
                m.Event.created_at > now() - timedelta(seconds=2),
            )
        )
        require(not recent, "RATE_LIMITED", "稍等一下再发送鼓励", 429)
        r = m.Reaction(event_id=eid, user_id=user.id, **data.model_dump())
        db.add(r)
        db.flush()
        emit(
            db,
            space,
            user.id,
            "interaction.reaction",
            r.id,
            data={"event_id": eid, "kind": data.kind, "message": data.message},
        )
        return dump(r)

    return run(db, sid, user, key, "reaction:" + eid, data, action)


@router.post("/spaces/{sid}/nudge")
def nudge(sid: str, user=Depends(current), db=Depends(get_db), key: str = Header(alias="Idempotency-Key")):
    def action(space):
        recipient = partner(db, sid, user.id)
        require(recipient, "PARTNER_REQUIRED", "另一位成员尚未加入", 409)
        require(
            db.get(m.User, recipient).preferences.get("gentle_nudges", True),
            "NUDGES_DISABLED",
            "对方已关闭轻提醒",
            409,
        )
        day = local_today(db, sid).isoformat()
        prior = [
            e
            for e in rows(db, m.Event, space_id=sid, type="interaction.nudge")
            if e.data.get("date") == day and e.entity_id == recipient
        ]
        require(not prior, "NUDGE_LIMIT", "今天已经轻轻提醒过了", 429)
        emit(db, space, user.id, "interaction.nudge", recipient, data={"date": day})
        return {"sent": True}

    return run(db, sid, user, key, "nudge", {}, action)


@router.get("/spaces/{sid}/snapshot")
def snapshot(sid: str, user=Depends(current), db=Depends(get_db)):
    # All mutations lock the space; holding it makes the snapshot and cursor consistent.
    space = lock_space(db, sid, user.id)
    result = {
        "space": space_info(sid, user, db),
        "daily": tasks.daily(db, space, local_today(db, sid)),
        "wallet": wallet_view(db, sid, user.id),
        "rewards": [dump(x) for x in rows(db, m.Reward, space_id=sid)],
        "orders": [dump(x) for x in rows(db, m.Order, space_id=sid)],
        "growth": growth.growth_view(db, sid),
        "snapshot_seq": space.seq,
    }
    result["rest_dates"] = [dump(r) for r in rows(db, m.RestDate, space_id=sid)]
    latest = db.scalar(
        select(m.Event)
        .where(m.Event.space_id == sid, m.Event.actor_id != user.id)
        .order_by(m.Event.seq.desc())
        .limit(1)
    )
    result["latest_partner_event"] = dump(latest) if latest else None
    db.commit()
    return result


@router.get("/spaces/{sid}/export")
def export(sid: str, user=Depends(current), db=Depends(get_db)):
    space = lock_space(db, sid, user.id)
    result = {
        "schema_version": 1,
        "exported_at": now().isoformat(),
        "space": dump(space),
        "snapshot_seq": space.seq,
    }
    for model in (
        m.Member,
        m.SpaceConfig,
        m.Task,
        m.Instance,
        m.DailyPlan,
        m.RestDate,
        m.Wallet,
        m.Ledger,
        m.Entitlement,
        m.Reward,
        m.Order,
        m.Wish,
        m.Milestone,
        m.Correction,
        m.Achievement,
        m.Contribution,
        m.Unlock,
        m.Event,
    ):
        result[model.__tablename__] = [dump(x) for x in rows(db, model, space_id=sid)]
    tids = [x["id"] for x in result["task_templates"]]
    result["task_versions"] = [dump(v) for tid in tids for v in rows(db, m.TaskVersion, task_id=tid)]
    result["task_schedule_changes"] = [
        dump(v) for tid in tids for v in rows(db, m.ScheduleChange, task_id=tid)
    ]
    eids = [x["id"] for x in result["events"]]
    result["reactions"] = [dump(r) for eid in eids for r in rows(db, m.Reaction, event_id=eid)]
    result["milestone_versions"] = [
        dump(v)
        for g in rows(db, m.Milestone, space_id=sid)
        for v in rows(db, m.MilestoneVersion, milestone_id=g.id)
    ]
    result["profiles"] = [
        {
            "id": x.user_id,
            "nickname": db.get(m.User, x.user_id).nickname,
            "avatar": db.get(m.User, x.user_id).avatar,
        }
        for x in rows(db, m.Member, space_id=sid)
    ]
    db.commit()
    return result


@router.put("/preferences")
def preferences(
    data: s.Preferences, user=Depends(current), db=Depends(get_db), key: str = Header(alias="Idempotency-Key")
):
    require(8 <= len(key) <= 100, "IDEMPOTENCY_REQUIRED", "请提供操作唯一标识", 400)
    db.execute(select(m.User).where(m.User.id == user.id).with_for_update())
    fingerprint = digest("preferences:" + data.model_dump_json())
    prior = db.get(m.Idempotency, (user.id, key))
    if prior:
        require(prior.payload_hash == fingerprint, "IDEMPOTENCY_CONFLICT", "操作标识已使用", 409)
        return prior.result
    user.nickname, user.avatar = data.nickname, data.avatar
    user.preferences = data.model_dump(exclude={"nickname", "avatar"})
    db.add(m.Idempotency(user_id=user.id, key=key, payload_hash=fingerprint, result=user.preferences))
    db.commit()
    return user.preferences


@router.get("/notifications")
def notifications(
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=50, ge=1, le=100),
    user=Depends(current),
    db=Depends(get_db),
):
    return [
        {**dump(n), "event": dump(db.get(m.Event, n.event_id))}
        for n in db.scalars(
            select(m.Notification)
            .where(m.Notification.user_id == user.id)
            .order_by(m.Notification.created_at.desc())
            .offset(offset)
            .limit(limit)
        )
    ]


@router.get("/notifications/{nid}")
def notification_detail(nid: str, user=Depends(current), db=Depends(get_db)):
    n = db.get(m.Notification, nid)
    require(n is not None and n.user_id == user.id, "NOT_FOUND", "通知不存在", 404)
    member(db, n.space_id, user.id)
    return {**dump(n), "event": dump(db.get(m.Event, n.event_id))}


@router.post("/notifications/{nid}/read")
def read_notification(nid: str, user=Depends(current), db=Depends(get_db)):
    n = db.get(m.Notification, nid)
    require(n is not None and n.user_id == user.id)
    member(db, n.space_id, user.id)
    n.read = True
    db.commit()
    return {"read": True}


@router.post("/devices")
def register_device(
    data: s.DeviceData, authorization: str = Header(), user=Depends(current), db=Depends(get_db)
):
    _, session = authenticate(db, authorization[7:])
    d = one(db, m.Device, token=data.token)
    if d:
        require(d.user_id == user.id or not d.active, "DEVICE_IN_USE", "设备需先退出原账号", 409)
        d.user_id, d.session_id, d.platform, d.provider, d.active = (
            user.id,
            session.id,
            data.platform,
            data.provider,
            True,
        )
    else:
        d = m.Device(user_id=user.id, session_id=session.id, **data.model_dump())
        db.add(d)
    db.commit()
    return {"registered": True}
