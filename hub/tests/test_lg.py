import pytest

from homebase_hub.adapters import CommandError
from homebase_hub.adapters.lg import LGTV, NeedsPairing


class FakeClient:
    """Stands in for bscpylgtv's WebOsClient."""

    def __init__(self, fail_first=0, power_state="Active"):
        self.calls, self.connected, self.input_connection, self.fail_first = [], True, object(), fail_first
        self.power_state = power_state

    def is_connected(self):
        return self.connected

    async def disconnect(self):
        self.connected = False

    async def _call(self, *c):
        if self.fail_first:
            self.fail_first -= 1
            raise ConnectionError("stale socket")
        self.calls.append(c)

    async def button(self, b): await self._call("button", b)
    async def launch_app(self, a): await self._call("launch", a)
    async def set_volume(self, v): await self._call("volume", v)
    async def set_mute(self, m): await self._call("mute", m)
    async def power_off(self): await self._call("off")
    async def get_audio_status(self): return {"volume": 12, "mute": False}
    async def get_current_app(self): return "netflix"
    async def get_power_state(self): return {"state": self.power_state}
    async def power_on(self): await self._call("power_on")


async def no_tv(ip, port):
    return False


def make(clients, wol=None, probe=no_tv):
    made = []

    async def factory(ip, key_file, timeout, allow_pairing):
        c = clients.pop(0)
        if isinstance(c, Exception):
            raise c
        made.append(c)
        return c
    tv = LGTV("lg", "LG TV", ip="10.0.0.5", mac="80:5b:65:f5:17:00", key_file="/tmp/k.sqlite",
              client_factory=factory, send_wol=wol or (lambda mac, ip: None), probe=probe)
    return tv, made


async def test_button_and_launch():
    tv, made = make([FakeClient()])
    await tv.command("button", "UP")
    await tv.command("launch", "netflix")
    assert made[0].calls == [("button", "UP"), ("launch", "netflix")]


async def test_input_accepts_friendly_names():
    tv, made = make([FakeClient()])
    await tv.command("input", "HDMI 2")
    await tv.command("input", "hdmi3")
    await tv.command("input", "com.webos.app.hdmi4")
    assert [c[1] for c in made[0].calls] == ["com.webos.app.hdmi2", "com.webos.app.hdmi3", "com.webos.app.hdmi4"]


async def test_rejects_unknown_button_and_input():
    tv, _ = make([FakeClient()])
    with pytest.raises(CommandError):
        await tv.command("button", "SELF_DESTRUCT")
    with pytest.raises(CommandError):
        await tv.command("input", "HDMI 9")


async def test_reconnects_once_after_stale_connection():
    tv, made = make([FakeClient(fail_first=1), FakeClient()])
    await tv.command("button", "ENTER")
    assert len(made) == 2 and made[1].calls == [("button", "ENTER")]


async def test_power_on_uses_wake_on_lan():
    sent = []
    tv, made = make([], wol=lambda mac, ip: sent.append((mac, ip)))
    await tv.command("power_on")
    assert sent == [("80:5b:65:f5:17:00", "10.0.0.5")] and made == []


async def test_status_on_and_off():
    tv, _ = make([FakeClient()])
    st = await tv.status()
    assert st.power == "on" and st.detail == {"app": "netflix", "volume": 12, "muted": False, "power_state": "Active"}

    async def unreachable(ip, key_file, timeout, allow_pairing):
        raise OSError("no route to host")
    tv2 = LGTV("lg", "LG TV", ip="10.0.0.5", mac="80:5b:65:f5:17:00", key_file="/tmp/k", client_factory=unreachable)
    st2 = await tv2.status()
    assert st2.power == "off" and not st2.reachable


async def test_volume_is_clamped():
    tv, made = make([FakeClient()])
    await tv.command("volume", 250)
    assert made[0].calls == [("volume", 100)]


async def test_standby_reports_off_even_though_socket_answers():
    tv, _ = make([FakeClient(power_state="Active Standby")])
    st = await tv.status()
    assert st.power == "off" and st.reachable and st.detail == {"power_state": "Active Standby"}


async def test_power_on_from_standby_also_asks_over_the_socket():
    sent = []
    tv, made = make([FakeClient(power_state="Active Standby")], wol=lambda mac, ip: sent.append(mac))
    await tv.status()
    await tv.command("power_on")
    assert sent and made[0].calls == [("power_on",)]


async def test_missing_key_is_needs_pairing_and_polling_stops_asking():
    async def tv_up(ip, port):
        return True
    tv, made = make([NeedsPairing("no key")], probe=tv_up)
    st = await tv.status()
    assert st.needs_pairing and st.reachable and st.power == "unknown"
    st2 = await tv.status()  # no second connection attempt, so no second prompt on the TV
    assert st2.needs_pairing and made == []
    with pytest.raises(CommandError, match="pairing"):
        await tv.command("button", "UP")


async def test_pair_clears_needs_pairing():
    tv, made = make([NeedsPairing("no key"), FakeClient()])
    await tv.status()
    await tv.command("pair")
    await tv.command("button", "UP")
    assert made[0].calls == [("button", "UP")]
    assert not (await tv.status()).needs_pairing


async def test_declined_pairing_is_a_clear_error():
    tv, _ = make([NeedsPairing("Unable to pair")])
    with pytest.raises(CommandError, match="turned down"):
        await tv.command("pair")
