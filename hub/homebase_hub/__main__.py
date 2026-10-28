"""Run the hub: python -m homebase_hub [--config path]."""
from __future__ import annotations

import argparse
import logging

import uvicorn

from . import config
from .app import create_app, make_hub


def main() -> None:
    p = argparse.ArgumentParser(prog="homebase-hub")
    p.add_argument("--config", help="path to hub.toml (default: ~/Library/Application Support/HomeBase/hub.toml)")
    args = p.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    cfg = config.load(args.config)
    uvicorn.run(create_app(make_hub(cfg)), host=cfg.host, port=cfg.port, log_level="info")


if __name__ == "__main__":
    main()
