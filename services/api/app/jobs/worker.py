import logging
import time
from datetime import datetime, timedelta
from datetime import time as daytime

from sqlalchemy import select

from app.config import settings
from app.db import models as m
from app.db.base import SessionLocal, now
from app.domain.common import config, timezone
from app.jobs.push import PushFailure, provider


def quiet_until(current, preferences):
    start = daytime.fromisoformat(preferences.get("quiet_start", "22:00"))
    end = daytime.fromisoformat(preferences.get("quiet_end", "08:00"))
    t = current.time()
    quiet = (start <= t < end) if start < end else (t >= start or t < end) if start != end else False
    if not quiet:
        return None
    day = current.date() + timedelta(days=1) if start > end and t >= start else current.date()
    return datetime.combine(day, end, current.tzinfo)


def tick(send_provider=provider):
    with SessionLocal.begin() as db:
        item = db.scalar(
            select(m.Outbox)
            .where(
                m.Outbox.status.in_(["pending", "retry", "configuration_missing"]),
                m.Outbox.next_attempt <= now(),
            )
            .order_by(m.Outbox.next_attempt)
            .with_for_update(skip_locked=True)
            .limit(1)
        )
        if item is None:
            return False
        n = db.get(m.Notification, item.notification_id)
        e = db.get(m.Event, n.event_id)
        user = db.get(m.User, n.user_id)
        preferences = user.preferences
        category = (
            "checkins"
            if e.type.startswith("checkin")
            else "interactions"
            if e.type.startswith("interaction")
            else "rewards"
        )
        if not preferences.get(category, True):
            item.status = "suppressed"
            return True
        current = now().astimezone(timezone(config(db, e.space_id).timezone))
        quiet = quiet_until(current, preferences)
        if quiet:
            item.next_attempt = quiet
            return True
        if settings().push_provider == "disabled":
            item.status, item.error_code = "configuration_missing", "push_disabled"
            item.next_attempt = now() + timedelta(minutes=10)
            return True
        devices = list(
            db.scalars(
                select(m.Device)
                .join(m.AuthSession, m.Device.session_id == m.AuthSession.id)
                .where(
                    m.Device.user_id == n.user_id,
                    m.Device.active.is_(True),
                    m.AuthSession.revoked.is_(False),
                    m.AuthSession.refresh_expires > now(),
                )
            )
        )
        if not devices:
            item.status = "no_device"
            return True
        item.attempts += 1
        failures = []
        accepted = 0
        for device in devices:
            if db.get(m.PushReceipt, (item.id, device.id)):
                accepted += 1
                continue
            try:
                send_provider(device.provider).send(
                    device, n, e, preferences.get("lock_screen_details", False)
                )
                db.add(m.PushReceipt(outbox_id=item.id, device_id=device.id))
                accepted += 1
            except PushFailure as failure:
                if failure.invalid:
                    device.active = False
                else:
                    failures.append(failure.code)
            except Exception as failure:
                # Credentials, HTTP request content and device tokens never enter logs.
                failures.append(type(failure).__name__)
        if "configuration_missing" in failures:
            item.status, item.error_code = "configuration_missing", "configuration_missing"
            item.attempts -= 1  # Configuration absence is not a delivery attempt budget.
            item.next_attempt = now() + timedelta(minutes=10)
        elif failures:
            item.status = "failed" if item.attempts >= 8 else "retry"
            item.error_code = failures[0][:100]
            item.next_attempt = now() + timedelta(seconds=min(3600, 2**item.attempts * 15))
        else:
            item.status, item.error_code = ("provider_accepted" if accepted else "invalid_device"), None
        return True


def main():
    settings().validate_runtime()
    while True:
        try:
            busy = tick()
        except Exception as e:
            logging.error("worker_failure kind=%s", type(e).__name__)
            busy = False
        time.sleep(0.1 if busy else 2)


if __name__ == "__main__":
    main()
