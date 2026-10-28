import asyncio
import json

import httpx
import pytest

from homebase_hub.adapters import CommandError
from homebase_hub.adapters.hue import HueBridge

KEY = "abc123"


class FakeBridge:
    """Answers like a Hue Bridge's v2 API."""

    def __init__(self, button_pressed=True):
        self.button_pressed = button_pressed
        self.puts = []
        self.groups = {
            "g-home": {"id": "g-home", "owner": {"rtype": "bridge_home"}, "on": {"on": True}, "dimming": {"brightness": 40}},
            "g-living": {"id": "g-living", "owner": {"rtype": "room"}, "on": {"on": True}, "dimming": {"brightness": 40.4}},
            "g-bed": {"id": "g-bed", "owner": {"rtype": "room"}, "on": {"on": False}, "dimming": {"brightness": 0}},
        }

    def __call__(self, req: httpx.Request) -> httpx.Response:
        path = req.url.path
        if path == "/api" and req.method == "POST":
            if not self.button_pressed:
                return httpx.Response(200, json=[{"error": {"type": 101, "description": "link button not pressed"}}])
            return httpx.Response(200, json=[{"success": {"username": KEY, "clientkey": "ck"}}])
        if path == "/api/config":
            return httpx.Response(200, json={"name": "Hue Bridge"})
        if req.headers.get("hue-application-key") != KEY:
            return httpx.Response(403)
        kind = path.split("/")[4]
        if req.method == "PUT":
            rid = path.split("/")[5]
            self.puts.append((kind, rid, json.loads(req.content)))
            return httpx.Response(200, json={"data": [{"rid": rid}]})
        data = {
            "room": [{"id": "r-living", "metadata": {"name": "Living room"}, "services": [{"rid": "g-living", "rtype": "grouped_light"}]},
                     {"id": "r-bed", "metadata": {"name": "Bedroom"}, "services": [{"rid": "g-bed", "rtype": "grouped_light"}]}],
            "zone": [],
            "grouped_light": list(self.groups.values()),
            "scene": [{"id": "s-movie", "metadata": {"name": "Movie"}, "group": {"rid": "r-living"}, "status": {"active": "static"}},
                      {"id": "s-read", "metadata": {"name": "Read"}, "group": {"rid": "r-living"}, "status": {"active": "inactive"}},
                      {"id": "s-read2", "metadata": {"name": "Read"}, "group": {"rid": "r-bed"}, "status": {"active": "inactive"}}],
        }[kind]
        return httpx.Response(200, json={"data": data})


def make(tmp_path, bridge=None, paired=True):
    bridge = bridge or FakeBridge()
    key_file = tmp_path / "hue-hue.json"
    if paired:
        key_file.write_text(json.dumps({"app_key": KEY}))
    return HueBridge("hue", "Lights", ip="10.0.0.9", key_file=key_file, transport=httpx.MockTransport(bridge)), bridge


async def test_unpaired_then_pair(tmp_path):
    hue, bridge = make(tmp_path, FakeBridge(button_pressed=False), paired=False)
    st = await hue.status()
    assert st.needs_pairing and st.reachable and hue.actions() == ["pair"]
    with pytest.raises(CommandError, match="round button"):
        await hue.command("pair")
    bridge.button_pressed = True
    await hue.command("pair")
    assert json.loads((tmp_path / "hue-hue.json").read_text())["app_key"] == KEY
    st = await hue.status()
    assert not st.needs_pairing and "scene" in hue.actions()


async def test_status_lists_rooms_and_scenes(tmp_path):
    hue, _ = make(tmp_path)
    st = await hue.status()
    assert st.power == "on"
    assert st.detail["rooms"][0] == {"id": "r-living", "name": "Living room", "kind": "room", "on": True,
                                     "brightness": 40, "group": "g-living"}
    assert [s["name"] for s in st.detail["scenes"] if s["active"]] == ["Movie"]


async def test_room_brightness_and_off(tmp_path):
    hue, bridge = make(tmp_path)
    await hue.command("room", {"room": "Bedroom", "brightness": 30})
    await hue.command("room", {"room": "r-living", "on": False})
    await hue.command("room", {"room": "Living room", "brightness": 0})
    assert bridge.puts == [
        ("grouped_light", "g-bed", {"on": {"on": True}, "dimming": {"brightness": 30.0}}),
        ("grouped_light", "g-living", {"on": {"on": False}}),
        ("grouped_light", "g-living", {"on": {"on": False}}),
    ]


async def test_scenes_by_id_name_and_room(tmp_path):
    hue, bridge = make(tmp_path)
    await hue.command("scene", "Movie")
    with pytest.raises(CommandError, match="more than one"):
        await hue.command("scene", "Read")
    await hue.command("scene", {"room": "Bedroom", "scene": "Read"})
    await hue.command("scene", "s-read")
    assert [p[1] for p in bridge.puts] == ["s-movie", "s-read2", "s-read"]
    assert bridge.puts[0][2] == {"recall": {"action": "active"}}


async def test_all_off_uses_whole_home_group(tmp_path):
    hue, bridge = make(tmp_path)
    await hue.command("power_off")
    assert bridge.puts == [("grouped_light", "g-home", {"on": {"on": False}})]


async def test_bad_room_args(tmp_path):
    hue, _ = make(tmp_path)
    with pytest.raises(CommandError):
        await hue.command("room", "Bedroom")
    with pytest.raises(CommandError, match="no room"):
        await hue.command("room", {"room": "Garage", "on": True})


async def test_event_stream_triggers_refresh(tmp_path):
    def stream(req):
        if req.url.path == "/eventstream/clip/v2":
            body = b'id: 1\ndata: [{"type":"update"}]\n\n'
            return httpx.Response(200, content=body, headers={"content-type": "text/event-stream"})
        return FakeBridge()(req)
    hue = HueBridge("hue", "Lights", ip="10.0.0.9", key_file=tmp_path / "k.json", transport=httpx.MockTransport(stream))
    hue._key = KEY
    calls = []

    async def changed():
        calls.append(1)
    await hue.watch(changed)
    await asyncio.sleep(0.4)
    assert calls == [1]
