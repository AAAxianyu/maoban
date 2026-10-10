from datetime import date, datetime

from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, now, uid


class Identity:
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=uid)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class User(Identity, Base):
    __tablename__ = "users"
    username: Mapped[str] = mapped_column(String(80), unique=True)
    password_hash: Mapped[str] = mapped_column(Text)
    nickname: Mapped[str] = mapped_column(String(40))
    avatar: Mapped[str] = mapped_column(String(30), default="ginger")
    preferences: Mapped[dict] = mapped_column(JSON, default=dict)


class AuthSession(Identity, Base):
    __tablename__ = "sessions"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    access_hash: Mapped[str] = mapped_column(String(64), unique=True)
    refresh_hash: Mapped[str] = mapped_column(String(64), unique=True)
    access_expires: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    refresh_expires: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)


class UsedRefresh(Base):
    __tablename__ = "used_refresh"
    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    session_id: Mapped[str] = mapped_column(ForeignKey("sessions.id"))


class Activation(Identity, Base):
    __tablename__ = "activations"
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used: Mapped[bool] = mapped_column(Boolean, default=False)


class LoginAttempt(Identity, Base):
    __tablename__ = "login_attempts"
    bucket: Mapped[str] = mapped_column(String(64), index=True)


class Space(Identity, Base):
    __tablename__ = "spaces"
    name: Mapped[str] = mapped_column(String(80))
    creator_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    seq: Mapped[int] = mapped_column(BigInteger, default=0)


class Member(Base):
    __tablename__ = "memberships"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    slot: Mapped[int] = mapped_column(Integer)
    __table_args__ = (
        UniqueConstraint("space_id", "slot"),
        CheckConstraint("slot IN (1, 2)"),
    )


class SpaceConfig(Identity, Base):
    __tablename__ = "space_rule_versions"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    proposer_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    timezone: Mapped[str] = mapped_column(String(80))
    attendance_points: Mapped[int] = mapped_column(Integer, default=5)
    effective_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (CheckConstraint("attendance_points >= 0"),)


class Invitation(Identity, Base):
    __tablename__ = "invitations"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"))
    creator_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    revoked: Mapped[bool] = mapped_column(Boolean, default=False)


class Wallet(Base):
    __tablename__ = "wallets"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    balance: Mapped[int] = mapped_column(Integer, default=0)


class Entitlement(Identity, Base):
    __tablename__ = "reward_entitlements"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    source: Mapped[str] = mapped_column(String(160))
    net: Mapped[int] = mapped_column(Integer, default=0)
    revision: Mapped[int] = mapped_column(Integer, default=0)
    __table_args__ = (UniqueConstraint("space_id", "user_id", "source"),)


class Ledger(Identity, Base):
    __tablename__ = "ledger_entries"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    actor_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    entitlement_id: Mapped[str] = mapped_column(ForeignKey("reward_entitlements.id"))
    source: Mapped[str] = mapped_column(String(160))
    revision: Mapped[int] = mapped_column(Integer)
    delta: Mapped[int] = mapped_column(Integer)
    balance_after: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(200))
    __table_args__ = (
        UniqueConstraint("entitlement_id", "revision"),
        CheckConstraint("delta <> 0"),
    )


class Task(Identity, Base):
    __tablename__ = "task_templates"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    executor_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    proposer_id: Mapped[str] = mapped_column(ForeignKey("users.id"))


class TaskVersion(Identity, Base):
    __tablename__ = "task_versions"
    task_id: Mapped[str] = mapped_column(ForeignKey("task_templates.id"), index=True)
    version: Mapped[int] = mapped_column(Integer)
    proposer_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    approver_id: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(120))
    standard: Mapped[str] = mapped_column(String(500))
    tag: Mapped[str] = mapped_column(String(30), default="study")
    points: Mapped[int] = mapped_column(Integer)
    required: Mapped[bool] = mapped_column(Boolean)
    weekdays: Mapped[list] = mapped_column(JSON)
    starts_on: Mapped[date] = mapped_column(Date)
    ends_on: Mapped[date | None] = mapped_column(Date)
    reminder: Mapped[str | None] = mapped_column(String(5))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rejection_reason: Mapped[str | None] = mapped_column(String(200))
    __table_args__ = (
        UniqueConstraint("task_id", "version"),
        CheckConstraint("points >= 0"),
    )


