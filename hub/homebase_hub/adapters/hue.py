"""Philips Hue Bridge through its local v2 API (square bridge, firmware from 2021 or later).

Pairing: press the round button on the bridge, then run the "pair" action within 30 seconds.
The app key it hands back is saved in <data_dir>/hue-<id>.json. Changes made anywhere (the Hue
app, a switch, a schedule) arrive on the bridge's event stream, so the hub hears them at once.
"""
from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Awaitable, Callable

import httpx

from .base import Adapter, CommandError, DeviceStatus

log = logging.getLogger("homebase.hue")
LINK_BUTTON_NOT_PRESSED = 101


class HueBridge(Adapter):
    kind = "hue_bridge"

    def __init__(self, id: str, name: str, *, ip: str, key_file: str | Path,
                 transport: httpx.AsyncBaseTransport | None = None, timeout: float = 5.0):
        super().__init__(id, name or "Hue lights")
        self.ip, self.key_file = ip, Path(key_file)
        # The bridge's certificate is signed by Signify's own CA, not a public one, so it can't be verified
        # the usual way. This only ever talks to one address on the home network.
        self._http = httpx.AsyncClient(base_url=f"https://{ip}", verify=False, timeout=timeout, transport=transport)
        self._key = self._load_key()

    # ---- pairing key ----
    def _load_key(self) -> str | None:
        try:
            return json.loads(self.key_file.read_text())["app_key"]
        except (OSError, ValueError, KeyError):
            return None

    def _save_key(self, app_key: str, client_key: str | None) -> None:
        self.key_file.parent.mkdir(parents=True, exist_ok=True)
        self.key_file.write_text(json.dumps({"app_key": app_key, "client_key": client_key}))
        try:
            self.key_file.chmod(0o600)
        except OSError:
            pass
        self._key = app_key

    # ---- shape ----
    def actions(self) -> list[str]:
        if not self._key:
            return ["pair"]
        return ["power_on", "power_off", "room", "scene", "pair"]

    async def _get(self, kind: str) -> list[dict]:
        r = await self._http.get(f"/clip/v2/resource/{kind}", headers={"hue-application-key": self._key})
        if r.status_code in (401, 403):
            raise PermissionError("the bridge no longer accepts the saved key")
        r.raise_for_status()
        return r.json().get("data", [])

    async def _put(self, kind: str, rid: str, body: dict) -> None:
        r = await self._http.put(f"/clip/v2/resource/{kind}/{rid}", json=body,
                                 headers={"hue-application-key": self._key})
        if r.status_code in (401, 403):
            raise CommandError("the bridge no longer accepts the saved key: press its button and Pair again")
        if r.status_code == 404:
            raise CommandError("the bridge doesn't know that room or scene any more")
        r.raise_for_status()

    async def _snapshot(self) -> dict[str, Any]:
        rooms, zones, groups, scenes = await asyncio.gather(
            self._get("room"), self._get("zone"), self._get("grouped_light"), self._get("scene"))
        by_group = {g["id"]: g for g in groups}
        home = next((g for g in groups if g.get("owner", {}).get("rtype") == "bridge_home"), None)

        def place(r: dict, kind: str) -> dict:
            gid = next((s["rid"] for s in r.get("services", []) if s.get("rtype") == "grouped_light"), None)
            g = by_group.get(gid, {})
            return {"id": r["id"], "name": r.get("metadata", {}).get("name", "Room"), "kind": kind,
                    "on": bool(g.get("on", {}).get("on")),
                    "brightness": round(g.get("dimming", {}).get("brightness", 0)), "group": gid}
        places = [place(r, "room") for r in rooms] + [place(z, "zone") for z in zones]
        scene_list = [{"id": s["id"], "name": s.get("metadata", {}).get("name", "Scene"),
                       "room": s.get("group", {}).get("rid"),
                       "active": s.get("status", {}).get("active", "inactive") != "inactive"} for s in scenes]
        return {"rooms": places, "scenes": scene_list, "home_group": home["id"] if home else None}

    # ---- status ----
    async def status(self) -> DeviceStatus:
        if not self._key:
            try:
                r = await self._http.get("/api/config")  # answers without a key
                r.raise_for_status()
                return DeviceStatus(power="unknown", reachable=True, needs_pairing=True,
                                    detail={"bridge": r.json().get("name")})
            except Exception as e:
                return DeviceStatus(power="unknown", reachable=False, needs_pairing=True, detail={"error": str(e)[:120]})
        try:
            snap = await self._snapshot()
        except PermissionError as e:
            return DeviceStatus(power="unknown", reachable=True, needs_pairing=True, detail={"error": str(e)})
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                return DeviceStatus(power="unknown", reachable=True, detail={
                    "error": "this bridge doesn't have the v2 API: it needs the square bridge with current firmware"})
            return DeviceStatus(power="unknown", reachable=True, detail={"error": str(e)[:120]})
        except Exception as e:
            return DeviceStatus(power="off", reachable=False, detail={"error": str(e)[:120]})
        any_on = any(p["on"] for p in snap["rooms"])
        return DeviceStatus(power="on" if any_on else "off", reachable=True,
                            detail={"rooms": snap["rooms"], "scenes": snap["scenes"]})

    # ---- commands ----
    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        if action == "pair":
            return await self._pair()
        if not self._key:
            raise CommandError("Hue isn't paired yet: press the bridge's button, then Pair")
        snap = await self._snapshot()
        if action in ("power_on", "power_off"):
            on = action == "power_on"
            if snap["home_group"]:
                await self._put("grouped_light", snap["home_group"], {"on": {"on": on}})
            else:
                for p in snap["rooms"]:
                    if p["group"] and p["kind"] == "room":
                        await self._put("grouped_light", p["group"], {"on": {"on": on}})
            return {}
        if action == "room":
            if not isinstance(arg, dict) or "room" not in arg:
                raise CommandError('room needs {"room": <id or name>, "on": true/false, "brightness": 0-100}')
            p = self._find(snap["rooms"], arg["room"], "room")
            if not p["group"]:
                raise CommandError(f"{p['name']} has no lights")
            body: dict[str, Any] = {}
            if "brightness" in arg:
                try:
                    level = max(0.0, min(100.0, float(arg["brightness"])))
                except (TypeError, ValueError):
                    raise CommandError("brightness needs a number from 0 to 100")
                if level == 0:
                    body["on"] = {"on": False}
                else:
                    body["on"] = {"on": True}
                    body["dimming"] = {"brightness": level}
            if "on" in arg:
                body["on"] = {"on": bool(arg["on"])}
            if not body:
                raise CommandError("room needs on, brightness or both")
            await self._put("grouped_light", p["group"], body)
            return {}
        if action == "scene":
            if isinstance(arg, dict):
                rooms = [r for r in snap["rooms"] if r["id"] == arg.get("room") or r["name"].lower() == str(arg.get("room", "")).lower()]
                pool = [s for s in snap["scenes"] if not rooms or s["room"] in {r["id"] for r in rooms}]
                arg = arg.get("scene")
            else:
                pool = snap["scenes"]
            s = self._find(pool, arg, "scene")
            await self._put("scene", s["id"], {"recall": {"action": "active"}})
            return {}
        raise CommandError(f"Hue can't do {action!r}")

    @staticmethod
    def _find(items: list[dict], key: Any, what: str) -> dict:
        key = str(key or "")
        for it in items:
            if it["id"] == key:
                return it
        named = [it for it in items if it["name"].lower() == key.lower()]
        if len(named) == 1:
            return named[0]
        if len(named) > 1:
            raise CommandError(f"more than one {what} is called {key!r}; use its id or name the room")
        raise CommandError(f"no {what} called {key!r}")

    async def _pair(self) -> dict[str, Any]:
        r = await self._http.post("/api", json={"devicetype": "homebase#hub", "generateclientkey": True})
        r.raise_for_status()
        reply = (r.json() or [{}])[0]
        if "error" in reply:
            if reply["error"].get("type") == LINK_BUTTON_NOT_PRESSED:
                raise CommandError("Press the round button on the Hue Bridge first, then Pair within 30 seconds")
            raise CommandError(f"Hue Bridge said: {reply['error'].get('description', 'pairing failed')}")
        ok = reply.get("success", {})
        if not ok.get("username"):
            raise CommandError("Hue Bridge didn't hand back a key")
        self._save_key(ok["username"], ok.get("clientkey"))
        return {}

    # ---- push updates ----
    async def watch(self, changed: Callable[[], Awaitable[None]]) -> None:
        while not self._key:  # wait for pairing before opening the stream
            await asyncio.sleep(5)
        headers = {"hue-application-key": self._key, "Accept": "text/event-stream"}
        async with self._http.stream("GET", "/eventstream/clip/v2", headers=headers,
                                     timeout=httpx.Timeout(10.0, read=None)) as r:
            r.raise_for_status()
            pending: asyncio.Task | None = None
            async for line in r.aiter_lines():
                if not line.startswith("data:"):
                    continue
                # A scene recall sends a burst of events; refresh once after the burst settles.
                if pending is None or pending.done():
                    pending = asyncio.create_task(self._after(0.3, changed))

    @staticmethod
    async def _after(delay: float, fn: Callable[[], Awaitable[None]]) -> None:
        await asyncio.sleep(delay)
        try:
            await fn()
        except Exception:
            log.exception("refresh after a Hue event failed")

    async def close(self) -> None:
        await self._http.aclose()
