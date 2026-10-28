"""Builds adapters from the devices listed in hub.toml."""
from __future__ import annotations

from pathlib import Path

from ..config import DeviceConfig, HubConfig
from .base import Adapter, CommandError, DeviceStatus
from .appletv import AppleTV, storage_path
from .computer import Computer
from .fake import FakeTV
from .lg import LGTV
from .sony import SonyTV

__all__ = ["Adapter", "CommandError", "DeviceStatus", "build"]


def build(dev: DeviceConfig, cfg: HubConfig) -> Adapter:
    o = dev.options
    if dev.kind == "lg_webos":
        return LGTV(dev.id, dev.name, ip=o["ip"], mac=o["mac"],
                    key_file=Path(o["key_file"]).expanduser() if o.get("key_file") else cfg.data_dir / f"{dev.id}-keys.sqlite")
    if dev.kind == "sony_bravia":
        return SonyTV(dev.id, dev.name, ip=o["ip"], psk=o["psk"], mac=o.get("mac"))
    if dev.kind == "apple_tv":
        return AppleTV(dev.id, dev.name, ip=o["ip"], storage_file=storage_path(cfg.data_dir))
    if dev.kind == "computer":
        return Computer(dev.id, dev.name, ip=o["ip"], mac=o.get("mac"), token=o.get("token"),
                        off_action=o.get("off_action", "sleep"), can_turn_off=o.get("can_turn_off", True))
    if dev.kind == "fake_tv":
        return FakeTV(dev.id, dev.name)
    raise ValueError(f"unknown device kind {dev.kind!r} for {dev.id!r}")
