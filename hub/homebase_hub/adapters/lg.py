"""LG webOS TV, ported from Josh's LG_Remote/remote.py (2026-10-26).

Talks to the TV with bscpylgtv over the local network. Power on is
Wake-on-LAN, so the TV's "Turn on via Wi-Fi" setting must stay on. The
pairing key lives in a sqlite file; if it is missing the TV shows a Yes/No
prompt once.
"""
from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any, Awaitable, Callable

from .. import wol
from .base import Adapter, CommandError, DeviceStatus

DEFAULT_APPS = [
    ("Netflix", "netflix"), ("Prime Video", "amazon"), ("Disney+", "com.disney.disneyplus-prod"),
    ("Hulu", "hulu"), ("Sling", "com.movenetworks.app.sling-tv-sling-production"),
    ("Apple TV", "com.apple.appletv"), ("HBO Max", "com.wbd.stream"), ("YouTube", "youtube.leanback.v4"),
]
INPUTS = [(f"HDMI {n}", f"com.webos.app.hdmi{n}") for n in range(1, 5)]
BUTTONS = {
    "UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACK", "EXIT", "HOME", "MENU", "INFO",
    "VOLUMEUP", "VOLUMEDOWN", "MUTE", "CHANNELUP", "CHANNELDOWN",
    "PLAY", "PAUSE", "REWIND", "FASTFORWARD",
}

ClientFactory = Callable[[str, str, float], Awaitable[Any]]


async def bscpylgtv_client(ip: str, key_file: str, timeout: float):
    from bscpylgtv import WebOsClient  # imported here so tests run without the TV library

    client = await WebOsClient.create(ip, ping_interval=None, states=[], key_file_path=key_file, timeout_connect=timeout)
    await client.connect()
    for _ in range(3):  # the library opens the button socket lazily and swallows its failures; warm it here
        await client.input_command("")
        if client.input_connection is not None:
            break
    return client


class LGTV(Adapter):
    kind = "lg_webos"

    def __init__(self, id: str, name: str, *, ip: str, mac: str, key_file: str | Path,
                 apps: list[tuple[str, str]] | None = None, connect_timeout: float = 6.0,
                 client_factory: ClientFactory = bscpylgtv_client,
                 send_wol: Callable[[str, str], None] = wol.send):
        super().__init__(id, name or "LG TV")
        self.ip, self.mac, self.key_file = ip, mac, str(key_file)
        self.apps = apps or DEFAULT_APPS
        self.connect_timeout = connect_timeout
        self._factory, self._send_wol = client_factory, send_wol
        self._client = None
        self._lock = asyncio.Lock()

    def actions(self) -> list[str]:
        return ["power_on", "power_off", "button", "launch", "input", "volume", "mute"]

    def describe(self) -> dict[str, Any]:
        d = super().describe()
        d["apps"] = [{"name": n, "id": i} for n, i in self.apps]
        d["inputs"] = [{"name": n, "id": i} for n, i in INPUTS]
        d["buttons"] = sorted(BUTTONS)
        return d

    async def _connected(self):
        c = self._client
        if c is not None and c.is_connected():
            return c
        self._client = await asyncio.wait_for(
            self._factory(self.ip, self.key_file, self.connect_timeout), self.connect_timeout + 2)
        return self._client

    async def _drop(self) -> None:
        c, self._client = self._client, None
        if c is not None:
            try:
                await c.disconnect()
            except Exception:
                pass

    async def _with_client(self, fn):
        """Run fn(client), reconnecting once if the connection went stale."""
        async with self._lock:
            for attempt in range(2):
                try:
                    return await fn(await self._connected())
                except Exception:
                    await self._drop()
                    if attempt:
                        raise

    async def status(self) -> DeviceStatus:
        async def read(c):
            audio = await c.get_audio_status()
            return {"app": await c.get_current_app(), "volume": audio.get("volume"), "muted": audio.get("mute")}
        try:
            return DeviceStatus(power="on", reachable=True, detail=await self._with_client(read))
        except Exception as e:
            return DeviceStatus(power="off", reachable=False, detail={"error": str(e)[:120]})

    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        if action == "power_on":
            self._send_wol(self.mac, self.ip)
            return {}
        if action == "button":
            if arg not in BUTTONS:
                raise CommandError(f"unknown button {arg!r}")

            async def press(c):
                await c.button(arg)
                if c.input_connection is None:
                    raise ConnectionError("button socket not open")
            await self._with_client(press)
            return {}
        if action == "launch":
            if not isinstance(arg, str) or not arg:
                raise CommandError("launch needs an app id")
            await self._with_client(lambda c: c.launch_app(arg))
            return {}
        if action == "input":
            # accepts "HDMI 2", "hdmi2" or the app id itself
            by_name = {n.lower().replace(" ", ""): i for n, i in INPUTS}
            app = by_name.get(str(arg).lower().replace(" ", ""), arg)
            if app not in by_name.values():
                raise CommandError(f"unknown input {arg!r}")
            await self._with_client(lambda c: c.launch_app(app))
            return {}
        if action == "volume":
            try:
                level = max(0, min(100, int(arg)))
            except (TypeError, ValueError):
                raise CommandError("volume needs a number from 0 to 100")
            await self._with_client(lambda c: c.set_volume(level))
            return {}
        if action == "mute":
            await self._with_client(lambda c: c.set_mute(bool(arg)))
            return {}
        if action == "power_off":
            await self._with_client(lambda c: c.power_off())
            await self._drop()
            return {}
        raise CommandError(f"LG TV can't do {action!r}")

    async def close(self) -> None:
        await self._drop()
