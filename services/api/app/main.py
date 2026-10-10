import logging
from uuid import uuid4

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.api.auth import router as auth_router
from app.api.milestone_versions import router as milestone_version_router
from app.api.routes import router
from app.config import settings
from app.db.base import SessionLocal
from app.domain.common import DomainError
from app.realtime.socket import router as ws_router

settings().validate_runtime()
app = FastAPI(
    title="喵伴", version="0.1.0", docs_url="/api/docs" if settings().environment != "production" else None
)
app.include_router(auth_router, prefix="/api/v1")
app.include_router(router, prefix="/api/v1")
app.include_router(milestone_version_router, prefix="/api/v1")
app.include_router(ws_router, prefix="/api/v1")


@app.middleware("http")
async def request_context(request: Request, call_next):
    request.state.request_id = str(uuid4())
    response = await call_next(request)
    response.headers["X-Request-ID"] = request.state.request_id
    response.headers["Cache-Control"] = "no-store"
    return response


@app.exception_handler(DomainError)
async def domain_error(request: Request, error: DomainError):
    return JSONResponse(
        status_code=error.status,
        content={
            "code": error.code,
            "message": error.message,
            "request_id": request.state.request_id,
            **error.details,
        },
    )


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, error: RequestValidationError):
    # Never echo credentials from invalid input in an error response.
    fields = [".".join(map(str, e["loc"])) for e in error.errors()]
    field_errors = {}
    message = "输入格式不正确，请检查后重试"
    if request.url.path in {"/api/v1/auth/login", "/api/v1/auth/activate"}:
        hints = {
            "username": "账号须为 3–80 位英文字母、数字，或 _ . @ -；中文请填在昵称中",
            "password": "密码须为 10–128 个字符，首尾空格不计入长度",
            "token": "请粘贴完整的激活码或小屋邀请码（20–128 个字符）",
            "nickname": "昵称须为 1–40 个字符，可以使用中文",
        }
        labels = {"username": "账号", "password": "密码", "token": "激活码或邀请码", "nickname": "昵称"}
        for item in error.errors():
            loc = item["loc"]
            if len(loc) == 2 and loc[0] == "body" and loc[1] in hints:
                field = loc[1]
                field_errors[field] = f"请填写{labels[field]}" if item["type"] == "missing" else hints[field]
        # Unknown field names can contain private input too; expose only our known schema.
        fields = [f"body.{name}" for name in field_errors]
        message = "；".join(field_errors.values()) or "请求格式不正确，请更新 App 后重试"
    return JSONResponse(
        status_code=422,
        content={
            "code": "INVALID_INPUT",
            "message": message,
            "request_id": request.state.request_id,
            "fields": fields,
            **({"field_errors": field_errors} if field_errors else {}),
        },
    )


@app.exception_handler(SQLAlchemyError)
async def database_error(request: Request, error: SQLAlchemyError):
    logging.error("database_error request_id=%s kind=%s", request.state.request_id, type(error).__name__)
    return JSONResponse(
        status_code=503,
        content={
            "code": "SERVICE_UNAVAILABLE",
            "message": "服务暂时不可用，请重试",
            "request_id": request.state.request_id,
        },
    )


@app.get("/health")
def health():
    return {"status": "ok", "version": "0.1.0"}


@app.get("/ready")
def ready():
    with SessionLocal() as db:
        db.execute(text("SELECT version_num FROM alembic_version"))
    return {"status": "ready"}
