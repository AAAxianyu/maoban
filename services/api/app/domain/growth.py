from app.db import models as m
from app.domain.common import award, dump, emit, local_today, one, partner, require, rows

DECORATIONS = {"lamp": 10, "cat_bed": 30, "plant": 60, "bookshelf": 100}
ACHIEVEMENTS = {
    "first": "第一次有效打卡",
    "seven_days": "累计学习 7 天",
    "c_ten": "完成 10 次 C 练习",
    "together": "两人同日全勤",
    "thirty": "累计完成 30 个任务",
}


def milestone_progress(db, goal):
    done = [
        i
        for i in rows(db, m.Instance, space_id=goal.space_id, user_id=goal.executor_id, completed=True)
        if goal.starts_on <= i.date <= goal.ends_on and (not goal.tag or i.tag == goal.tag)
    ]
    if goal.metric == "manual":
        return 1 if goal.manual_confirmed else 0
    if goal.metric == "days":
        return len({i.date for i in done})
    return len(done)


def recompute_goal(db, space, actor, goal):
    met = goal.status == "accepted" and milestone_progress(db, goal) >= goal.target
    if goal.reward_points is not None:
        delta = award(
            db,
            space.id,
            goal.executor_id,
            "milestone:" + goal.id,
            goal.reward_points if met else 0,
            actor,
            "阶段奖励／更正：" + goal.title,
        )
        if delta:
            emit(
                db,
                space,
                actor,
                "milestone.rewarded" if met else "milestone.corrected",
                goal.id,
                goal.version,
            )
    else:
        o = one(db, m.Order, milestone_id=goal.id)
        if met and not o:
            o = m.Order(
                space_id=space.id,
                milestone_id=goal.id,
                provider_id=goal.approver_id,
                recipient_id=goal.executor_id,
                title=goal.gift_title,
                description=goal.standard,
                price=0,
                status="pending",
                finite_stock=False,
            )
            db.add(o)
            db.flush()
            emit(db, space, actor, "milestone.gift", o.id)
        elif o and not met:
            if o.status == "pending":
                o.status, o.version = "cancelled", o.version + 1
            if not o.corrected:
                o.corrected = True
                emit(db, space, actor, "milestone.corrected", o.id, o.version)
        elif o and met and o.status == "cancelled" and not o.ever_fulfilled:
            o.status, o.corrected, o.version = "pending", False, o.version + 1
            emit(db, space, actor, "milestone.restored", o.id, o.version)
        elif o and met and o.corrected:
            o.corrected = False


def refresh_growth(db, space, actor):
    for g in rows(db, m.Milestone, space_id=space.id, status="accepted"):
        recompute_goal(db, space, actor, g)
    count = len(rows(db, m.Contribution, space_id=space.id))
    for decoration, threshold in DECORATIONS.items():
        if count >= threshold and db.get(m.Unlock, (space.id, decoration)) is None:
            db.add(m.Unlock(space_id=space.id, decoration=decoration))
            emit(db, space, actor, "room.unlocked", space.id, data={"decoration": decoration})
    members = rows(db, m.Member, space_id=space.id)
    full_days = []
    for who in members:
        items = rows(db, m.Instance, space_id=space.id, user_id=who.user_id)
        dates = {i.date for i in items if i.required}
        full_days.append({d for d in dates if all(i.completed for i in items if i.date == d and i.required)})
    together = len(full_days) == 2 and bool(full_days[0] & full_days[1])
    for who in members:
        done = rows(db, m.Instance, space_id=space.id, user_id=who.user_id, completed=True)
        conditions = {
            "first": bool(done),
            "seven_days": len({i.date for i in done}) >= 7,
            "c_ten": sum(i.tag == "c" for i in done) >= 10,
            "together": together,
            "thirty": len(done) >= 30,
        }
        for code, unlocked in conditions.items():
            if unlocked and db.get(m.Achievement, (space.id, who.user_id, code)) is None:
                db.add(m.Achievement(space_id=space.id, user_id=who.user_id, code=code))
                emit(db, space, actor, "achievement.unlocked", who.user_id, data={"code": code})
    db.flush()


def propose_goal(db, space, actor, data):
    executor = data["executor_id"]
    require(executor == actor or executor == partner(db, space.id, actor))
    approver = executor if actor != executor else partner(db, space.id, actor)
    require(approver is not None, "PARTNER_REQUIRED", "绑定另一位成员后才能约定奖励", 409)
    # Gifts are promises made by the person providing them. Self proposals are approved
    # by the partner; partner proposals are themselves a provider promise.
    provider = partner(db, space.id, executor)
    require(data["starts_on"] >= local_today(db, space.id), "INVALID_DATE", "目标不能回溯开始", 400)
    g = m.Milestone(space_id=space.id, proposer_id=actor, approver_id=provider, **data)
    db.add(g)
    db.flush()
    db.add(
        m.MilestoneVersion(
            milestone_id=g.id,
            proposer_id=actor,
            approver_id=approver,
            version=1,
            data={k: dump(g)[k] for k in data},
        )
    )
    emit(db, space, actor, "milestone.proposed", g.id)
    return dump(g)


def growth_view(db, sid):
    users = rows(db, m.Member, space_id=sid)
    stats = {}
    for who in users:
        done = rows(db, m.Instance, space_id=sid, user_id=who.user_id, completed=True)
        stats[who.user_id] = {
            "effective_completions": len(done),
            "effective_days": len({i.date for i in done}),
            "c_completions": sum(i.tag == "c" for i in done),
        }
    xp = len(rows(db, m.Contribution, space_id=sid))
    return {
        "stats": stats,
        "permanent_xp": xp,
        "level": 1 + sum(xp >= t for t in DECORATIONS.values()),
        "decorations": [dump(x) for x in rows(db, m.Unlock, space_id=sid)],
        "achievements": [dump(x) for x in rows(db, m.Achievement, space_id=sid)],
        "achievement_definitions": ACHIEVEMENTS,
        "calendar": [
            {"user_id": i.user_id, "date": i.date.isoformat(), "instance_id": i.id}
            for i in rows(db, m.Instance, space_id=sid, completed=True)
        ],
    }
