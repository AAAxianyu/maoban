from fastapi import APIRouter, Depends, Header, Query

from app.api import schemas as s
from app.api.auth import current
from app.api.routes import run
from app.db import models as m
from app.db.base import get_db, now
from app.domain import growth
from app.domain.common import dump, emit, entity, local_today, member, page, require, rows

router = APIRouter(tags=["milestone versions"])


@router.get("/spaces/{sid}/milestones/{gid}/versions")
def versions(
    sid: str,
    gid: str,
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=100, ge=1, le=200),
    user=Depends(current),
    db=Depends(get_db),
):
    member(db, sid, user.id)
    entity(db, m.Milestone, sid, gid)
    return [dump(v) for v in page(db, m.MilestoneVersion, offset, limit, milestone_id=gid)]


@router.post("/spaces/{sid}/milestones/{gid}/versions")
def propose(
    sid: str,
    gid: str,
    data: s.GoalData,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        g = entity(db, m.Milestone, sid, gid)
        require(g.status == "accepted", "INVALID_STATE", "当前目标须先接受", 409)
        require(g.executor_id == data.executor_id, "INVALID_EXECUTOR", "目标不能更换执行人", 400)
        require(
            (g.reward_points is None) == (data.reward_points is None),
            "REWARD_TYPE_LOCKED",
            "同一目标不能改换奖励类型",
            409,
        )
        require(data.starts_on >= local_today(db, sid), "INVALID_DATE", "新版本不能回溯开始", 400)
        prior = rows(db, m.MilestoneVersion, milestone_id=gid)
        if not prior:
            baseline = {k: dump(g)[k] for k in s.GoalData.model_fields}
            db.add(
                m.MilestoneVersion(
                    milestone_id=gid,
                    proposer_id=g.proposer_id,
                    approver_id=g.executor_id if g.proposer_id != g.executor_id else g.approver_id,
                    version=1,
                    data=baseline,
                    status="accepted",
                )
            )
        v = m.MilestoneVersion(
            milestone_id=gid,
            proposer_id=user.id,
            approver_id=g.executor_id if user.id != g.executor_id else g.approver_id,
            version=max([x.version for x in prior] + [1]) + 1,
            data=data.model_dump(mode="json"),
        )
        db.add(v)
        db.flush()
        emit(db, space, user.id, "milestone.version_proposed", gid, g.version)
        return dump(v)

    return run(db, sid, user, key, "milestone.version:" + gid, data, action)


@router.post("/spaces/{sid}/milestone-versions/{vid}/decision")
def decide(
    sid: str,
    vid: str,
    data: s.Decision,
    user=Depends(current),
    db=Depends(get_db),
    key: str = Header(alias="Idempotency-Key"),
):
    def action(space):
        v = db.get(m.MilestoneVersion, vid)
        require(v is not None, "NOT_FOUND", "目标版本不存在", 404)
        g = entity(db, m.Milestone, sid, v.milestone_id)
        require(v.approver_id == user.id and v.proposer_id != user.id)
        require(v.status == "pending", "INVALID_STATE", "版本已处理", 409)
        newer = [
            x
            for x in rows(db, m.MilestoneVersion, milestone_id=g.id)
            if x.version > v.version and x.status == "accepted"
        ]
        require(not newer, "VERSION_CONFLICT", "已有更新的有效版本", 409)
        v.status = "accepted" if data.accepted else "rejected"
        v.rejection_reason = None if data.accepted else data.reason
        if data.accepted:
            payload = s.GoalData(**v.data).model_dump()
            g.manual_confirmed = False
            for k, value in payload.items():
                setattr(g, k, value)
            g.status, g.version, v.accepted_at = "accepted", g.version + 1, now()
            growth.recompute_goal(db, space, user.id, g)
        emit(db, space, user.id, "milestone.version_" + v.status, g.id, g.version)
        return dump(v)

    return run(db, sid, user, key, "milestone.version_decide:" + vid, data, action)
