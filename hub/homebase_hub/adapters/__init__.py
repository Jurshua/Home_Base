"""Builds adapters from the devices listed in hub.toml."""
from __future__ import annotations

from pathlib import Path

from ..config import DeviceConfig, HubConfig
from .base import Adapter, CommandError, DeviceStatus
from .fake import FakeTV
from .lg import LGTV

__all__ = ["Adapter", "CommandError", "DeviceStatus", "build"]


def build(dev: DeviceConfig, cfg: HubConfig) -> Adapter:
    o = dev.options
    if dev.kind == "lg_webos":
        return LGTV(dev.id, dev.name, ip=o["ip"], mac=o["mac"],
                    key_file=Path(o["key_file"]).expanduser() if o.get("key_file") else cfg.data_dir / f"{dev.id}-keys.sqlite")
    if dev.kind == "fake_tv":
        return FakeTV(dev.id, dev.name)
    raise ValueError(f"unknown device kind {dev.kind!r} for {dev.id!r}")
