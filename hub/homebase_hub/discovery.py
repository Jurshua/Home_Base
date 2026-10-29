"""Announce the hub on the home network (Bonjour), so the apps find it without anyone typing an address."""
from __future__ import annotations

import logging
import socket

from . import __version__

log = logging.getLogger("homebase.discovery")
SERVICE = "_homebase._tcp.local."


def lan_addresses() -> list[str]:
    import ifaddr

    found = []
    for adapter in ifaddr.get_adapters():
        for ip in adapter.ips:
            if isinstance(ip.ip, str) and not ip.ip.startswith(("127.", "169.254.")):
                found.append(ip.ip)
    return found


class Announcer:
    def __init__(self, port: int, name: str | None = None):
        self.port = port
        self.name = name or "Home Base on " + socket.gethostname().split(".")[0]
        self._zc = None
        self._info = None

    async def start(self) -> None:
        try:
            from zeroconf import ServiceInfo
            from zeroconf.asyncio import AsyncZeroconf

            addrs = lan_addresses()
            if not addrs:
                log.warning("no network address found, so the hub isn't announcing itself")
                return
            self._info = ServiceInfo(
                SERVICE, f"{self.name}.{SERVICE}", port=self.port,
                properties={"version": __version__, "api": "1"},
                server=socket.gethostname().split(".")[0] + ".local.",
                addresses=[socket.inet_aton(a) for a in addrs])
            self._zc = AsyncZeroconf()
            await self._zc.async_register_service(self._info, allow_name_change=True)
            log.info("announcing %s on %s port %s", self.name, ", ".join(addrs), self.port)
        except Exception:
            log.exception("couldn't announce the hub on the network; apps can still connect by address")
            self._zc = None

    async def stop(self) -> None:
        if self._zc:
            try:
                await self._zc.async_unregister_service(self._info)
            finally:
                await self._zc.async_close()
            self._zc = None
