# Adding the Sony TV, Apple TV and computers

All devices go in `~/Library/Application Support/HomeBase/hub.toml` on the Mac Mini (see `hub/hub.example.toml`). After editing it, run `hub/deploy/install-mac.sh` again to restart the hub. Giving every device a fixed address in the router keeps the `ip` values from changing.

## Sony TV

1. On the TV: **Settings → Network & Internet → Home network → IP control** (menu names vary a little by model).
   - **Authentication**: Normal and Pre-Shared Key.
   - **Pre-Shared Key**: pick something, like a short password.
   - **Simple IP control**: on. **Remote start**: on, so the hub can turn it on.
2. Find the TV's IP under **Network → Advanced settings → Network status**.
3. In `hub.toml`, set the `sony` device's `ip`, and `psk` to that key.

If the test page says **Needs pairing** for the Sony, the key in `hub.toml` doesn't match the TV.

## Apple TV

1. Set its `ip` in `hub.toml` (Apple TV: **Settings → Network**).
2. On the Mac Mini, pair once:
   ```bash
   "$HOME/Library/Application Support/HomeBase/venv/bin/python" -m homebase_hub pair-appletv appletv
   ```
   The TV shows a PIN twice: once for control and apps, once for the remote and what's playing. Type each one in.
3. Run `hub/deploy/install-mac.sh` again so the hub picks up the pairing.

With **Control TVs and Receivers** on in the Apple TV's settings and Bravia Sync (HDMI-CEC) on in the Sony, turning the Apple TV on from the hub also turns on the Sony and switches it to the Apple TV.

## Computers

Turning a computer **on** is Wake-on-LAN, so the hub needs its MAC address. Turning it **off** (sleep or shut down) goes through a small helper running on that computer. The Mac and Windows apps will take this over later.

### Gaming PC (Windows)

1. Install Python if it isn't there: `winget install Python.Python.3.12`.
2. Copy the `hub/agent` folder to the PC. Open PowerShell **as Administrator**, go to that folder and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File install-agent-windows.ps1
   ```
   It starts the helper at every login, opens port 4901 on private networks, and prints a **token**.
3. In `hub.toml`, set the `pc` device's `ip`, `mac` (from `ipconfig /all`, "Physical Address" of the Wi-Fi adapter) and `token`.
4. Make sure the home Wi-Fi is set to **Private** on the PC (Settings → Network & internet → Wi-Fi → your network).

Waking a PC over Wi-Fi is unreliable on many Wi-Fi adapters. If **Turn on** doesn't work:

- Enable **Wake on Magic Packet** in Device Manager → the Wi-Fi adapter → Advanced, and **Allow this device to wake the computer** on its Power Management tab.
- Use `off_action = "sleep"`, not shutdown. Waking from sleep is far more reliable than from off.
- Windows hibernates instead of sleeping when hibernation is on. Run `powercfg /hibernate off` as Administrator for true sleep.

### MacBook Air

1. Copy the `hub/agent` folder to the MacBook Air and run `./install-agent-mac.sh`. It prints a **token**.
2. In `hub.toml`, set the `air` device's `ip`, `mac` (System Settings → Network → Wi-Fi → Details → Hardware) and `token`.

A MacBook Air's Wi-Fi only wakes for the network while it's on power with **Wake for network access** on (System Settings → Battery → Options). Asleep on battery, it won't wake remotely.

### Mac Mini

The Mac Mini runs the hub, so it's listed with `ip = "127.0.0.1"` and `can_turn_off = false`, and always shows as on.
