import json

import httpx
import pytest

from homebase_hub.adapters import CommandError
from homebase_hub.adapters.sony import SonyTV


class FakeBravia:
    """Answers like a Bravia's REST and IRCC endpoints."""

    def __init__(self, power="active", psk="1234"):
        self.power, self.psk, self.calls, self.ircc = power, psk, [], []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        if request.headers.get("X-Auth-PSK") != self.psk:
            return httpx.Response(403)
        if request.url.path == "/sony/IRCC":
            self.ircc.append(request.content.decode().split("<IRCCCode>")[1].split("<")[0])
            return httpx.Response(200)
        body = json.loads(request.content)
        m, p = body["method"], body["params"]
        self.calls.append((request.url.path, m, p))
        if m == "getPowerStatus":
            return httpx.Response(200, json={"result": [{"status": self.power}]})
        if m == "setPowerStatus":
            self.power = "active" if p[0]["status"] else "standby"
        if m == "getRemoteControllerInfo":
            return httpx.Response(200, json={"result": [{"bundled": True}, [
                {"name": "Up", "value": "AAAAAQAAAAEAAAB0Aw=="}, {"name": "Confirm", "value": "AAAAAQAAAAEAAABlAw=="}]]})
        if m == "getApplicationList":
            return httpx.Response(200, json={"result": [[{"title": "Netflix", "uri": "com.sony.dtv.netflix"}]]})
        if m == "getPlayingContentInfo":
            return httpx.Response(200, json={"error": [7, "Illegal State"]})
        if m == "getVolumeInformation":
            return httpx.Response(200, json={"result": [[{"target": "speaker", "volume": 18, "mute": False}]]})
        return httpx.Response(200, json={"result": []})


def make(tv=None, **kw):
    tv = tv or FakeBravia()
    return SonyTV("sony", "Sony TV", ip="10.0.0.6", psk="1234", transport=httpx.MockTransport(tv), **kw), tv


async def test_status_on_with_volume_and_apps():
    a, _ = make()
    st = await a.status()
    assert st.power == "on" and st.detail["volume"] == 18 and st.detail["muted"] is False
    assert a.describe()["apps"] == [{"name": "Netflix", "id": "com.sony.dtv.netflix"}]


async def test_standby_is_off():
    a, _ = make(FakeBravia(power="standby"))
    st = await a.status()
    assert st.power == "off" and st.reachable


async def test_wrong_key_needs_pairing():
    a = SonyTV("sony", "Sony TV", ip="10.0.0.6", psk="wrong", transport=httpx.MockTransport(FakeBravia()))
    st = await a.status()
    assert st.needs_pairing and st.reachable
    with pytest.raises(CommandError, match="pre-shared key"):
        await a.command("power_off")


async def test_power_and_inputs_and_apps():
    a, tv = make(FakeBravia(power="standby"))
    await a.command("power_on")
    assert tv.power == "active"
    await a.command("input", "HDMI 2")
    await a.status()
    await a.command("launch", "Netflix")  # by name, once the app list is known
    await a.command("volume", 30)
    sent = [(m, p) for _, m, p in tv.calls if m.startswith("set")]
    assert sent == [("setPowerStatus", [{"status": True}]), ("setPlayContent", [{"uri": "extInput:hdmi?port=2"}]),
                    ("setActiveApp", [{"uri": "com.sony.dtv.netflix"}]),
                    ("setAudioVolume", [{"target": "speaker", "volume": "30"}])]


async def test_buttons_use_ircc_codes_from_the_tv():
    a, tv = make()
    await a.command("button", "UP")
    await a.command("button", "ENTER")
    assert tv.ircc == ["AAAAAQAAAAEAAAB0Aw==", "AAAAAQAAAAEAAABlAw=="]
    with pytest.raises(CommandError):
        await a.command("button", "HOME")  # not in this fake's code list


async def test_unreachable_is_off():
    def down(request):
        raise httpx.ConnectError("no route")
    a = SonyTV("sony", "Sony TV", ip="10.0.0.6", psk="1234", transport=httpx.MockTransport(down))
    st = await a.status()
    assert st.power == "off" and not st.reachable
