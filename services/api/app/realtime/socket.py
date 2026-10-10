import asyncio

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.api.auth import authenticate
from app.db import models as m
from app.db.base import SessionLocal
from app.domain.common import DomainError, dump, member

router = APIRouter()


@router.websocket("/spaces/{sid}/ws")
async def subscribe(socket: WebSocket, sid: str):
    auth = socket.headers.get("authorization", "")
    try:
        if not auth.startswith("Bearer "):
            await socket.close(code=4401)
            return
        with SessionLocal() as db:
            user, _ = authenticate(db, auth[7:])
            member(db, sid, user.id)
        await socket.accept()
        handshake = await asyncio.wait_for(socket.receive_json(), timeout=10)
        cursor = handshake.get("after_seq", 0)
        if type(cursor) is not int or cursor < 0:
            await socket.close(code=4400)
            return
        while True:
            # Durable database events work across API restarts and multiple workers.
            # Polling is deliberately bounded at 250 ms for this two-person deployment.
            with SessionLocal() as db:
                user, _ = authenticate(db, auth[7:])
                member(db, sid, user.id)
                space = db.get(m.Space, sid)
                if cursor > space.seq:
                    await socket.send_json({"type": "resync_required"})
                    cursor = space.seq
                items = list(
                    db.scalars(
                        select(m.Event)
                        .where(m.Event.space_id == sid, m.Event.seq > cursor)
                        .order_by(m.Event.seq)
                        .limit(100)
                    )
                )
                for event in items:
                    await socket.send_json({"type": "event", "event": dump(event)})
                    cursor = event.seq
            await asyncio.sleep(0.25)
    except (WebSocketDisconnect, asyncio.TimeoutError):
        return
    except DomainError as e:
        await socket.close(code=4401 if e.status == 401 else 4403)
