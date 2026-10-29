"""A computer on the network: wake it with Wake-on-LAN, sleep or shut it down through its helper.

The helper is agent/homebase_agent.py, a small service on each computer (port 4901, token
protected). The SwiftUI and Windows apps will take over its job later with the same API.
"""
from __future__ import annotations

import asyncio
from typing import Any, Awaitable, Callable

import httpx

from .. import wol
from .base import Adapter, CommandError, DeviceStatus
from .lg import port_open

AGENT_PORT = 4901


class Computer(Adapter):
    kind = "computer"

    def __init__(self, id: str, name: str, *, ip: str, mac: str | None = None, token: str | None = None,
                 agent_port: int = AGENT_PORT, off_action: str = "sleep", can_turn_off: bool = True,
                 transport: httpx.AsyncBaseTransport | None = None, send_wol=wol.send,
                 probe: Callable[[str, int], Awaitable[bool]] = port_open):
        super().__init__(id, name or "Computer")
        if off_action not in ("sleep", "shutdown"):
            raise ValueError("off_action must be sleep or shutdown")
        self.ip, self.mac, self.token = ip, mac, token
        self.agent_port, self.off_action, self.can_turn_off = agent_port, off_action, can_turn_off
        self._http = httpx.AsyncClient(base_url=f"http://{ip}:{agent_port}", timeout=4.0, transport=transport,
                                       headers={"Authorization": f"Bearer {token}"} if token else {})
        self._send_wol, self._probe = send_wol, probe

    def actions(self) -> list[str]:
        acts = ["power_on"] if self.mac else []
        if self.can_turn_off and self.token:
            acts += ["power_off", "sleep", "shutdown"]
        return acts

    async def status(self) -> DeviceStatus:
        if self.ip in ("127.0.0.1", "localhost"):
            return DeviceStatus(power="on", reachable=True, detail={"hub": True})  # the computer running the hub
        try:
            r = await self._http.get("/health")
            r.raise_for_status()
            info = r.json()
            return DeviceStatus(power="on", reachable=True,
                                detail={"os": info.get("os"), "agent": info.get("version")})
        except Exception:
            pass
        # No helper answering: it's asleep, off, or the helper isn't installed. Check a common port.
        if await self._probe(self.ip, 445) or await self._probe(self.ip, 22):
            return DeviceStatus(power="on", reachable=True, detail={"agent": None})
        return DeviceStatus(power="off", reachable=False)

    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        if action == "power_on":
            if not self.mac:
                raise CommandError(f"{self.name} has no MAC address set, so it can't be woken")
            self._send_wol(self.mac, self.ip)
            return {}
        if action in ("power_off", "sleep", "shutdown"):
            if not self.can_turn_off:
                raise CommandError(f"{self.name} can't be turned off from Home Base")
            how = self.off_action if action == "power_off" else action
            try:
                r = await self._http.post("/power", json={"action": how})
            except (httpx.TransportError, asyncio.TimeoutError) as e:
                raise CommandError(f"{self.name}'s helper isn't answering ({e.__class__.__name__})")
            if r.status_code == 401:
                raise CommandError(f"{self.name}'s helper rejected the token")
            r.raise_for_status()
            return {"did": how}
        raise CommandError(f"{self.name} can't do {action!r}")

    async def close(self) -> None:
        await self._http.aclose()
