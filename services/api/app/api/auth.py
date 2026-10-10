import secrets
from datetime import timedelta

from fastapi import APIRouter, Depends, Header
from pwdlib import PasswordHash
from sqlalchemy import func, select, update

from app.api import schemas as s
from app.db import models as m
from app.db.base import get_db, now
from app.domain.common import digest, dump, one, require

router = APIRouter(prefix="/auth", tags=["auth"])
passwords = PasswordHash.recommended()
DUMMY_HASH = passwords.hash("constant-timing-dummy-password")


def authenticate(db, token):
    session = one(db, m.AuthSession, access_hash=digest(token))
    require(
        session and not session.revoked and session.access_expires > now(),
        "UNAUTHENTICATED",
        "登录已过期，请重新登录",
        401,
    )
    return db.get(m.User, session.user_id), session


def current(authorization: str = Header(default=""), db=Depends(get_db)):
    require(authorization.startswith("Bearer "), "UNAUTHENTICATED", "请先登录", 401)
    return authenticate(db, authorization[7:])[0]


def rotate(session):
    access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
    session.access_hash, session.refresh_hash = digest(access), digest(refresh)
    session.access_expires, session.refresh_expires = (
        now() + timedelta(minutes=15),
        now() + timedelta(days=30),
    )
    return {"access_token": access, "refresh_token": refresh, "expires_in": 900, "token_type": "bearer"}


@router.post("/activate")
def activate(data: s.Activate, db=Depends(get_db)):
    with db.begin():
        token = db.scalar(
            select(m.Activation).where(m.Activation.token_hash == digest(data.token)).with_for_update()
        )
        invitation, space = None, None
        if token is None:
            invitation = one(db, m.Invitation, token_hash=digest(data.token))
            require(
                invitation is not None,
                "ACTIVATION_INVALID",
                "激活码无效，请核对完整激活码；已激活过账号请直接登录",
                400,
            )
            space = db.scalar(select(m.Space).where(m.Space.id == invitation.space_id).with_for_update())
            db.refresh(invitation)
            require(
                not invitation.used_by and not invitation.revoked and invitation.expires_at > now(),
                "INVITE_INVALID",
                "邀请已使用、撤销或过期",
                409,
            )
            from app.domain.common import rows

            require(len(rows(db, m.Member, space_id=space.id)) < 2, "SPACE_FULL", "小屋已满", 409)
        else:
            require(
                not token.used and token.expires_at > now(),
                "ACTIVATION_INVALID",
                "激活码已使用或过期；已激活过账号请直接登录，否则请获取新的激活码",
                400,
            )
        require(not one(db, m.User, username=data.username.lower()), "USERNAME_TAKEN", "账号名已被使用", 409)
        user = m.User(
            username=data.username.lower(),
            password_hash=passwords.hash(data.password),
            nickname=data.nickname,
        )
        db.add(user)
        db.flush()
        if token:
            token.used = True
        else:
            from app.domain.common import emit

            invitation.used_by = user.id
            db.add_all(
                [
                    m.Member(space_id=space.id, user_id=user.id, slot=2),
                    m.Wallet(space_id=space.id, user_id=user.id),
                ]
            )
            emit(db, space, user.id, "member.joined", user.id)
        return {"user_id": user.id}


@router.post("/login")
def login(data: s.Credentials, db=Depends(get_db)):
    # PostgreSQL transaction-scoped advisory lock enforces this bucket across API processes.
    bucket = digest(data.username.lower())
    from sqlalchemy import text

    db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": int(bucket[:15], 16)})
    count = db.scalar(
        select(func.count())
        .select_from(m.LoginAttempt)
        .where(m.LoginAttempt.bucket == bucket, m.LoginAttempt.created_at > now() - timedelta(minutes=15))
    )
    require(count < 10, "RATE_LIMITED", "登录尝试过多，请稍后再试", 429)
    user = one(db, m.User, username=data.username.lower())
    ok = passwords.verify(data.password, user.password_hash if user else DUMMY_HASH)
    if not user or not ok:
        db.add(m.LoginAttempt(bucket=bucket, created_at=now()))
        db.commit()
        require(False, "INVALID_CREDENTIALS", "账号或密码不正确；首次使用请先用激活码注册", 401)
    session = m.AuthSession(user_id=user.id)
    result = rotate(session)
    db.add(session)
    db.commit()
    return result


@router.post("/refresh")
def refresh(data: s.Refresh, db=Depends(get_db)):
    token_hash = digest(data.refresh_token)
    session = db.scalar(
        select(m.AuthSession).where(m.AuthSession.refresh_hash == token_hash).with_for_update()
    )
    if not session:
        used = db.get(m.UsedRefresh, token_hash)
        if used:
            session = db.scalar(
                select(m.AuthSession).where(m.AuthSession.id == used.session_id).with_for_update()
            )
            session.revoked = True
            db.execute(update(m.Device).where(m.Device.session_id == session.id).values(active=False))
            db.commit()
        require(False, "REFRESH_INVALID", "登录凭证无效，请重新登录", 401)
    require(not session.revoked and session.refresh_expires > now(), "REFRESH_INVALID", "登录凭证已过期", 401)
    db.add(m.UsedRefresh(token_hash=token_hash, session_id=session.id))
    result = rotate(session)
    db.commit()
    return result


@router.post("/logout")
def logout(authorization: str = Header(default=""), db=Depends(get_db)):
    require(authorization.startswith("Bearer "), "UNAUTHENTICATED", "请先登录", 401)
    _, session = authenticate(db, authorization[7:])
    session.revoked = True
    db.execute(update(m.Device).where(m.Device.session_id == session.id).values(active=False))
    db.commit()
    return {"logged_out": True}


@router.get("/me")
def me(user=Depends(current), db=Depends(get_db)):
    return {
        "id": user.id,
        "username": user.username,
        "nickname": user.nickname,
        "avatar": user.avatar,
        "preferences": user.preferences,
        "spaces": [
            dump(x)
            for x in db.scalars(
                select(m.Space)
                .join(m.Member)
                .where(m.Member.user_id == user.id)
                .order_by(m.Space.created_at, m.Space.id)
            )
        ],
    }
