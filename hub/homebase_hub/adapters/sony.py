"""Sony Bravia TV over its local REST API (the "IP control" feature).

On the TV: Settings > Network > Home network > IP control:
  Authentication = Normal and Pre-Shared Key, Pre-Shared Key = the `psk` in hub.toml,
  and turn on Remote start so it can be woken over the network.
Buttons go through IRCC (the TV's IR-over-IP service); the codes are read from the TV once.
"""
from __future__ import annotations

import asyncio
from typing import Any

import httpx

from .. import wol
from .base import Adapter, CommandError, DeviceStatus

# Home Base button name -> Sony IRCC code name
BUTTON_NAMES = {
    "UP": "Up", "DOWN": "Down", "LEFT": "Left", "RIGHT": "Right", "ENTER": "Confirm",
    "BACK": "Return", "EXIT": "Exit", "HOME": "Home", "MENU": "ActionMenu", "INFO": "Display",
    "VOLUMEUP": "VolumeUp", "VOLUMEDOWN": "VolumeDown", "MUTE": "Mute",
    "CHANNELUP": "ChannelUp", "CHANNELDOWN": "ChannelDown",
    "PLAY": "Play", "PAUSE": "Pause", "REWIND": "Rewind", "FASTFORWARD": "Forward",
}
INPUTS = [(f"HDMI {n}", f"extInput:hdmi?port={n}") for n in range(1, 5)]
AUTH_ERRORS = {401, 403, 40005}
NOT_SHOWING_INPUT = 7  # getPlayingContentInfo when an app or the home screen is up

IRCC_BODY = (
    '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
    's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
    '<u:X_SendIRCC xmlns:u="urn:schemas-sony-com:service:IRCC:1"><IRCCCode>{code}</IRCCCode>'
    '</u:X_SendIRCC></s:Body></s:Envelope>'
)


class SonyError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(f"Sony TV error {code}: {message}")
        self.code = code


