from datetime import datetime, time, timedelta

from sqlalchemy import select

from app.db import models as m
from app.db.base import now
from app.domain.common import (
    award,
    config,
    dump,
    emit,
    entity,
    local_today,
    member,
    one,
    partner,
    require,
    rows,
    timezone,
    wallet_view,
)


def propose(db, space, actor, data, task_id=None):
    member(db, space.id, data["executor_id"])
    today = local_today(db, space.id)
    require(data["starts_on"] >= today, "INVALID_DATE", "新约定不能回溯开始", 400)
    task = (
        entity(db, m.Task, space.id, task_id)
        if task_id
        else m.Task(space_id=space.id, executor_id=data["executor_id"], proposer_id=actor)
    )
    if task_id:
        require(actor in (task.proposer_id, task.executor_id))
        require(data["executor_id"] == task.executor_id, "INVALID_EXECUTOR", "新版本不能更换执行人", 400)
    else:
        db.add(task)
        db.flush()
    old = rows(db, m.TaskVersion, task_id=task.id)
    approver = task.executor_id if actor != task.executor_id else partner(db, space.id, actor)
    self_zero = actor == task.executor_id and data["points"] == 0
    v = m.TaskVersion(
        task_id=task.id,
        version=len(old) + 1,
        proposer_id=actor,
        approver_id=approver,
        **{k: v for k, v in data.items() if k != "executor_id"},
        status="accepted" if self_zero else "pending",
        accepted_at=now() if self_zero else None,
    )
    db.add(v)
    db.flush()
    emit(db, space, actor, "task.proposed", task.id, v.version)
    return {"task": dump(task), "proposal": dump(v)}


def decide(db, space, actor, vid, accepted, reason=""):
    v = db.get(m.TaskVersion, vid)
    require(v is not None, "NOT_FOUND", "约定版本不存在", 404)
    task = entity(db, m.Task, space.id, v.task_id)
    approver = (
        task.executor_id if v.proposer_id != task.executor_id else partner(db, space.id, task.executor_id)
    )
    require(actor == approver and actor != v.proposer_id)
    require(v.status == "pending", "INVALID_STATE", "该提议已处理", 409)
    # Concurrent pending versions must not replace a newer already accepted version.
    newer = db.scalar(
        select(m.TaskVersion.id).where(
            m.TaskVersion.task_id == task.id,
            m.TaskVersion.version > v.version,
            m.TaskVersion.status == "accepted",
        )
    )
    require(not newer, "VERSION_CONFLICT", "已有更新的有效版本", 409)
    v.status = "accepted" if accepted else "rejected"
    v.approver_id = actor
    v.accepted_at = now() if accepted else None
    v.rejection_reason = reason if not accepted else None
    emit(db, space, actor, "task." + v.status, task.id, v.version)
    return dump(v)


def ensure_plan(db, space, user_id, day):
    plan = one(db, m.DailyPlan, space_id=space.id, user_id=user_id, date=day)
    if plan is None:
        c = config(db, space.id, day)
        plan = m.DailyPlan(
            space_id=space.id,
            user_id=user_id,
            date=day,
            timezone=c.timezone,
            attendance_points=c.attendance_points,
            rest=db.get(m.RestDate, (space.id, user_id, day)) is not None,
        )
        db.add(plan)
        db.flush()
    if plan.rest:
        return plan
    midnight = datetime.combine(day, time.min, timezone(plan.timezone))
    end = midnight + timedelta(days=1)
    for task in rows(db, m.Task, space_id=space.id, executor_id=user_id):
        if one(db, m.Instance, task_id=task.id, user_id=user_id, date=day):
            continue
        changes = [c for c in rows(db, m.ScheduleChange, task_id=task.id) if c.effective_date <= day]
        if changes and max(changes, key=lambda c: (c.effective_date, c.created_at)).state != "active":
            continue
        candidates = [
            v
            for v in rows(db, m.TaskVersion, task_id=task.id, status="accepted")
            if v.starts_on <= day and v.accepted_at < end
        ]
        if not candidates:
            continue
        # For the daily required set prefer the version accepted at midnight; new versions
        # during the day become optional only when there was no prior active version.
        at_midnight = [v for v in candidates if v.accepted_at <= midnight]
        v = max(at_midnight or candidates, key=lambda v: v.version)
        if v.ends_on and v.ends_on < day or day.isoweekday() not in v.weekdays:
            continue
        db.add(
            m.Instance(
                space_id=space.id,
                task_id=task.id,
                task_version_id=v.id,
                user_id=user_id,
                date=day,
                timezone=plan.timezone,
                title=v.title,
                standard=v.standard,
                tag=v.tag,
                points=v.points,
                required=v.required and v.accepted_at <= midnight,
                completed=False,
                version=0,
                note="",
            )
        )
    db.flush()
    return plan


