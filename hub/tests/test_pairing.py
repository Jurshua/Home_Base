import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from homebase_hub.adapters.fake import FakeTV
from homebase_hub.app import create_app
from homebase_hub.hub import History, Hub
from homebase_hub.pairing import Clients, PairingError


def setup(tmp_path, clock=None):
    clients = Clients(tmp_path / "h.sqlite", **({"clock": clock} if clock else {}))
    hub = Hub([FakeTV("tv", "Test TV")], History(tmp_path / "h.sqlite"))
    app = create_app(hub, poll=False, clients=clients, local_hosts=frozenset({"10.0.0.1"}))
    mini = TestClient(app, client=("10.0.0.1", 1))       # the hub's own Mac
    phone = TestClient(app, client=("10.0.0.20", 1))     # another device on the network
    return mini, phone, hub


def pair(mini, phone, name="Josh's iPhone"):
    code = mini.post("/api/pairing-codes").json()["code"]
    r = phone.post("/api/pair", json={"code": code, "name": name})
    assert r.status_code == 200, r.text
    return r.json()


def test_unpaired_device_is_turned_away(tmp_path):
    mini, phone, _ = setup(tmp_path)
    assert phone.get("/api/health").status_code == 200  # so an app can tell it found a hub
    assert phone.get("/").status_code == 200
    for path in ("/api/devices", "/api/history", "/api/clients"):
        assert phone.get(path).status_code == 401
    assert phone.post("/api/devices/tv/power_on").status_code == 401
    assert phone.post("/api/pairing-codes").status_code == 401
    assert phone.get("/api/devices", headers={"Authorization": "Bearer made-up"}).status_code == 401
    with pytest.raises(WebSocketDisconnect) as e, phone.websocket_connect("/api/live") as ws:
        ws.receive_json()
    assert e.value.code == 4401
    assert mini.get("/api/devices").status_code == 200


def test_pair_then_use_the_key(tmp_path):
    mini, phone, hub = setup(tmp_path)
    got = pair(mini, phone)
    auth = {"Authorization": "Bearer " + got["token"]}
    assert phone.get("/api/me", headers=auth).json() == {"name": "Josh's iPhone", "id": got["client"]["id"], "local": False}
    # the history names the paired device, whatever source it claims
    assert phone.post("/api/devices/tv/power_on", headers=auth, json={"source": "someone else"}).status_code == 200
    assert hub.history.recent(1)[0]["source"] == "Josh's iPhone"
    with phone.websocket_connect("/api/live?token=" + got["token"]) as ws:
        assert ws.receive_json()["type"] == "snapshot"
        ws.send_json({"type": "command", "id": "1", "device": "tv", "action": "power_off"})
        msgs = [ws.receive_json() for _ in range(2)]
        assert {"event", "result"} <= {m["type"] for m in msgs}
    assert hub.history.recent(1)[0]["source"] == "Josh's iPhone"
    # a paired device can bring in the next one
    code = phone.post("/api/pairing-codes", headers=auth).json()["code"]
    assert phone.post("/api/pair", json={"code": code, "name": "iPad"}).status_code == 200
    assert [c["name"] for c in mini.get("/api/clients").json()] == ["Josh's iPhone", "iPad"]


def test_code_works_once(tmp_path):
    mini, phone, _ = setup(tmp_path)
    code = mini.post("/api/pairing-codes").json()["code"]
    assert len(code) == 6 and code.isdigit()
    assert phone.post("/api/pair", json={"code": code, "name": "A"}).status_code == 200
    assert phone.post("/api/pair", json={"code": code, "name": "B"}).status_code == 403


def test_name_is_required(tmp_path):
    mini, phone, _ = setup(tmp_path)
    code = mini.post("/api/pairing-codes").json()["code"]
    assert phone.post("/api/pair", json={"code": code, "name": "  "}).status_code == 400


def test_removing_a_device_cuts_it_off(tmp_path):
    mini, phone, _ = setup(tmp_path)
    got = pair(mini, phone)
    auth = {"Authorization": "Bearer " + got["token"]}
    with phone.websocket_connect("/api/live", headers=auth) as ws:
        assert ws.receive_json()["type"] == "snapshot"
        assert mini.delete(f"/api/clients/{got['client']['id']}").status_code == 200
        with pytest.raises(WebSocketDisconnect) as e:
            while True:
                ws.receive_json()
        assert e.value.code == 4401
    assert phone.get("/api/devices", headers=auth).status_code == 401
    assert mini.delete(f"/api/clients/{got['client']['id']}").status_code == 404


def test_codes_expire(tmp_path):
    now = [1000.0]
    c = Clients(tmp_path / "c.sqlite", clock=lambda: now[0])
    code = c.new_code("Mac Mini")["code"]
    now[0] += 301
    with pytest.raises(PairingError) as e:
        c.pair(code, "Phone", "10.0.0.5")
    assert e.value.status == 403


def test_guessing_is_slowed_down(tmp_path):
    now = [1000.0]
    c = Clients(tmp_path / "c.sqlite", clock=lambda: now[0])
    code = c.new_code("Mac Mini")["code"]
    wrong = "000000" if code != "000000" else "000001"
    for _ in range(5):
        with pytest.raises(PairingError):
            c.pair(wrong, "Phone", "10.0.0.5")
    with pytest.raises(PairingError) as e:  # even the right code is refused from that address for a while
        c.pair(code, "Phone", "10.0.0.5")
    assert e.value.status == 429
    assert c.pair(code, "Laptop", "10.0.0.6")["token"]  # another device still can
    now[0] += 301
    code = c.new_code("Mac Mini")["code"]
    assert c.pair(code, "Phone", "10.0.0.5")["token"]


def test_too_many_wrong_guesses_burn_the_code(tmp_path):
    c = Clients(tmp_path / "c.sqlite")
    code = c.new_code("Mac Mini")["code"]
    wrong = "000000" if code != "000000" else "000001"
    for i in range(10):
        with pytest.raises(PairingError):
            c.pair(wrong, "x", f"10.0.1.{i}")
    with pytest.raises(PairingError):
        c.pair(code, "Phone", "10.0.0.9")


def test_only_a_hash_of_the_key_is_stored(tmp_path):
    c = Clients(tmp_path / "c.sqlite")
    token = c.pair(c.new_code("Mac Mini")["code"], "Phone", "10.0.0.5")["token"]
    assert token.encode() not in (tmp_path / "c.sqlite").read_bytes()
    assert c.check(token).name == "Phone"
