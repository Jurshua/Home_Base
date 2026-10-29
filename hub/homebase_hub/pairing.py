"""Which apps may use the hub.

Anything running on the Mac Mini itself is trusted. Every other device pairs once: someone already
trusted makes a 6-digit code, the new device sends it back with its name, and gets a key of its own.
Only a hash of each key is stored, and any device can be removed from the list to cut it off.
"""
from __future__ import annotations

import hashlib
import secrets
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path

CODE_SECONDS = 300
MAX_TRIES_PER_CODE = 10       # wrong guesses before a code stops working
MAX_FAILS_PER_ADDRESS = 5     # wrong guesses from one address per window
FAIL_WINDOW = 300


class PairingError(Exception):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


@dataclass
class Caller:
    name: str
    client_id: str | None = None  # None means the hub's own Mac

    @property
    def local(self) -> bool:
        return self.client_id is None


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class Clients:
    def __init__(self, path: Path | str, clock=time.time):
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.execute("CREATE TABLE IF NOT EXISTS clients (id TEXT PRIMARY KEY, name TEXT, token_hash TEXT UNIQUE,"
                        " created REAL, last_seen REAL)")
        self.db.commit()
        self.clock = clock
        self._codes: dict[str, dict] = {}       # code -> {expires, tries, by}
        self._fails: dict[str, list[float]] = {}

    # ---- codes ----
    def new_code(self, by: str) -> dict:
        self._drop_expired()
        code = f"{secrets.randbelow(1_000_000):06d}"
        while code in self._codes:
            code = f"{secrets.randbelow(1_000_000):06d}"
        expires = self.clock() + CODE_SECONDS
        self._codes[code] = {"expires": expires, "tries": 0, "by": by}
        return {"code": code, "expires": expires}

    def pair(self, code: str, name: str, address: str) -> dict:
        now = self.clock()
        recent = [t for t in self._fails.get(address, []) if now - t < FAIL_WINDOW]
        if len(recent) >= MAX_FAILS_PER_ADDRESS:
            raise PairingError("Too many wrong codes. Wait a few minutes and try again", 429)
        self._drop_expired()
        name = " ".join(str(name or "").split())[:60]
        if not name:
            raise PairingError("Give this device a name, like \"Josh's iPhone\"")
        entry = self._codes.get(str(code).strip())
        if entry is None:
            self._fails[address] = recent + [now]
            for e in self._codes.values():  # a guess counts against every live code
                e["tries"] += 1
            self._codes = {c: e for c, e in self._codes.items() if e["tries"] < MAX_TRIES_PER_CODE}
            raise PairingError("That code didn't work. Make a new one on a device that's already set up", 403)
        del self._codes[str(code).strip()]
        token = secrets.token_urlsafe(32)
        cid = secrets.token_hex(4)
        self.db.execute("INSERT INTO clients VALUES (?,?,?,?,?)", (cid, name, _hash(token), now, now))
        self.db.commit()
        return {"token": token, "client": {"id": cid, "name": name, "created": now, "last_seen": now}}

    def _drop_expired(self) -> None:
        now = self.clock()
        self._codes = {c: e for c, e in self._codes.items() if e["expires"] > now}

    # ---- keys ----
    def check(self, token: str | None) -> Caller | None:
        if not token:
            return None
        row = self.db.execute("SELECT id, name, last_seen FROM clients WHERE token_hash = ?", (_hash(token),)).fetchone()
        if not row:
            return None
        cid, name, last_seen = row
        now = self.clock()
        if now - (last_seen or 0) > 60:  # no need to write on every request
            self.db.execute("UPDATE clients SET last_seen = ? WHERE id = ?", (now, cid))
            self.db.commit()
        return Caller(name=name, client_id=cid)

    def list(self) -> list[dict]:
        cur = self.db.execute("SELECT id, name, created, last_seen FROM clients ORDER BY created")
        return [{"id": i, "name": n, "created": c, "last_seen": s} for i, n, c, s in cur.fetchall()]

    def remove(self, client_id: str) -> bool:
        cur = self.db.execute("DELETE FROM clients WHERE id = ?", (client_id,))
        self.db.commit()
        return cur.rowcount > 0

    def close(self) -> None:
        self.db.close()


def bearer(header: str | None) -> str | None:
    if header and header.lower().startswith("bearer "):
        return header[7:].strip() or None
    return None