class ScheduleChange(Identity, Base):
    __tablename__ = "task_schedule_changes"
    task_id: Mapped[str] = mapped_column(ForeignKey("task_templates.id"), index=True)
    effective_date: Mapped[date] = mapped_column(Date)
    state: Mapped[str] = mapped_column(String(20))


class RestDate(Base):
    __tablename__ = "member_rest_dates"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    date: Mapped[date] = mapped_column(Date, primary_key=True)


class DailyPlan(Identity, Base):
    __tablename__ = "daily_plans"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    date: Mapped[date] = mapped_column(Date)
    timezone: Mapped[str] = mapped_column(String(80))
    attendance_points: Mapped[int] = mapped_column(Integer)
    rest: Mapped[bool] = mapped_column(Boolean)
    __table_args__ = (UniqueConstraint("space_id", "user_id", "date"),)


class Instance(Identity, Base):
    __tablename__ = "task_instances"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    task_id: Mapped[str] = mapped_column(ForeignKey("task_templates.id"))
    task_version_id: Mapped[str] = mapped_column(ForeignKey("task_versions.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    date: Mapped[date] = mapped_column(Date)
    timezone: Mapped[str] = mapped_column(String(80))
    title: Mapped[str] = mapped_column(String(120))
    standard: Mapped[str] = mapped_column(String(500))
    tag: Mapped[str] = mapped_column(String(30))
    points: Mapped[int] = mapped_column(Integer)
    required: Mapped[bool] = mapped_column(Boolean)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    version: Mapped[int] = mapped_column(Integer, default=0)
    note: Mapped[str] = mapped_column(String(2000), default="")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    __table_args__ = (UniqueConstraint("task_id", "user_id", "date"),)


class Correction(Identity, Base):
    __tablename__ = "corrections"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"))
    instance_id: Mapped[str] = mapped_column(ForeignKey("task_instances.id"))
    requester_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    desired_state: Mapped[bool] = mapped_column(Boolean)
    expected_version: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(2000))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Reward(Identity, Base):
    __tablename__ = "rewards"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    provider_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    recipient_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(1000))
    price: Mapped[int] = mapped_column(Integer)
    stock: Mapped[int | None] = mapped_column(Integer)
    published: Mapped[bool] = mapped_column(Boolean, default=False)
    icon: Mapped[str] = mapped_column(String(30), default="gift")
    version: Mapped[int] = mapped_column(Integer, default=1)
    __table_args__ = (
        CheckConstraint("price > 0"),
        CheckConstraint("stock IS NULL OR stock >= 0"),
    )


class Wish(Identity, Base):
    __tablename__ = "wishes"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"))
    requester_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(1000))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    reward_id: Mapped[str | None] = mapped_column(ForeignKey("rewards.id"))


class Milestone(Identity, Base):
    __tablename__ = "milestones"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    proposer_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    executor_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    approver_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(120))
    standard: Mapped[str] = mapped_column(String(500))
    metric: Mapped[str] = mapped_column(String(20))
    tag: Mapped[str | None] = mapped_column(String(30))
    target: Mapped[int] = mapped_column(Integer)
    starts_on: Mapped[date] = mapped_column(Date)
    ends_on: Mapped[date] = mapped_column(Date)
    reward_points: Mapped[int | None] = mapped_column(Integer)
    gift_title: Mapped[str | None] = mapped_column(String(120))
    status: Mapped[str] = mapped_column(String(20), default="pending")
    evidence: Mapped[str] = mapped_column(String(2000), default="")
    manual_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    version: Mapped[int] = mapped_column(Integer, default=1)


