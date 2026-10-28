"""HTTP and WebSocket API the apps (and the test page) talk to. See shared/protocol/README.md."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

from fastapi import Body, FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse

from . import __version__
from .adapters import CommandError, build
from .config import HubConfig
from .hub import History, Hub

STATIC = Path(__file__).parent / "static"


def make_hub(cfg: HubConfig) -> Hub:
    cfg.data_dir.mkdir(parents=True, exist_ok=True)
    return Hub([build(d, cfg) for d in cfg.devices], History(cfg.data_dir / "hub.sqlite"), cfg.poll_seconds)


def create_app(hub: Hub, poll: bool = True) -> FastAPI:
    @asynccontextmanager
    async def lifespan(_app):
        if poll:
            hub.start()
        yield
        await hub.stop()

    app = FastAPI(title="Home Base hub", version=__version__, lifespan=lifespan)

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
    async def command(device_id: str, action: str, body: dict = Body(default_factory=dict)):
        return {"ok": True, "result": await run(device_id, action, body.get("arg"), body.get("source", "http"))}

    @app.get("/api/history")
    async def history(limit: int = 50):
        return hub.history.recent(max(1, min(limit, 500)))

    @app.websocket("/api/live")
    async def live(ws: WebSocket):
        await ws.accept()
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
                    result = await hub.command(msg["device"], msg["action"], msg.get("arg"), msg.get("source", "app"))
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": True, "result": result})
                except KeyError:
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": False, "error": f"no device {msg.get('device')!r}"})
                except Exception as e:
                    await ws.send_json({"type": "result", "id": msg.get("id"), "ok": False, "error": str(e)[:200] or repr(e)})
        except WebSocketDisconnect:
            pass
        finally:
            sender.cancel()
            hub.unsubscribe(q)

    return app
