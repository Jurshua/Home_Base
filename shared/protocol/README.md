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
  "detail": {"app": "netflix", "volume": 12, "muted": false},
  "updated": 1761620000.0
}
```

`apps`, `inputs` and `buttons` appear only on devices that support them.

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
| `power_on`, `power_off` | none |
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
