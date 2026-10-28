# Hub protocol (v1)

Every app talks to the hub on the Mac Mini, port 4900. Device ids come from `hub.toml` (for example `lg`).

## Device object

```json
{
  "id": "lg", "name": "LG TV", "kind": "lg_webos",
  "actions": ["power_on", "power_off", "button", "launch", "input", "volume", "mute"],
  "apps":   [{"name": "Netflix", "id": "netflix"}],
  "inputs": [{"name": "HDMI 1", "id": "com.webos.app.hdmi1"}],
  "buttons": ["UP", "DOWN", "LEFT", "RIGHT", "ENTER", "BACK", "HOME", "..."],
  "power": "on | off | unknown",
  "reachable": true,
  "needs_pairing": false,
  "detail": {"app": "netflix", "volume": 12, "muted": false},
  "updated": 1761620000.0
}
```

`apps`, `inputs` and `buttons` appear only on devices that support them.

`power` is the device's real state: a TV in standby still answers on the network (`reachable: true`) but reports `"off"`. When `needs_pairing` is true the hub has no working key for the device: `power` is `"unknown"`, other commands are refused, and the app should offer the `pair` action. The hub never starts pairing on its own, so the TV's prompt only appears when someone asks for it.

## Live connection: `ws://<hub>:4900/api/live`

The hub sends, as JSON text frames:

| `type` | When | Body |
| --- | --- | --- |
| `snapshot` | Right after connecting | `devices`: every device object |
| `device` | A device's power, reachability or detail changed | `device`: the full device object |
| `event` | Any app ran a command | `event`: `{ts, device, action, arg, source, ok, error}` |
| `result` | Reply to your own command | `id`, `ok`, and `result` or `error` |

Apps send commands:

```json
{"type": "command", "id": "42", "device": "lg", "action": "button", "arg": "UP", "source": "Josh's iPhone"}
```

Actions and their `arg`:

| Action | `arg` |
| --- | --- |
| `power_on`, `power_off` | none. After either, the hub keeps checking for up to 20 s and sends a `device` update once the power state matches |
| `pair` | none. Shows the Yes/No prompt on the TV and waits up to 60 s |
| `button` | one of the device's `buttons` |
| `launch` | an app id |
| `input` | an input id or name (`"HDMI 2"`) |
| `volume` | 0 to 100 |
| `mute` | true or false |

## HTTP

| Method and path | What it does |
| --- | --- |
| `GET /api/health` | `{ok, version, devices}` |
| `GET /api/devices` | List of device objects |
| `GET /api/devices/{id}` | One device |
| `POST /api/devices/{id}/{action}` | Run a command. Body `{"arg": ..., "source": ...}`. 400 bad command, 404 unknown device, 502 device didn't respond |
| `POST /api/devices/{id}/refresh` | Check the device now instead of waiting for the next poll |
| `GET /api/history?limit=50` | Recent commands, newest first |

No pairing yet: the hub listens only on the Mac Mini itself until milestone 3 adds per-device keys.
