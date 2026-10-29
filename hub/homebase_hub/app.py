"""HTTP and WebSocket API the apps (and the test page) talk to. See shared/protocol/README.md."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse

from . import __version__
from .adapters import CommandError, build
from .config import HubConfig
from .hub import History, Hub
from .pairing import Caller, Clients, PairingError, bearer

STATIC = Path(__file__).parent / "static"
LOCAL_HOSTS = frozenset({"127.0.0.1", "::1"})
OPEN_PATHS = {"/", "/api/health", "/api/pair"}  # everything else needs a paired device or the hub's own Mac


def make_hub(cfg: HubConfig) -> Hub:
    cfg.data_dir.mkdir(parents=True, exist_ok=True)
    return Hub([build(d, cfg) for d in cfg.devices], History(cfg.data_dir / "hub.sqlite"), cfg.poll_seconds)


def create_app(hub: Hub, poll: bool = True, clients: Clients | None = None, announcer=None,
               local_hosts: frozenset[str] = LOCAL_HOSTS) -> FastAPI:
    clients = clients or Clients(":memory:")
    sockets: dict[str, set[WebSocket]] = {}  # client id -> its open live connections

    @asynccontextmanager
    async def lifespan(_app):
        if poll:
            hub.start()
        if announcer:
            await announcer.start()
        yield
        if announcer:
            await announcer.stop()
        await hub.stop()
        clients.close()

    app = FastAPI(title="Home Base hub", version=__version__, lifespan=lifespan)

    def identify(host: str | None, token: str | None) -> Caller | None:
        if host in local_hosts:
            return Caller(name="Mac Mini")
        return clients.check(token)

    @app.middleware("http")
    async def require_pairing(request: Request, call_next):
        if request.url.path not in OPEN_PATHS:
            caller = identify(request.client.host if request.client else None, bearer(request.headers.get("authorization")))
            if caller is None:
                return JSONResponse({"detail": "This device isn't paired with the hub yet"}, status_code=401)
            request.state.caller = caller
        return await call_next(request)

    def source_for(caller: Caller, given: Any, default: str) -> str:
        # A paired device is always named by its own pairing, so the history can't be spoofed.
        return caller.name if not caller.local else str(given or default)

    async def run(device_id: str, action: str, arg: Any, source: str) -> dict:
        try:
            return await hub.command(device_id, action, arg, source)
        except KeyError:
            raise HTTPException(404, f"no device {device_id!r}")
        except CommandError as e:
            raise HTTPException(400, str(e))
        except Exception as e:
            raise HTTPException(502, f"device didn't respond: {str(e)[:160]}")

    @app.get("/")
    async def test_page():
        return FileResponse(STATIC / "test.html")

    @app.get("/api/health")
    async def health():
        return {"ok": True, "version": __version__, "devices": len(hub.adapters)}

    # ---- pairing ----
    @app.post("/api/pair")
    async def pair(request: Request, body: dict = Body(default_factory=dict)):
        try:
            return clients.pair(str(body.get("code", "")), body.get("name", ""),
                                request.client.host if request.client else "?")
        except PairingError as e:
            raise HTTPException(e.status, str(e))

    @app.get("/api/me")
    async def me(request: Request):
        c: Caller = request.state.caller
        return {"name": c.name, "id": c.client_id, "local": c.local}

    @app.post("/api/pairing-codes")
    async def new_code(request: Request):
        return clients.new_code(by=request.state.caller.name)

    @app.get("/api/clients")
    async def list_clients():
        return clients.list()

    @app.delete("/api/clients/{client_id}")
    async def remove_client(client_id: str):
        if not clients.remove(client_id):
            raise HTTPException(404, "no such device")
        for ws in list(sockets.pop(client_id, ())):
            try:
                await ws.close(code=4401, reason="removed from the hub")
            except Exception:
                pass
        return {"ok": True}

    # ---- devices ----
    @app.get("/api/devices")
    async def devices():
        return hub.snapshot()

    @app.get("/api/devices/{device_id}")
    async def device(device_id: str):
        if device_id not in hub.state:
            raise HTTPException(404, f"no device {device_id!r}")
        return hub.state[device_id]

    @app.post("/api/devices/{device_id}/refresh")
    async def refresh(device_id: str):
        if device_id not in hub.adapters:
            raise HTTPException(404, f"no device {device_id!r}")
        return await hub.refresh(device_id)

    @app.post("/api/devices/{device_id}/{action}")
    async def command(request: Request, device_id: str, action: str, body: dict = Body(default_factory=dict)):
        source = source_for(request.state.caller, body.get("source"), "http")
        return {"ok": True, "result": await run(device_id, action, body.get("arg"), source)}

    @app.get("/api/history")
    async def history(limit: int = 50):
        return hub.history.recent(max(1, min(limit, 500)))

    @app.websocket("/api/live")
    async def live(ws: WebSocket):
        token = bearer(ws.headers.get("authorization")) or ws.query_params.get("token")
        caller = identify(ws.client.host if ws.client else None, token)
        if caller is None:
            await ws.close(code=4401, reason="this device isn't paired with the hub yet")
            return
        await ws.accept()
        if caller.client_id:
            sockets.setdefault(caller.client_id, set()).add(ws)
        q = hub.subscribe()
        await ws.send_json({"type": "snapshot", "devices": hub.snapshot()})

        async def pump():
            while True:
                await ws.send_json(await q.get())

        sender = asyncio.create_task(pump())
        try:
            while True:
                msg = await ws.receive_json()
                if msg.get("type") != "command":
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": False, "error": "unknown message type"})
                    continue
                try:
                    result = await hub.command(msg["device"], msg["action"], msg.get("arg"),
                                               source_for(caller, msg.get("source"), "app"))
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": True, "result": result})
                except KeyError:
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": False, "error": f"no device {msg.get('device')!r}"})
                except Exception as e:
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": False, "error": str(e)[:200] or repr(e)})
        except (WebSocketDisconnect, RuntimeError):
            pass
        finally:
            sender.cancel()
            hub.unsubscribe(q)
            if caller.client_id:
                sockets.get(caller.client_id, set()).discard(ws)

    return app
