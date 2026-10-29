#!/usr/bin/env python3
"""Home Base helper for a computer (Mac or Windows). Python 3.9+, standard library only.

Lets the hub sleep or shut down this computer. Runs on port 4901 and only obeys
requests that carry the token in homebase-agent.json (created on first run).

    python3 homebase_agent.py           # run
    python3 homebase_agent.py --token   # print the token to paste into the hub's hub.toml
"""
import hmac
import json
import os
import platform
import secrets
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

VERSION = "0.1.0"
PORT = 4901
IS_MAC = sys.platform == "darwin"
IS_WINDOWS = sys.platform.startswith("win")

if IS_WINDOWS:
    CONFIG = Path(os.environ.get("APPDATA", Path.home())) / "HomeBase" / "homebase-agent.json"
else:
    CONFIG = Path.home() / "Library" / "Application Support" / "HomeBase" / "homebase-agent.json"

COMMANDS = {
    "darwin": {
        "sleep": ["pmset", "sleepnow"],
        "shutdown": ["osascript", "-e", 'tell application "System Events" to shut down'],
    },
    "win32": {
        # Sleeps when hibernation is off (powercfg /hibernate off); otherwise Windows hibernates.
        "sleep": ["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"],
        "shutdown": ["shutdown", "/s", "/t", "0"],
    },
}


def load_token() -> str:
    if CONFIG.exists():
        return json.loads(CONFIG.read_text())["token"]
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(24)
    CONFIG.write_text(json.dumps({"token": token}))
    if not IS_WINDOWS:
        CONFIG.chmod(0o600)
    return token


def os_name() -> str:
    return "macOS" if IS_MAC else "Windows" if IS_WINDOWS else platform.system()


def make_handler(token: str, run=subprocess.Popen, commands=None):
    commands = commands if commands is not None else COMMANDS.get("win32" if IS_WINDOWS else sys.platform, {})

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def send(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path == "/health":
                return self.send(200, {"ok": True, "os": os_name(), "version": VERSION, "host": platform.node()})
            self.send(404, {"error": "not found"})

        def do_POST(self):
            given = self.headers.get("Authorization", "").removeprefix("Bearer ")
            if not hmac.compare_digest(given.encode(), token.encode()):
                return self.send(401, {"error": "bad token"})
            if self.path != "/power":
                return self.send(404, {"error": "not found"})
            n = int(self.headers.get("Content-Length") or 0)
            try:
                action = json.loads(self.rfile.read(n) or b"{}").get("action")
            except ValueError:
                return self.send(400, {"error": "bad json"})
            cmd = commands.get(action)
            if not cmd:
                return self.send(400, {"error": f"can't {action!r} on {os_name()}"})
            self.send(200, {"ok": True, "did": action})
            # Answer first, then act, so the hub hears back before the network goes away.
            threading.Timer(1.0, lambda: run(cmd)).start()

    return Handler


def main():
    token = load_token()
    if "--token" in sys.argv:
        print(token)
        return
    print(f"Home Base helper {VERSION} on port {PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), make_handler(token)).serve_forever()


if __name__ == "__main__":
    main()
