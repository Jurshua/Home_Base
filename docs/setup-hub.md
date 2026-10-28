# Setting up the hub on the Mac Mini

1. Install Python 3.12 or newer if needed: `brew install python@3.12`.
2. Clone this repo, then run `hub/deploy/install-mac.sh`. The first run creates `~/Library/Application Support/HomeBase/hub.toml` and stops.
3. Open that file and fill in the LG TV's `ip` and `mac`. They're the `TV_IP` and `TV_MAC` lines at the top of `LG_Remote/remote.py`.
4. Optional, skips pairing: copy `LG_Remote/keys.sqlite` to `~/Library/Application Support/HomeBase/lg-keys.sqlite`.
5. Run `hub/deploy/install-mac.sh` again. It starts the hub as a background service that starts at login and restarts itself if it stops.
6. Open http://127.0.0.1:4900 for the test page. If it says **Needs pairing**, press **Pair** and then **Yes** on the TV within a minute.

If macOS asks whether Python may find devices on your local network, allow it, or the hub can't reach the TV.

Keep the TV's **Turn on via Wi-Fi** setting on, since power on is Wake-on-LAN. Giving the TV a fixed address in the router keeps the `ip` from changing.

**Logs:** `~/Library/Application Support/HomeBase/hub.log`. **Stop:** `launchctl bootout gui/$(id -u)/com.homebase.hub`. **Update:** `git pull`, then run the install script again.

The service runs while you're logged in, so set the Mac Mini to log in automatically (System Settings → Users & Groups) and to restart after a power failure (System Settings → Energy).

## Running it by hand while developing

```bash
cd hub
python3 -m venv .venv && .venv/bin/pip install -e '.[dev]'
.venv/bin/pytest                                     # tests use a fake TV, no hardware needed
.venv/bin/python -m homebase_hub --config hub.toml   # your own copy of hub.example.toml
```
