"""LG webOS TV, ported from Josh's LG_Remote/remote.py (2026-10-26).

Talks to the TV with bscpylgtv over the local network. Power on is
Wake-on-LAN, so the TV's "Turn on via Wi-Fi" setting must stay on. The
pairing key lives in a sqlite file. The TV only shows its Yes/No pairing
prompt when someone runs the "pair" action, never from background polling.
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
PAIR_TIMEOUT = 60.0  # time to walk over and press Yes on the TV
SSL_PORT = 3001


class NeedsPairing(Exception):
    """The TV has no valid key for the hub, or it turned the pairing down."""


ClientFactory = Callable[[str, str, float, bool], Awaitable[Any]]


async def bscpylgtv_client(ip: str, key_file: str, timeout: float, allow_pairing: bool):
    from bscpylgtv import WebOsClient  # imported here so tests run without the TV library
    from bscpylgtv.exceptions import PyLGTVPairException

    client = await WebOsClient.create(ip, ping_interval=None, states=[], key_file_path=key_file, timeout_connect=timeout)
    if not allow_pairing and not client.is_registered():
        raise NeedsPairing("no pairing key yet")
    try:
        await asyncio.wait_for(client.connect(), None if allow_pairing else timeout + 1)
    except PyLGTVPairException as e:
        raise NeedsPairing(str(e)) from e
    except asyncio.TimeoutError:
        # A TV that rejects a stored key shows its prompt and stalls registration. If its port
        # answers but registration doesn't, assume that, so polling doesn't keep re-prompting.
        await client.disconnect()
        if await port_open(ip, SSL_PORT):
            raise NeedsPairing("the TV didn't accept the saved key")
        raise
    for _ in range(3):  # the library opens the button socket lazily and swallows its failures; warm it here
        await client.input_command("")
        if client.input_connection is not None:
            break
    return client


async def port_open(ip: str, port: int, timeout: float = 2.0) -> bool:
    try:
        _, w = await asyncio.wait_for(asyncio.open_connection(ip, port), timeout)
        w.close()
        return True
    except Exception:
        return False


class LGTV(Adapter):
    kind = "lg_webos"

    def __init__(self, id: str, name: str, *, ip: str, mac: str, key_file: str | Path,
                 apps: list[tuple[str, str]] | None = None, connect_timeout: float = 6.0,
                 client_factory: ClientFactory = bscpylgtv_client,
                 send_wol: Callable[[str, str], None] = wol.send,
                 probe: Callable[[str, int], Awaitable[bool]] = port_open):
        super().__init__(id, name or "LG TV")
        self.ip, self.mac, self.key_file = ip, mac, str(key_file)
        self.apps = apps or DEFAULT_APPS
        self.connect_timeout = connect_timeout
        self._factory, self._send_wol, self._probe = client_factory, send_wol, probe
        self._client = None
        self._needs_pairing = False  # set after a refused or missing key; cleared only by "pair"
        self._lock = asyncio.Lock()

    def actions(self) -> list[str]:
        return ["power_on", "power_off", "button", "launch", "input", "volume", "mute", "pair"]

    def describe(self) -> dict[str, Any]:
        d = super().describe()
        d["apps"] = [{"name": n, "id": i} for n, i in self.apps]
        d["inputs"] = [{"name": n, "id": i} for n, i in INPUTS]
        d["buttons"] = sorted(BUTTONS)
        return d

    async def _connected(self, allow_pairing: bool = False):
        c = self._client
        if c is not None and c.is_connected():
            return c
        if self._needs_pairing and not allow_pairing:
            raise NeedsPairing("LG TV needs pairing: run Pair and press Yes on the TV")
        timeout = PAIR_TIMEOUT if allow_pairing else self.connect_timeout + 3
        try:
            self._client = await asyncio.wait_for(
                self._factory(self.ip, self.key_file, self.connect_timeout, allow_pairing), timeout + 2)
        except NeedsPairing:
            self._needs_pairing = True
            raise
        self._needs_pairing = False
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
                except NeedsPairing:
                    raise
                except Exception:
                    await self._drop()
                    if attempt:
                        raise

    async def status(self) -> DeviceStatus:
        async def read(c):
            # In standby the TV keeps its network socket open, so ask for the real power state.
            try:
                state = (await c.get_power_state()).get("state", "Unknown")
            except Exception:
                state = "Active"  # older webOS without the power service only answers when on
            if state != "Active":
                return "off", {"power_state": state}
            audio = await c.get_audio_status()
            return "on", {"app": await c.get_current_app(), "volume": audio.get("volume"),
                          "muted": audio.get("mute"), "power_state": state}
        try:
            power, detail = await self._with_client(read)
            return DeviceStatus(power=power, reachable=True, detail=detail)
        except NeedsPairing:
            reachable = await self._probe(self.ip, SSL_PORT)
            return DeviceStatus(power="unknown" if reachable else "off", reachable=reachable, needs_pairing=True)
        except Exception as e:
            return DeviceStatus(power="off", reachable=False, detail={"error": str(e)[:120]})

    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        if action == "power_on":
            self._send_wol(self.mac, self.ip)
            # From standby the socket is still up and Wake-on-LAN may be ignored; ask over it too.
            c = self._client
            if c is not None and c.is_connected():
                try:
                    await asyncio.wait_for(c.power_on(), 3)
                except Exception:
                    pass
            return {}
        if action == "pair":
            async with self._lock:
                await self._drop()
                try:
                    await self._connected(allow_pairing=True)
                except NeedsPairing:
                    raise CommandError("The TV turned down pairing. Run Pair again and press Yes on the TV")
                except asyncio.TimeoutError:
                    raise CommandError("No answer from the TV. Make sure it's on, run Pair again and press Yes")
            return {}
        if action == "button":
            if arg not in BUTTONS:
                raise CommandError(f"unknown button {arg!r}")

            async def press(c):
                await c.button(arg)
                if c.input_connection is None:
                    raise ConnectionError("button socket not open")
            await self._run(press)
            return {}
        if action == "launch":
            if not isinstance(arg, str) or not arg:
                raise CommandError("launch needs an app id")
            await self._run(lambda c: c.launch_app(arg))
            return {}
        if action == "input":
            # accepts "HDMI 2", "hdmi2" or the app id itself
            by_name = {n.lower().replace(" ", ""): i for n, i in INPUTS}
            app = by_name.get(str(arg).lower().replace(" ", ""), arg)
            if app not in by_name.values():
                raise CommandError(f"unknown input {arg!r}")
            await self._run(lambda c: c.launch_app(app))
            return {}
        if action == "volume":
            try:
                level = max(0, min(100, int(arg)))
            except (TypeError, ValueError):
                raise CommandError("volume needs a number from 0 to 100")
            await self._run(lambda c: c.set_volume(level))
            return {}
        if action == "mute":
            await self._run(lambda c: c.set_mute(bool(arg)))
            return {}
        if action == "power_off":
            await self._run(lambda c: c.power_off())
            return {}
        raise CommandError(f"LG TV can't do {action!r}")

    async def _run(self, fn):
        try:
            return await self._with_client(fn)
        except NeedsPairing as e:
            raise CommandError(str(e)) from e

    async def close(self) -> None:
        await self._drop()