class SonyTV(Adapter):
    kind = "sony_bravia"

    def __init__(self, id: str, name: str, *, ip: str, psk: str, mac: str | None = None,
                 timeout: float = 4.0, transport: httpx.AsyncBaseTransport | None = None,
                 send_wol=wol.send):
        super().__init__(id, name or "Sony TV")
        self.ip, self.psk, self.mac = ip, psk, mac
        self._http = httpx.AsyncClient(base_url=f"http://{ip}", timeout=timeout, transport=transport,
                                       headers={"X-Auth-PSK": psk})
        self._send_wol = send_wol
        self._ircc: dict[str, str] = {}
        self._apps: list[dict] = []
        self._id = 0

    def actions(self) -> list[str]:
        return ["power_on", "power_off", "button", "launch", "input", "volume", "mute"]

    def describe(self) -> dict[str, Any]:
        d = super().describe()
        d["apps"] = self._apps
        d["inputs"] = [{"name": n, "id": i} for n, i in INPUTS]
        d["buttons"] = sorted(BUTTON_NAMES)
        return d

    async def _call(self, service: str, method: str, params: list | None = None, version: str = "1.0") -> Any:
        self._id += 1
        r = await self._http.post(f"/sony/{service}", json={"method": method, "id": self._id,
                                                             "params": params or [], "version": version})
        if r.status_code in (401, 403):
            raise SonyError(r.status_code, "pre-shared key rejected")
        r.raise_for_status()
        body = r.json()
        if "error" in body:
            code, msg = (body["error"] + [0, ""])[:2]
            raise SonyError(int(code), str(msg))
        return body.get("result", [])

    async def _load_codes(self) -> None:
        if self._ircc:
            return
        result = await self._call("system", "getRemoteControllerInfo")
        self._ircc = {c["name"]: c["value"] for c in result[1]}

    async def _load_apps(self) -> None:
        if self._apps:
            return
        try:
            result = await self._call("appControl", "getApplicationList")
            self._apps = [{"name": a["title"], "id": a["uri"]} for a in result[0]]
        except Exception:
            pass  # app list is a nice-to-have; the TV refuses it while starting up

    async def status(self) -> DeviceStatus:
        try:
            power = (await self._call("system", "getPowerStatus"))[0].get("status")
        except SonyError as e:
            if e.code in AUTH_ERRORS:
                return DeviceStatus(power="unknown", reachable=True, needs_pairing=True,
                                    detail={"error": "pre-shared key rejected: check IP control on the TV"})
            return DeviceStatus(power="unknown", reachable=True, detail={"error": str(e)[:120]})
        except Exception as e:
            return DeviceStatus(power="off", reachable=False, detail={"error": str(e)[:120]})
        if power != "active":
            return DeviceStatus(power="off", reachable=True, detail={"power_state": power})

        detail: dict[str, Any] = {"power_state": power}
        await self._load_apps()
        try:
            playing = (await self._call("avContent", "getPlayingContentInfo"))[0]
            detail["app"] = playing.get("title") or playing.get("uri")
            detail["input"] = playing.get("uri")
        except SonyError as e:
            if e.code != NOT_SHOWING_INPUT:
                detail["error"] = str(e)[:120]
        try:
            for v in (await self._call("audio", "getVolumeInformation"))[0]:
                if v.get("target") == "speaker":
                    detail["volume"], detail["muted"] = v.get("volume"), v.get("mute")
        except Exception:
            pass
        return DeviceStatus(power="on", reachable=True, detail=detail)

    async def _ircc_send(self, button: str) -> None:
        await self._load_codes()
        code = self._ircc.get(BUTTON_NAMES[button])
        if not code:
            raise CommandError(f"this Sony TV has no {button} button")
        r = await self._http.post("/sony/IRCC", content=IRCC_BODY.format(code=code), headers={
            "Content-Type": 'text/xml; charset="utf-8"',
            "SOAPACTION": '"urn:schemas-sony-com:service:IRCC:1#X_SendIRCC"'})
        if r.status_code in (401, 403):
            raise SonyError(r.status_code, "pre-shared key rejected")
        r.raise_for_status()

    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        try:
            return await self._command(action, arg)
        except SonyError as e:
            raise CommandError(str(e)) from e

    async def _command(self, action: str, arg: Any) -> dict[str, Any]:
        if action == "power_on":
            if self.mac:
                self._send_wol(self.mac, self.ip)
            try:
                await self._call("system", "setPowerStatus", [{"status": True}])
            except (httpx.TransportError, asyncio.TimeoutError):
                if not self.mac:
                    raise
            return {}
        if action == "power_off":
            await self._call("system", "setPowerStatus", [{"status": False}])
            return {}
        if action == "button":
            if arg not in BUTTON_NAMES:
                raise CommandError(f"unknown button {arg!r}")
            await self._ircc_send(arg)
            return {}
        if action == "input":
            by_name = {n.lower().replace(" ", ""): i for n, i in INPUTS}
            uri = by_name.get(str(arg).lower().replace(" ", ""), arg)
            if uri not in by_name.values():
                raise CommandError(f"unknown input {arg!r}")
            await self._call("avContent", "setPlayContent", [{"uri": uri}])
            return {}
        if action == "launch":
            if not isinstance(arg, str) or not arg:
                raise CommandError("launch needs an app id")
            uri = next((a["id"] for a in self._apps if arg in (a["id"], a["name"])), arg)
            await self._call("appControl", "setActiveApp", [{"uri": uri}])
            return {}
        if action == "volume":
            try:
                level = max(0, min(100, int(arg)))
            except (TypeError, ValueError):
                raise CommandError("volume needs a number from 0 to 100")
            await self._call("audio", "setAudioVolume", [{"target": "speaker", "volume": str(level)}])
            return {}
        if action == "mute":
            await self._call("audio", "setAudioMute", [{"status": bool(arg)}])
            return {}
        raise CommandError(f"Sony TV can't do {action!r}")

    async def close(self) -> None:
        await self._http.aclose()