class Order(Identity, Base):
    __tablename__ = "redemptions"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    reward_id: Mapped[str | None] = mapped_column(ForeignKey("rewards.id"))
    milestone_id: Mapped[str | None] = mapped_column(ForeignKey("milestones.id"), unique=True)
    provider_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    recipient_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    title: Mapped[str] = mapped_column(String(120))
    description: Mapped[str] = mapped_column(String(1000))
    price: Mapped[int] = mapped_column(Integer)
    finite_stock: Mapped[bool] = mapped_column(Boolean, default=False)
    status: Mapped[str] = mapped_column(String(30), default="pending")
    version: Mapped[int] = mapped_column(Integer, default=1)
    cancel_requested_by: Mapped[str | None] = mapped_column(ForeignKey("users.id"))
    cancel_reason: Mapped[str | None] = mapped_column(String(500))
    corrected: Mapped[bool] = mapped_column(Boolean, default=False)
    ever_fulfilled: Mapped[bool] = mapped_column(Boolean, default=False)


class MilestoneVersion(Identity, Base):
    __tablename__ = "milestone_versions"
    milestone_id: Mapped[str] = mapped_column(ForeignKey("milestones.id"), index=True)
    proposer_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    approver_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    version: Mapped[int] = mapped_column(Integer)
    data: Mapped[dict] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    accepted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    rejection_reason: Mapped[str | None] = mapped_column(String(200))
    __table_args__ = (UniqueConstraint("milestone_id", "version"),)


class Achievement(Base):
    __tablename__ = "user_achievements"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    code: Mapped[str] = mapped_column(String(30), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Contribution(Base):
    __tablename__ = "room_contributions"
    instance_id: Mapped[str] = mapped_column(ForeignKey("task_instances.id"), primary_key=True)
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Unlock(Base):
    __tablename__ = "room_unlocks"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), primary_key=True)
    decoration: Mapped[str] = mapped_column(String(30), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Event(Identity, Base):
    __tablename__ = "events"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"), index=True)
    seq: Mapped[int] = mapped_column(BigInteger)
    actor_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    type: Mapped[str] = mapped_column(String(50))
    entity_id: Mapped[str] = mapped_column(String(36))
    entity_version: Mapped[int] = mapped_column(Integer, default=1)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    __table_args__ = (UniqueConstraint("space_id", "seq"),)


class Reaction(Identity, Base):
    __tablename__ = "reactions"
    event_id: Mapped[str] = mapped_column(ForeignKey("events.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    kind: Mapped[str] = mapped_column(String(20))
    message: Mapped[str] = mapped_column(String(200), default="")
    __table_args__ = (UniqueConstraint("event_id", "user_id", "kind"),)


class Notification(Identity, Base):
    __tablename__ = "notifications"
    space_id: Mapped[str] = mapped_column(ForeignKey("spaces.id"))
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), index=True)
    event_id: Mapped[str] = mapped_column(ForeignKey("events.id"))
    read: Mapped[bool] = mapped_column(Boolean, default=False)
    __table_args__ = (UniqueConstraint("event_id", "user_id"),)


class Device(Identity, Base):
    __tablename__ = "device_registrations"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"))
    session_id: Mapped[str] = mapped_column(ForeignKey("sessions.id"))
    token: Mapped[str] = mapped_column(Text, unique=True)
    platform: Mapped[str] = mapped_column(String(20))
    provider: Mapped[str] = mapped_column(String(20))
    active: Mapped[bool] = mapped_column(Boolean, default=True)


class Outbox(Identity, Base):
    __tablename__ = "outbox"
    notification_id: Mapped[str] = mapped_column(ForeignKey("notifications.id"), unique=True)
    status: Mapped[str] = mapped_column(String(30), default="pending")
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    next_attempt: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    error_code: Mapped[str | None] = mapped_column(String(100))


class PushReceipt(Base):
    __tablename__ = "push_receipts"
    outbox_id: Mapped[str] = mapped_column(ForeignKey("outbox.id"), primary_key=True)
    device_id: Mapped[str] = mapped_column(ForeignKey("device_registrations.id"), primary_key=True)
    accepted_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Idempotency(Base):
    __tablename__ = "idempotency_records"
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id"), primary_key=True)
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    payload_hash: Mapped[str] = mapped_column(String(64))
    result: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
