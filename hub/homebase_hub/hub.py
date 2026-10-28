"""The hub core: holds every device's live state, runs commands, and tells listeners."""
from __future__ import annotations

import asyncio
import json
import logging
import sqlite3
import time
from pathlib import Path
from typing import Any

from .adapters import Adapter, CommandError

log = logging.getLogger("homebase.hub")


class History:
    """Every command, who sent it and whether it worked, in a small SQLite file."""

    def __init__(self, path: Path | str):
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.execute(
            "CREATE TABLE IF NOT EXISTS history (ts REAL, device TEXT, action TEXT, arg TEXT, source TEXT, ok INTEGER, error TEXT)")
        self.db.commit()

    def add(self, device: str, action: str, arg: Any, source: str, ok: bool, error: str | None) -> dict:
        row = {"ts": time.time(), "device": device, "action": action, "arg": arg, "source": source, "ok": ok, "error": error}
        self.db.execute("INSERT INTO history VALUES (?,?,?,?,?,?,?)",
                        (row["ts"], device, action, json.dumps(arg), source, int(ok), error))
        self.db.commit()
        return row

    def recent(self, limit: int = 50) -> list[dict]:
        cur = self.db.execute(
            "SELECT ts, device, action, arg, source, ok, error FROM history ORDER BY ts DESC LIMIT ?", (limit,))
        return [{"ts": ts, "device": d, "action": a, "arg": json.loads(arg), "source": s, "ok": bool(ok), "error": e}
                for ts, d, a, arg, s, ok, e in cur.fetchall()]

    def close(self) -> None:
        self.db.close()


class Hub:
    def __init__(self, adapters: list[Adapter], history: History, poll_seconds: float = 5.0):
        self.adapters = {a.id: a for a in adapters}
        self.history = history
        self.poll_seconds = poll_seconds
        self.state: dict[str, dict] = {
            a.id: {**a.describe(), "power": "unknown", "reachable": False, "needs_pairing": False,
                   "detail": {}, "updated": None}
            for a in adapters}
        self._listeners: set[asyncio.Queue] = set()
        self._poller: asyncio.Task | None = None
        self._tasks: set[asyncio.Task] = set()
        self.settle_interval = 1.0

    # ---- listeners (each open app connection gets a queue) ----
    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self._listeners.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self._listeners.discard(q)

    def _publish(self, msg: dict) -> None:
        for q in list(self._listeners):
            try:
                q.put_nowait(msg)
            except asyncio.QueueFull:  # a stuck client should not hold up everyone else
                self._listeners.discard(q)

    def snapshot(self) -> list[dict]:
        return list(self.state.values())

    # ---- state ----
    async def refresh(self, device_id: str) -> dict:
        a = self.adapters[device_id]
        st = await a.status()
        cur = self.state[device_id]
        new = {**cur, "power": st.power, "reachable": st.reachable, "needs_pairing": st.needs_pairing, "detail": st.detail}
        changed = any(new[k] != cur[k] for k in ("power", "reachable", "needs_pairing", "detail"))
        new["updated"] = time.time()
        self.state[device_id] = new
        if changed:
            self._publish({"type": "device", "device": new})
        return new

    async def refresh_all(self) -> None:
        await asyncio.gather(*(self.refresh(i) for i in self.adapters), return_exceptions=True)

    async def _poll_forever(self) -> None:
        while True:
            try:
                await self.refresh_all()
            except Exception:
                log.exception("poll failed")
            await asyncio.sleep(self.poll_seconds)

    def start(self) -> None:
        if self._poller is None:
            self._poller = asyncio.create_task(self._poll_forever())

    async def stop(self) -> None:
        if self._poller:
            self._poller.cancel()
            try:
                await self._poller
            except asyncio.CancelledError:
                pass
            self._poller = None
        for t in list(self._tasks):
            t.cancel()
        for a in self.adapters.values():
            await a.close()
        self.history.close()

    # ---- commands ----
    async def command(self, device_id: str, action: str, arg: Any = None, source: str = "unknown") -> dict:
        if device_id not in self.adapters:
            raise KeyError(device_id)
        a = self.adapters[device_id]
        if action not in a.actions():
            raise CommandError(f"{a.name} can't do {action!r}")
        try:
            result = await a.command(action, arg)
        except Exception as e:
            self._publish({"type": "event", "event": self.history.add(device_id, action, arg, source, False, str(e)[:200])})
            raise
        self._publish({"type": "event", "event": self.history.add(device_id, action, arg, source, True, None)})
        # Show the change quickly. Power changes take a few seconds, so keep checking until the device gets there.
        target = {"power_on": "on", "power_off": "off"}.get(action)
        self._spawn(self._settle(device_id, target))
        return result

    def _spawn(self, coro) -> None:
        t = asyncio.create_task(coro)
        self._tasks.add(t)
        t.add_done_callback(self._tasks.discard)

    async def _settle(self, device_id: str, target: str | None, timeout: float = 20.0) -> None:
        try:
            await asyncio.sleep(0.8)
            st = await self.refresh(device_id)
            deadline = asyncio.get_running_loop().time() + timeout
            while target and st["power"] != target and asyncio.get_running_loop().time() < deadline:
                await asyncio.sleep(self.settle_interval)
                st = await self.refresh(device_id)
        except Exception:
            log.exception("refresh after command failed")
