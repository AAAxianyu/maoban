from datetime import timedelta

import pytest

from app.api import auth
from app.db import base
from app.db import models as m
from app.domain.common import digest


@pytest.mark.parametrize(
    ("field", "value", "hint"),
    [
        ("username", "中文账号", "中文请填在昵称中"),
        ("username", "account name", "3–80"),
        ("username", "a" * 81, "3–80"),
        ("password", "  short123  ", "10–128"),
        ("password", "p" * 129, "10–128"),
        ("token", "incomplete-code", "完整"),
        ("nickname", "   ", "1–40"),
    ],
)
def test_activation_reports_the_field_without_echoing_private_input(client, field, value, hint):
    data = {
        "username": "fixture-user",
        "password": "fixture-private-password-123",
        "token": "fixture-private-activation-token-123",
        "nickname": "小猫",
    }
    data[field] = value
    response = client.post("/api/v1/auth/activate", json=data)
    assert response.status_code == 422
    body = response.json()
    assert body["fields"] == [f"body.{field}"]
    assert hint in body["field_errors"][field]
    assert body["message"] == body["field_errors"][field]
    for supplied in data.values():
        if supplied.strip():
            assert supplied not in response.text
    assert response.headers["x-request-id"] == body["request_id"]


def test_login_validation_and_unknown_fields_are_sanitized(client):
    response = client.post("/api/v1/auth/login", json={"username": "中文账号"})
    assert response.status_code == 422
    assert response.json()["field_errors"]["password"] == "请填写密码"
    private_key = "private-input-in-field-name"
    response = client.post(
        "/api/v1/auth/login",
        json={"username": "fixture-user", "password": "fixture-password-123", private_key: "private-value"},
    )
    assert response.status_code == 422
    assert private_key not in response.text
    assert "private-value" not in response.text


def test_activation_trims_pasted_fields_and_accepts_chinese_nickname(client):
    token = "fixture-activation-token-12345"
    with base.SessionLocal.begin() as db:
        db.add(m.Activation(token_hash=digest(token), expires_at=auth.now() + timedelta(days=1)))
    response = client.post(
        "/api/v1/auth/activate",
        json={
            "username": "  Fixture.Cat  ",
            "password": "  fixture-password-123  ",
            "token": f"\n{token}\n",
            "nickname": "  小猫  ",
        },
    )
    assert response.status_code == 200
    login = client.post(
        "/api/v1/auth/login", json={"username": "fixture.cat", "password": "fixture-password-123"}
    )
    assert login.status_code == 200
    profile = client.get(
        "/api/v1/auth/me", headers={"Authorization": "Bearer " + login.json()["access_token"]}
    )
    assert profile.json()["nickname"] == "小猫"
    known = client.post(
        "/api/v1/auth/login", json={"username": "fixture.cat", "password": "wrong-password-123"}
    )
    unknown = client.post(
        "/api/v1/auth/login", json={"username": "unknown.cat", "password": "wrong-password-123"}
    )
    assert known.status_code == unknown.status_code == 401
    assert known.json()["message"] == unknown.json()["message"]
    assert "激活码" in unknown.json()["message"]


def test_used_activation_code_explains_login_recovery(client):
    token = "fixture-already-used-activation-token"
    with base.SessionLocal.begin() as db:
        db.add(m.Activation(token_hash=digest(token), used=True, expires_at=auth.now() + timedelta(days=1)))
    response = client.post(
        "/api/v1/auth/activate",
        json={
            "username": "fixture-cat",
            "password": "fixture-password-123",
            "token": token,
            "nickname": "小猫",
        },
    )
    assert response.status_code == 400
    assert "已使用或过期" in response.json()["message"]
    assert "直接登录" in response.json()["message"]
    assert token not in response.text