def daily(db, space, day):
    today = local_today(db, space.id)
    require(today - timedelta(days=366) <= day <= today, "INVALID_DATE", "只能查询过去一年到今日", 400)
    for who in rows(db, m.Member, space_id=space.id):
        ensure_plan(db, space, who.user_id, day)
    return {
        "date": day.isoformat(),
        "plans": [dump(p) for p in rows(db, m.DailyPlan, space_id=space.id, date=day)],
        "instances": [dump(i) for i in rows(db, m.Instance, space_id=space.id, date=day)],
        "snapshot_seq": space.seq,
    }


def recalculate(db, space, actor, instance):
    award(
        db,
        space.id,
        instance.user_id,
        "task:" + instance.id,
        instance.points if instance.completed else 0,
        actor,
        "任务完成奖励／更正",
    )
    plan = one(db, m.DailyPlan, space_id=space.id, user_id=instance.user_id, date=instance.date)
    mandatory = rows(
        db, m.Instance, space_id=space.id, user_id=instance.user_id, date=instance.date, required=True
    )
    all_done = bool(mandatory) and all(i.completed for i in mandatory)
    award(
        db,
        space.id,
        instance.user_id,
        f"attendance:{instance.date}",
        plan.attendance_points if all_done else 0,
        actor,
        "每日全勤奖励／更正",
    )
    if instance.completed and db.get(m.Contribution, instance.id) is None:
        db.add(m.Contribution(instance_id=instance.id, space_id=space.id))
    db.flush()
    from app.domain.growth import refresh_growth

    refresh_growth(db, space, actor)


def apply_state(db, space, actor, i, desired, expected, note=None):
    if i.completed == desired:
        return {"instance": dump(i), "wallet": wallet_view(db, space.id, i.user_id)}
    require(i.version == expected, "VERSION_CONFLICT", "记录已更新，请刷新后重试", 409, instance=dump(i))
    i.completed, i.version = desired, i.version + 1
    i.completed_at = now() if desired else None
    if note is not None:
        i.note = note
    db.flush()
    recalculate(db, space, actor, i)
    emit(
        db,
        space,
        actor,
        "checkin.completed" if desired else "checkin.reversed",
        i.id,
        i.version,
        {"date": i.date.isoformat()},
    )
    return {"instance": dump(i), "wallet": wallet_view(db, space.id, i.user_id)}


def checkin(db, space, actor, iid, desired, expected, note=None):
    i = entity(db, m.Instance, space.id, iid)
    require(i.user_id == actor)
    require(
        i.date == local_today(db, space.id),
        "DATE_REQUIRES_REVIEW",
        "跨日记录需提交补记或更正申请",
        409,
        instance=dump(i),
    )
    return apply_state(db, space, actor, i, desired, expected, note)


def correction(db, space, actor, iid, data):
    i = entity(db, m.Instance, space.id, iid)
    require(i.user_id == actor)
    today = local_today(db, space.id)
    require(i.date < today, "INVALID_DATE", "当日请直接撤销或完成", 400)
    if data["desired_state"] and not i.completed:
        current = now().astimezone(timezone(config(db, space.id).timezone))
        require(
            i.date == today - timedelta(days=1) and current.time() < time(12),
            "MAKEUP_WINDOW_CLOSED",
            "已超过次日 12:00 补记窗口，可保存历史说明",
            409,
        )
    require(i.version == data["expected_version"], "VERSION_CONFLICT", "记录已更新", 409)
    pending = one(db, m.Correction, instance_id=i.id, status="pending")
    if pending:
        require(pending.desired_state == data["desired_state"], "CORRECTION_PENDING", "已有待处理的更正", 409)
        return dump(pending)
    r = m.Correction(space_id=space.id, instance_id=i.id, requester_id=actor, **data)
    db.add(r)
    db.flush()
    emit(db, space, actor, "correction.requested", r.id)
    return dump(r)


def decide_correction(db, space, actor, cid, accepted):
    c = entity(db, m.Correction, space.id, cid)
    require(actor == partner(db, space.id, c.requester_id))
    require(c.status == "pending", "INVALID_STATE", "该更正已处理", 409)
    i = entity(db, m.Instance, space.id, c.instance_id)
    if accepted:
        apply_state(db, space, actor, i, c.desired_state, c.expected_version)
    c.status, c.decided_at = "accepted" if accepted else "rejected", now()
    emit(db, space, actor, "correction." + c.status, c.id)
    return dump(c)
