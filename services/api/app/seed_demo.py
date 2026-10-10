"""Development-only accounts, created without artificial wallet balances."""

from app.api.auth import passwords
from app.config import settings
from app.db import models as m
from app.db.base import SessionLocal
from app.domain.common import one


def main():
    if settings().environment != "development":
        raise SystemExit("Demo seed is allowed only in development")
    with SessionLocal.begin() as db:
        for name, nickname, avatar in [
            ("demo_a", "演示 · 橘猫", "ginger"),
            ("demo_b", "演示 · 灰猫", "gray"),
        ]:
            if one(db, m.User, username=name) is None:
                db.add(
                    m.User(
                        username=name,
                        nickname=nickname,
                        avatar=avatar,
                        password_hash=passwords.hash("Demo-only-password-123"),
                    )
                )
    print("Development-only accounts demo_a / demo_b; password Demo-only-password-123")
    print("Wallets start at zero. Create/bind a space and earn points through accepted tasks.")


if __name__ == "__main__":
    main()
