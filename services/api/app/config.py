from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    environment: str = "development"
    database_url: str = "postgresql+psycopg://miaoban:miaoban@127.0.0.1:55432/miaoban"
    public_url: str = "http://localhost:8000"
    push_provider: str = "disabled"
    apns_key_path: str = ""
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_topic: str = ""
    apns_sandbox: bool = True
    fcm_credentials_path: str = ""

    def validate_runtime(self):
        if not self.database_url.startswith("postgresql+psycopg://"):
            raise RuntimeError("Only PostgreSQL is supported")
        if self.environment == "production":
            from urllib.parse import urlsplit

            from sqlalchemy.engine import make_url

            public = urlsplit(self.public_url)
            if public.scheme != "https" or not public.hostname:
                raise RuntimeError("Production requires HTTPS public_url")
            if any(s in self.database_url for s in (":miaoban@", "isolated-test-only", ":password@")):
                raise RuntimeError("Production database uses an unsafe example password")
            password = make_url(self.database_url).password or ""
            if len(password) < 24 or "replace-with" in password:
                raise RuntimeError("Production requires a unique database password of at least 24 characters")


@lru_cache
def settings():
    return Settings()
