from fastapi.testclient import TestClient

from homebase_hub.adapters.fake import FakeTV
from homebase_hub.app import create_app
from homebase_hub.hub import History, Hub


def client(tmp_path):
    hub = Hub([FakeTV("tv", "Test TV")], History(tmp_path / "h.sqlite"))
    return TestClient(create_app(hub, poll=False)), hub


def test_health_and_devices(tmp_path):
    c, _ = client(tmp_path)
    with c:
        assert c.get("/api/health").json()["devices"] == 1
        d = c.get("/api/devices").json()[0]
        assert d["id"] == "tv" and "button" in d["actions"]


def test_command_over_http_is_logged(tmp_path):
    c, hub = client(tmp_path)
    with c:
        assert c.post("/api/devices/tv/power_on", json={"source": "pytest"}).status_code == 200
        assert c.post("/api/devices/tv/button", json={"arg": "UP"}).status_code == 200
        assert hub.adapters["tv"].pressed == ["UP"]
        h = c.get("/api/history").json()
        assert [r["action"] for r in h] == ["button", "power_on"] and h[1]["source"] == "pytest"


def test_errors(tmp_path):
    c, _ = client(tmp_path)
    with c:
        assert c.post("/api/devices/nope/power_on").status_code == 404
        assert c.post("/api/devices/tv/fly").status_code == 400
        assert c.post("/api/devices/tv/button", json={"arg": "UP"}).status_code == 400  # TV is off


def test_live_socket_syncs_every_listener(tmp_path):
    c, _ = client(tmp_path)
    with c, c.websocket_connect("/api/live") as a, c.websocket_connect("/api/live") as b:
        assert a.receive_json()["type"] == "snapshot" and b.receive_json()["type"] == "snapshot"
        a.send_json({"type": "command", "id": "1", "device": "tv", "action": "power_on"})
        seen_a = [a.receive_json() for _ in range(2)]
        assert {m["type"] for m in seen_a} == {"event", "result"}
        ev = b.receive_json()  # the other app hears about it too
        assert ev["type"] == "event" and ev["event"]["action"] == "power_on"
        c.post("/api/devices/tv/refresh")
        msg = b.receive_json()
        while msg["type"] != "device":
            msg = b.receive_json()
        assert msg["device"]["power"] == "on"


def test_power_on_keeps_checking_until_on(tmp_path):
    import asyncio

    from homebase_hub.adapters.base import DeviceStatus

    class SlowTV(FakeTV):
        checks = 0

        async def status(self):
            self.checks += 1
            on = self.on and self.checks >= 3  # takes a few checks to wake up
            return DeviceStatus(power="on" if on else "off", reachable=on)

    hub = Hub([SlowTV("tv", "Slow TV")], History(tmp_path / "h.sqlite"))
    hub.settle_interval = 0.01

    async def go():
        await hub.command("tv", "power_on")
        for _ in range(300):
            await asyncio.sleep(0.01)
            if hub.state["tv"]["power"] == "on":
                return True
        return False
    assert asyncio.run(go())
