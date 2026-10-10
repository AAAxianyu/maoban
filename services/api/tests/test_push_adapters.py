"""Provider HTTP contracts with intercepted transport; no actual device delivery claim."""

import json
from types import SimpleNamespace

import httpx
import pytest
from google.oauth2 import service_account

from app.config import settings
from app.jobs import push


@pytest.fixture
def adapter_context(tmp_path, monkeypatch):
    config = settings()
    key = tmp_path / "test.p8"
    key.write_text("fixture-only")
    credentials = tmp_path / "service.json"
    credentials.write_text(json.dumps({"project_id": "fixture-project"}))
    for name, value in {
        "apns_key_path": str(key),
        "apns_key_id": "fixture-key",
        "apns_team_id": "fixture-team",
        "apns_topic": "com.example.fixture",
        "apns_sandbox": True,
        "fcm_credentials_path": str(credentials),
    }.items():
        monkeypatch.setattr(config, name, value)
    monkeypatch.setattr(push.jwt, "encode", lambda *a, **k: "fixture-jwt")

    def oauth(info, scopes):
        assert scopes == ["https://www.googleapis.com/auth/firebase.messaging"]
        return SimpleNamespace(token="fixture-oauth", refresh=lambda request: None)

    monkeypatch.setattr(service_account.Credentials, "from_service_account_info", oauth)
    requests = []
    reply = {"status": 200, "body": {}}

    def transport(request):
        requests.append(request)
        return httpx.Response(reply["status"], json=reply["body"])

    real_client = httpx.Client
    monkeypatch.setattr(
        push.httpx, "Client", lambda **kwargs: real_client(transport=httpx.MockTransport(transport), **kwargs)
    )
    return requests, reply


@pytest.mark.parametrize("provider", [push.APNs, push.FCM])
@pytest.mark.parametrize("details", [False, True])
def test_both_channels_honor_lock_screen_privacy(adapter_context, provider, details):
    requests, _ = adapter_context
    event = SimpleNamespace(
        space_id="room", entity_id="instance", type="checkin.completed", data={"note": "private study note"}
    )
    provider().send(SimpleNamespace(token="fixture-device"), SimpleNamespace(id="inbox-id"), event, details)
    request = requests[0]
    payload = json.loads(request.content)
    body = (
        payload["aps"]["alert"]["body"]
        if provider is push.APNs
        else payload["message"]["notification"]["body"]
    )
    assert body == ("TA完成了一项约定" if details else "TA有新的打卡动态")
    assert "private study note" not in request.content.decode()
    if provider is push.APNs:
        assert request.url.host == "api.sandbox.push.apple.com"
        assert request.headers["apns-topic"] == "com.example.fixture"
        assert request.headers["apns-collapse-id"] == "inbox-id"
        assert payload["notification_id"] == "inbox-id"
    else:
        assert str(request.url).endswith("/projects/fixture-project/messages:send")
        assert request.headers["authorization"] == "Bearer fixture-oauth"
        assert payload["message"]["android"]["notification"] == {
            "tag": "inbox-id",
            "channel_id": "partner_events",
        }
        assert payload["message"]["data"]["notification_id"] == "inbox-id"


@pytest.mark.parametrize("provider", [push.APNs, push.FCM])
def test_invalid_token_is_distinguished_from_retry(adapter_context, provider):
    _, reply = adapter_context
    reply.update(
        status=410 if provider is push.APNs else 404,
        body={"reason": "Unregistered"}
        if provider is push.APNs
        else {"error": {"details": [{"errorCode": "UNREGISTERED"}]}},
    )
    with pytest.raises(push.PushFailure) as failure:
        provider().send(
            SimpleNamespace(token="fixture-device"),
            SimpleNamespace(id="n"),
            SimpleNamespace(space_id="room", entity_id="i", type="order.fulfill"),
        )
    assert failure.value.invalid


@pytest.mark.parametrize("provider,field", [(push.APNs, "apns_key_path"), (push.FCM, "fcm_credentials_path")])
def test_missing_private_file_is_configuration_failure(adapter_context, monkeypatch, provider, field):
    monkeypatch.setattr(settings(), field, "/nonexistent/fixture-private-file")
    with pytest.raises(push.PushFailure) as failure:
        provider().send(None, None, None)
    assert failure.value.code == "configuration_missing" and not failure.value.invalid
