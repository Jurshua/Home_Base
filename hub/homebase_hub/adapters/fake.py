"""A pretend TV for tests and for trying the hub without real devices."""
from __future__ import annotations

from typing import Any

from .base import Adapter, CommandError, DeviceStatus


class FakeTV(Adapter):
    kind = "fake_tv"

    def __init__(self, id: str, name: str, **_):
        super().__init__(id, name or "Fake TV")
        self.on, self.app, self.volume, self.muted = False, None, 10, False
        self.pressed: list[str] = []

    def actions(self) -> list[str]:
        return ["power_on", "power_off", "button", "launch", "input", "volume", "mute"]

    async def status(self) -> DeviceStatus:
        if not self.on:
            return DeviceStatus(power="off", reachable=False)
        return DeviceStatus(power="on", reachable=True, detail={"app": self.app, "volume": self.volume, "muted": self.muted})

    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        if action == "power_on":
            self.on, self.app = True, "home"
            return {}
        if not self.on:
            raise CommandError("TV is off")
        if action == "power_off":
            self.on = False
        elif action == "button":
            self.pressed.append(arg)
        elif action in ("launch", "input"):
            self.app = arg
        elif action == "volume":
            self.volume = int(arg)
        elif action == "mute":
            self.muted = bool(arg)
        else:
            raise CommandError(f"can't do {action!r}")
        return {}
