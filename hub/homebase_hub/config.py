"""Hub settings, read from one TOML file.

Default location is ~/Library/Application Support/HomeBase/hub.toml; set
HOMEBASE_CONFIG to use another file. See hub/hub.example.toml.
"""
from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_DATA_DIR = Path.home() / "Library" / "Application Support" / "HomeBase"


@dataclass
class DeviceConfig:
    id: str
    kind: str
    name: str
    options: dict = field(default_factory=dict)


@dataclass
class HubConfig:
    host: str = "127.0.0.1"
    port: int = 4900
    data_dir: Path = DEFAULT_DATA_DIR
    poll_seconds: float = 5.0
    devices: list[DeviceConfig] = field(default_factory=list)


def load(path: str | os.PathLike | None = None) -> HubConfig:
    path = Path(path or os.environ.get("HOMEBASE_CONFIG") or DEFAULT_DATA_DIR / "hub.toml").expanduser()
    raw = tomllib.loads(path.read_text()) if path.exists() else {}
    hub = raw.get("hub", {})
    devices = []
    for d in raw.get("devices", []):
        d = dict(d)
        devices.append(DeviceConfig(id=d.pop("id"), kind=d.pop("kind"), name=d.pop("name", ""), options=d))
    return HubConfig(
        host=hub.get("host", "127.0.0.1"),
        port=int(hub.get("port", 4900)),
        data_dir=Path(hub.get("data_dir", DEFAULT_DATA_DIR)).expanduser(),
        poll_seconds=float(hub.get("poll_seconds", 5.0)),
        devices=devices,
    )
