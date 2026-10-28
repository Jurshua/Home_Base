"""Apple TV through pyatv.

Pairing needs a PIN shown on the TV, so it's a one-time command rather than an action:
    python -m homebase_hub pair-appletv <device id>
Credentials are kept in <data_dir>/appletv.json by pyatv's own file storage.
"""
from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from .base import Adapter, CommandError, DeviceStatus

# Home Base button name -> pyatv RemoteControl method
BUTTONS = {
    "UP": "up", "DOWN": "down", "LEFT": "left", "RIGHT": "right", "ENTER": "select",
    "BACK": "menu", "HOME": "home", "MENU": "top_menu", "PLAY": "play", "PAUSE": "pause",
    "PLAYPAUSE": "play_pause", "NEXT": "next", "PREVIOUS": "previous",
    "FASTFORWARD": "skip_forward", "REWIND": "skip_backward",
    "VOLUMEUP": "volume_up", "VOLUMEDOWN": "volume_down",
}
PAIR_PROTOCOLS = ("Companion", "AirPlay")  # Companion: power and apps; AirPlay: remote and now playing


def storage_path(data_dir: Path) -> Path:
    return Path(data_dir) / "appletv.json"


class AppleTV(Adapter):
    kind = "apple_tv"

    def __init__(self, id: str, name: str, *, ip: str, storage_file: str | Path, connector=None):
        super().__init__(id, name or "Apple TV")
        self.ip, self.storage_file = ip, str(storage_file)
        self._connector = connector or self._pyatv_connect
        self._atv = None
        self._apps: list[dict] = []
        self._needs_pairing = False
        self._lock = asyncio.Lock()

    def actions(self) -> list[str]:
        return ["power_on", "power_off", "button", "launch", "volume"]

    def describe(self) -> dict[str, Any]:
        d = super().describe()
        d["apps"] = self._apps
        d["buttons"] = sorted(BUTTONS)
        return d

    async def _pyatv_connect(self):
        import pyatv
        from pyatv.const import Protocol
        from pyatv.storage.file_storage import FileStorage

        loop = asyncio.get_running_loop()
        storage = FileStorage(self.storage_file, loop)
        await storage.load()
        found = await pyatv.scan(loop, hosts=[self.ip], timeout=3, storage=storage)
        if not found:
            raise ConnectionError("Apple TV not found on the network")
        conf = found[0]
        settings = await storage.get_settings(conf)
        if not settings.protocols.companion.credentials:
            raise PermissionError("not paired")
        return await pyatv.connect(conf, loop, protocol=Protocol.Companion, storage=storage)

    async def _connected(self):
        if self._atv is not None:
            return self._atv
        try:
            self._atv = await asyncio.wait_for(self._connector(), 12)
        except PermissionError:
            self._needs_pairing = True
            raise
        self._needs_pairing = False
        try:
            self._apps = [{"name": a.name, "id": a.identifier} for a in await self._atv.apps.app_list()]
        except Exception:
            pass
        return self._atv

    async def _drop(self) -> None:
        atv, self._atv = self._atv, None
        if atv is not None:
            try:
                atv.close()
            except Exception:
                pass

    async def _with_atv(self, fn):
        async with self._lock:
            for attempt in range(2):
                try:
                    return await fn(await self._connected())
                except PermissionError:
                    raise
                except Exception:
                    await self._drop()
                    if attempt:
                        raise

    async def status(self) -> DeviceStatus:
        async def read(atv):
            from pyatv.const import PowerState

            power = atv.power.power_state
            if power == PowerState.Off:
                return "off", {}
            detail: dict[str, Any] = {}
            try:
                playing = await atv.metadata.playing()
                detail["state"] = playing.device_state.name.lower()
                detail["title"] = playing.title
                detail["series"] = playing.series_name
            except Exception:
                pass
            try:
                app = atv.metadata.app
                detail["app"] = app.name if app else None
            except Exception:
                pass
            return "on", detail
        try:
            power, detail = await self._with_atv(read)
            return DeviceStatus(power=power, reachable=True, detail=detail)
        except PermissionError:
            return DeviceStatus(power="unknown", reachable=True, needs_pairing=True,
                                detail={"error": "not paired: run pair-appletv on the hub"})
        except Exception as e:
            return DeviceStatus(power="off", reachable=False, detail={"error": str(e)[:120]})

    async def command(self, action: str, arg: Any = None) -> dict[str, Any]:
        try:
            return await self._command(action, arg)
        except PermissionError:
            raise CommandError("Apple TV isn't paired yet: run pair-appletv on the hub")

    async def _command(self, action: str, arg: Any) -> dict[str, Any]:
        if action == "power_on":
            await self._with_atv(lambda atv: atv.power.turn_on())
            return {}
        if action == "power_off":
            await self._with_atv(lambda atv: atv.power.turn_off())
            return {}
        if action == "button":
            if arg not in BUTTONS:
                raise CommandError(f"unknown button {arg!r}")
            await self._with_atv(lambda atv: getattr(atv.remote_control, BUTTONS[arg])())
            return {}
        if action == "launch":
            if not isinstance(arg, str) or not arg:
                raise CommandError("launch needs an app id")
            app = next((a["id"] for a in self._apps if arg in (a["id"], a["name"])), arg)
            await self._with_atv(lambda atv: atv.apps.launch_app(app))
            return {}
        if action == "volume":
            try:
                level = max(0, min(100, int(arg)))
            except (TypeError, ValueError):
                raise CommandError("volume needs a number from 0 to 100")
            await self._with_atv(lambda atv: atv.audio.set_volume(float(level)))
            return {}
        raise CommandError(f"Apple TV can't do {action!r}")

    async def close(self) -> None:
        await self._drop()


async def pair_interactive(ip: str, storage_file: str | Path, ask=input, say=print) -> None:
    """Pair Companion and AirPlay with the Apple TV, asking for the PIN it shows."""
    import pyatv
    from pyatv.const import Protocol
    from pyatv.storage.file_storage import FileStorage

    loop = asyncio.get_running_loop()
    storage = FileStorage(str(storage_file), loop)
    await storage.load()
    found = await pyatv.scan(loop, hosts=[ip], timeout=5, storage=storage)
    if not found:
        raise SystemExit(f"No Apple TV answered at {ip}. Is it on and on the same network?")
    conf = found[0]
    say(f"Found {conf.name}.")
    for name in PAIR_PROTOCOLS:
        protocol = getattr(Protocol, name)
        if not conf.get_service(protocol):
            say(f"{name}: not offered by this Apple TV, skipping.")
            continue
        handler = await pyatv.pair(conf, protocol, loop, storage=storage, name="Home Base")
        try:
            await handler.begin()
            if handler.device_provides_pin:
                handler.pin(ask(f"{name}: enter the PIN shown on the TV: ").strip())
            await handler.finish()
            say(f"{name}: {'paired' if handler.has_paired else 'pairing failed'}.")
        finally:
            await handler.close()
    await storage.save()
