from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class Credentials(Input):
    username: str = Field(min_length=3, max_length=80, pattern=r"^[a-zA-Z0-9_.@-]+$")
    password: str = Field(min_length=10, max_length=128)


class Activate(Credentials):
    token: str = Field(min_length=20, max_length=128)
    nickname: str = Field(min_length=1, max_length=40)


class Refresh(Input):
    refresh_token: str = Field(min_length=20, max_length=128)


class CreateSpace(Input):
    name: str = Field(min_length=1, max_length=80)
    timezone: str = Field(min_length=1, max_length=80)


class Join(Input):
    token: str = Field(min_length=20, max_length=128)


class Decision(Input):
    accepted: bool
    reason: str = Field(default="", max_length=200)


class TaskData(Input):
    executor_id: str
    title: str = Field(min_length=1, max_length=120)
    standard: str = Field(min_length=1, max_length=500)
    tag: Literal["study", "cet6", "c", "reading", "exercise"] = "study"
    points: int = Field(ge=0, le=1000, strict=True)
    required: bool = True
    weekdays: list[int] = Field(default=[1, 2, 3, 4, 5, 6, 7], min_length=1, max_length=7)
    starts_on: date
    ends_on: date | None = None
    reminder: str | None = Field(default=None, pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")

    @model_validator(mode="after")
    def dates(self):
        if self.ends_on and self.ends_on < self.starts_on:
            raise ValueError("结束日期不能早于开始日期")
        if len(set(self.weekdays)) != len(self.weekdays) or any(d not in range(1, 8) for d in self.weekdays):
            raise ValueError("星期必须是 1–7 中的不重复值")
        return self


class Checkin(Input):
    desired_state: bool
    expected_version: int = Field(ge=0)
    note: str | None = Field(default=None, max_length=2000)


class CorrectionData(Input):
    desired_state: bool
    expected_version: int = Field(ge=0)
    reason: str = Field(min_length=1, max_length=2000)


class Note(Input):
    note: str = Field(max_length=2000)
    expected_version: int = Field(ge=0)


class Schedule(Input):
    state: Literal["active", "paused", "archived"]
    effective_date: date


class Rest(Input):
    date: date
    rest: bool


class Rule(Input):
    timezone: str
    attendance_points: int = Field(ge=0, le=100, strict=True)
    effective_date: date


class RewardData(Input):
    recipient_id: str
    title: str = Field(min_length=1, max_length=120)
    description: str = Field(min_length=1, max_length=1000)
    price: int = Field(gt=0, le=100000, strict=True)
    stock: int | None = Field(default=None, ge=0, le=10000, strict=True)
    published: bool = False
    icon: Literal["gift", "drink", "movie", "meal", "date"] = "gift"


class RewardUpdate(RewardData):
    expected_version: int = Field(ge=1)


class Redemption(Input):
    confirmed_price: int = Field(gt=0, strict=True)


class OrderCommand(Input):
    action: Literal["fulfill", "confirm", "cancel", "request_cancel", "approve_cancel", "reject_cancel"]
    expected_version: int = Field(ge=1)
    reason: str = Field(default="", max_length=500)


class WishData(Input):
    title: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=1000)


class WishDecision(Input):
    accepted: bool
    reward_id: str | None = None


class GoalData(Input):
    executor_id: str
    title: str = Field(min_length=1, max_length=120)
    standard: str = Field(min_length=1, max_length=500)
    metric: Literal["tasks", "days", "manual"]
    tag: Literal["study", "cet6", "c", "reading", "exercise"] | None = None
    target: int = Field(ge=1, le=10000, strict=True)
    starts_on: date
    ends_on: date
    reward_points: int | None = Field(default=None, ge=1, le=10000, strict=True)
    gift_title: str | None = Field(default=None, min_length=1, max_length=120)

    @model_validator(mode="after")
    def valid(self):
        if (self.reward_points is None) == (self.gift_title is None):
            raise ValueError("奖励须选择积分或实物其中一种")
        if self.ends_on < self.starts_on or (self.metric == "manual" and self.target != 1):
            raise ValueError("目标日期或人工目标阈值无效")
        return self


class Evidence(Input):
    evidence: str = Field(min_length=1, max_length=2000)
    expected_version: int = Field(ge=1)


class ReactionData(Input):
    kind: Literal["hug", "high_five", "paw", "message"]
    message: str = Field(default="", max_length=200)


class Preferences(Input):
    nickname: str = Field(min_length=1, max_length=40)
    avatar: Literal["ginger", "gray"]
    reduce_motion: bool = False
    checkins: bool = True
    interactions: bool = True
    rewards: bool = True
    reminders: bool = True
    gentle_nudges: bool = True
    lock_screen_details: bool = False
    quiet_start: str = Field(default="22:00", pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")
    quiet_end: str = Field(default="08:00", pattern=r"^(?:[01]\d|2[0-3]):[0-5]\d$")


class DeviceData(Input):
    token: str = Field(min_length=16, max_length=4096)
    platform: Literal["ios", "android"]
    provider: Literal["apns", "fcm"]
