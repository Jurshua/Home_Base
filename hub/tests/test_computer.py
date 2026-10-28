import json
import threading
import urllib.request
from http.server import ThreadingHTTPServer

import httpx
import pytest

from homebase_hub.adapters import CommandError
from homebase_hub.adapters.computer import Computer

import importlib.util, pathlib
spec = importlib.util.spec_from_file_location("homebase_agent", pathlib.Path(__file__).parents[1] / "agent" / "homebase_agent.py")
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


async def closed(ip, port):
    return False


def make(handler, **kw):
    return Computer("pc", "Gaming PC", ip="10.0.0.7", transport=httpx.MockTransport(handler), probe=closed, **kw)


async def test_status_from_helper_and_off_when_silent():
    on = make(lambda r: httpx.Response(200, json={"ok": True, "os": "Windows", "version": "0.1.0"}), token="t")
    st = await on.status()
    assert st.power == "on" and st.detail["os"] == "Windows"

    def down(r):
        raise httpx.ConnectError("asleep")
    st2 = await make(down).status()
    assert st2.power == "off" and not st2.reachable


async def test_hub_computer_is_always_on():
    mini = Computer("mini", "Mac Mini", ip="127.0.0.1", can_turn_off=False)
    assert (await mini.status()).power == "on"


async def test_wake_and_sleep():
    sent, posted = [], []

    def helper(r):
        posted.append((r.headers.get("Authorization"), json.loads(r.content)))
        return httpx.Response(200, json={"ok": True})
    pc = make(helper, mac="aa:bb:cc:dd:ee:ff", token="secret", send_wol=lambda mac, ip: sent.append(mac))
    await pc.command("power_on")
    await pc.command("power_off")
    await pc.command("shutdown")
    assert sent == ["aa:bb:cc:dd:ee:ff"]
    assert posted == [("Bearer secret", {"action": "sleep"}), ("Bearer secret", {"action": "shutdown"})]


async def test_actions_depend_on_setup():
    assert make(lambda r: None).actions() == []
    hub_mac = make(lambda r: None, mac="aa:bb:cc:dd:ee:ff", token="t", can_turn_off=False)
    assert hub_mac.actions() == ["power_on"]
    with pytest.raises(CommandError):
        await hub_mac.command("power_off")


def test_agent_requires_token_and_runs_command():
    ran = []
    srv = ThreadingHTTPServer(("127.0.0.1", 0), agent.make_handler("tok", run=ran.append, commands=agent.COMMANDS["darwin"]))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_port}"
    try:
        health = json.load(urllib.request.urlopen(base + "/health"))
        assert health["ok"]

        def post(token, action):
            req = urllib.request.Request(base + "/power", data=json.dumps({"action": action}).encode(),
                                         headers={"Authorization": f"Bearer {token}"}, method="POST")
            try:
                return urllib.request.urlopen(req).status
            except urllib.error.HTTPError as e:
                return e.code
        assert post("nope", "sleep") == 401
        assert post("tok", "dance") == 400
        assert post("tok", "sleep") == 200
        import time
        time.sleep(1.3)  # the helper answers first, then acts
        assert ran == [["pmset", "sleepnow"]]
    finally:
        srv.shutdown()
