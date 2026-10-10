import argparse
import getpass
import secrets
from datetime import timedelta

from sqlalchemy import select, update

from app.api.auth import passwords
from app.config import settings
from app.db import models as m
from app.db.base import SessionLocal, now
from app.domain.common import digest


def main():
    p = argparse.ArgumentParser(description="喵伴服务器维护命令（不通过公开 HTTP 暴露）")
    commands = p.add_subparsers(dest="command", required=True)
    commands.add_parser("activation")
    reset = commands.add_parser("reset-password")
    reset.add_argument("username")
    commands.add_parser("reconcile")
    args = p.parse_args()
    settings().validate_runtime()
    with SessionLocal.begin() as db:
        if args.command == "activation":
            token = secrets.token_urlsafe(32)
            db.add(m.Activation(token_hash=digest(token), expires_at=now() + timedelta(hours=24)))
            print("一次性激活码（24 小时有效，仅在本终端显示）：", token)
        elif args.command == "reset-password":
            user = db.scalar(select(m.User).where(m.User.username == args.username).with_for_update())
            if not user:
                raise SystemExit("账号不存在")
            password = getpass.getpass("新密码（至少 10 字符）：")
            if len(password) < 10 or password != getpass.getpass("再次输入："):
                raise SystemExit("密码不满足要求或两次不同")
            user.password_hash = passwords.hash(password)
            db.execute(update(m.AuthSession).where(m.AuthSession.user_id == user.id).values(revoked=True))
            db.execute(update(m.Device).where(m.Device.user_id == user.id).values(active=False))
            print("已重置密码并撤销旧会话与设备绑定")
        elif args.command == "reconcile":
            from sqlalchemy import func

            bad = []
            for w in db.scalars(select(m.Wallet)):
                total = db.scalar(
                    select(func.coalesce(func.sum(m.Ledger.delta), 0)).where(
                        m.Ledger.space_id == w.space_id, m.Ledger.user_id == w.user_id
                    )
                )
                if total != w.balance:
                    bad.append((w.space_id, w.user_id))
            if bad:
                raise SystemExit(f"账目不一致：{bad}")
            print("全部钱包余额与不可变流水一致")


if __name__ == "__main__":
    main()
