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

`apps`, `inputs` and `buttons` appear only on devices that support them. Sony and Apple TV learn their app list after the first connection, so `apps` can grow in a later `device` message.

Device kinds: `lg_webos`, `sony_bravia`, `apple_tv`, `computer`, `hue_bridge`. Each lists the actions it supports in `actions`; a computer has none until it has a MAC address (for `power_on`) or a helper token (for `power_off`, `sleep`, `shutdown`). Apple TV buttons add `PLAYPAUSE`, `NEXT` and `PREVIOUS`.

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
| `pair` | none. LG only: shows the Yes/No prompt on the TV and waits up to 60 s |
| `room` | Hue only: `{"room": <room id or name>, "on": true/false, "brightness": 0-100}`. Either field can be left out; brightness 0 turns the room off |
| `scene` | Hue only: a scene id, a scene name, or `{"room": <room>, "scene": <name>}` when two rooms share a scene name |
| `sleep`, `shutdown` | none. Computers only. `power_off` does whichever the computer's `off_action` says |
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

| `GET /api/me` | Who the hub thinks you are: `{name, id, local}` |

## Finding the hub and pairing

**Finding it.** The hub announces itself with Bonjour as `_homebase._tcp` on port 4900 (TXT `version`, `api`). Browse for that service (`NWBrowser` on Apple platforms) instead of asking for an address; keep a manual address field as a fallback. `GET /api/health` answers without a key, so an app can check it found a hub.

**Who needs a key.** Anything on the Mac Mini itself (`127.0.0.1`) is trusted and needs nothing. Every other device pairs once and then sends its key on every request:

- HTTP: `Authorization: Bearer <token>`
- Live connection: the same header, or `ws://<hub>:4900/api/live?token=<token>`

Without a valid key the hub answers `401` (HTTP) or closes the live connection with code `4401`. The same `4401` close happens to an open connection when its device is removed. On either, the app should forget its key and show the pairing screen. The test page (`/`), `/api/health` and `/api/pair` are the only things open without a key.

**Pairing a new device.**

1. On a device that's already trusted (the Mac Mini, or any paired device), `POST /api/pairing-codes` returns `{"code": "123456", "expires": <unix time>}`. Show the code big; it works once and for 5 minutes.
2. On the new device, the person types the code. The app sends `POST /api/pair` with `{"code": "123456", "name": "Josh's iPhone"}` and gets back `{"token": "...", "client": {"id", "name", "created", "last_seen"}}`.
3. Keep the token in the Keychain. It doesn't expire; it stops working only when the device is removed.

`/api/pair` errors: `400` no name, `403` wrong or expired code, `429` too many wrong codes from this address (wait 5 minutes). After 10 wrong guesses in total, open codes stop working and a new one is needed.

**Managing devices.** `GET /api/clients` lists paired devices (`id`, `name`, `created`, `last_seen`). `DELETE /api/clients/{id}` removes one and cuts off its open connections.

**History names.** Commands from a paired device are logged under that device's name, whatever `source` it sends. Only the Mac Mini's own apps set `source` freely.

## Hue lights

A `hue_bridge` device's `detail` holds the rooms and the bridge's own scenes:

```json
{
  "rooms":  [{"id": "…", "name": "Living room", "kind": "room", "on": true, "brightness": 40, "group": "…"}],
  "scenes": [{"id": "…", "name": "Movie", "room": "<room id>", "active": true}]
}
```

`kind` is `room` or `zone`. `power` is `on` when any room is on; `power_on` and `power_off` switch every light. Until it's paired, the only action is `pair` (press the bridge's button first). Changes made in the Hue app or with a switch reach the hub through the bridge's event stream, so apps get a `device` message within a second.
