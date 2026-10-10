import json
import time
from pathlib import Path

import httpx
import jwt

from app.config import settings


class PushFailure(Exception):
    def __init__(self, code, invalid=False):
        self.code, self.invalid = code, invalid


def alert_body(event_type, details):
    if not details:
        return "TA有新的打卡动态"
    return {
        "checkin.completed": "TA完成了一项约定",
        "checkin.reversed": "TA更正了一次打卡",
        "interaction.reaction": "TA送来了一份鼓励",
        "interaction.nudge": "TA轻轻提醒了一下",
        "task.proposed": "TA提出了新的约定",
        "task.accepted": "TA接受了约定",
        "order.redeemed": "TA兑换了一份奖品",
        "order.fulfill": "TA兑现了一份奖品",
        "order.confirm": "TA确认收到奖品",
        "order.cancel": "TA取消了兑换",
        "milestone.rewarded": "TA获得了阶段奖励",
        "milestone.gift": "阶段赠品已解锁",
        "milestone.accepted": "TA确认了阶段目标",
    }.get(event_type, "TA更新了小屋记录")


class APNs:
    def send(self, device, notification, event, details=False):
        c = settings()
        if not all((c.apns_key_path, c.apns_key_id, c.apns_team_id, c.apns_topic)):
            raise PushFailure("configuration_missing")
        try:
            token = jwt.encode(
                {"iss": c.apns_team_id, "iat": int(time.time())},
                Path(c.apns_key_path).read_text(),
                algorithm="ES256",
                headers={"kid": c.apns_key_id},
            )
        except (OSError, ValueError, jwt.InvalidKeyError):
            raise PushFailure("configuration_missing") from None
        host = "https://api.sandbox.push.apple.com" if c.apns_sandbox else "https://api.push.apple.com"
        payload = {
            "aps": {"alert": {"title": "喵伴", "body": alert_body(event.type, details)}, "sound": "default"},
            "space_id": event.space_id,
            "entity_id": event.entity_id,
            "notification_id": notification.id,
        }
        with httpx.Client(http2=True, timeout=10) as client:
            response = client.post(
                host + "/3/device/" + device.token,
                json=payload,
                headers={
                    "authorization": "bearer " + token,
                    "apns-topic": c.apns_topic,
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                    "apns-collapse-id": notification.id,
                },
            )
        if response.status_code != 200:
            reason = response.json().get("reason", "provider_error")
            raise PushFailure(reason, reason in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic"))


class FCM:
    def send(self, device, notification, event, details=False):
        # Explicit opt-in adapter for Android devices with verified Google services.
        # A vendor/aggregate channel remains an external decision for GMS-free phones.
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account

        c = settings()
        if not c.fcm_credentials_path:
            raise PushFailure("configuration_missing")
        try:
            info = json.loads(Path(c.fcm_credentials_path).read_text())
            credentials = service_account.Credentials.from_service_account_info(
                info, scopes=["https://www.googleapis.com/auth/firebase.messaging"]
            )
        except (OSError, ValueError):
            raise PushFailure("configuration_missing") from None
        credentials.refresh(Request())
        payload = {
            "message": {
                "token": device.token,
                "notification": {"title": "喵伴", "body": alert_body(event.type, details)},
                "data": {
                    "space_id": event.space_id,
                    "entity_id": event.entity_id,
                    "notification_id": notification.id,
                },
                "android": {"notification": {"tag": notification.id, "channel_id": "partner_events"}},
            }
        }
        with httpx.Client(timeout=10) as client:
            response = client.post(
                f"https://fcm.googleapis.com/v1/projects/{info['project_id']}/messages:send",
                headers={"Authorization": "Bearer " + credentials.token},
                json=payload,
            )
        if response.status_code != 200:
            codes = [d.get("errorCode") for d in response.json().get("error", {}).get("details", [])]
            raise PushFailure(
                "UNREGISTERED" if "UNREGISTERED" in codes else "fcm_error", "UNREGISTERED" in codes
            )


def provider(name):
    return {"apns": APNs, "fcm": FCM}[name]()
