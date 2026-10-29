"""Run the hub: python -m homebase_hub [--config path]
Pair an Apple TV once: python -m homebase_hub pair-appletv <device id> [--config path]"""
from __future__ import annotations

import argparse
import asyncio
import logging

import uvicorn

from . import config
from .app import create_app, make_hub


def main() -> None:
    p = argparse.ArgumentParser(prog="homebase-hub")
    p.add_argument("--config", help="path to hub.toml (default: ~/Library/Application Support/HomeBase/hub.toml)")
    p.add_argument("command", nargs="?", choices=["serve", "pair-appletv"], default="serve")
    p.add_argument("device", nargs="?", help="device id, for pair-appletv")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    cfg = config.load(args.config)
    if args.command == "pair-appletv":
        return pair_appletv(cfg, args.device)
    uvicorn.run(create_app(make_hub(cfg)), host=cfg.host, port=cfg.port, log_level="info")


def pair_appletv(cfg: config.HubConfig, device_id: str | None) -> None:
    from .adapters.appletv import pair_interactive, storage_path

    tvs = [d for d in cfg.devices if d.kind == "apple_tv" and (device_id in (None, d.id))]
    if not tvs:
        raise SystemExit("No matching apple_tv device in hub.toml")
    cfg.data_dir.mkdir(parents=True, exist_ok=True)
    asyncio.run(pair_interactive(tvs[0].options["ip"], storage_path(cfg.data_dir)))
    print("Done. Restart the hub (run install-mac.sh again) so it picks up the new pairing.")


if __name__ == "__main__":
    main()
