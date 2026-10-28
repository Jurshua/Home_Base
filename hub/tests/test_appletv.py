import pytest

pyatv_const = pytest.importorskip("pyatv.const")

from homebase_hub.adapters import CommandError
from homebase_hub.adapters.appletv import AppleTV


class Obj:
    def __init__(self, **kw):
        self.__dict__.update(kw)


class FakeATV:
    def __init__(self, power=pyatv_const.PowerState.On):
        self.log = []
        outer = self

        class RC:
            def __getattr__(self, name):
                async def press():
                    outer.log.append(name)
                return press

        async def turn_on():
            self.power.power_state = pyatv_const.PowerState.On

        async def app_list():
            return [Obj(name="Netflix", identifier="com.netflix.Netflix")]

        async def launch(app):
            self.log.append(("launch", app))

        async def playing():
            return Obj(device_state=pyatv_const.DeviceState.Playing, title="[Show]", series_name=None)

        self.power = Obj(power_state=power, turn_on=turn_on)
        self.remote_control = RC()
        self.apps = Obj(app_list=app_list, launch_app=launch)
        self.metadata = Obj(playing=playing, app=Obj(name="TV"))

    def close(self):
        pass


def make(atv=None, unpaired=False):
    atv = atv or FakeATV()

    async def connect():
        if unpaired:
            raise PermissionError("not paired")
        return atv
    return AppleTV("atv", "Apple TV", ip="10.0.0.8", storage_file="/tmp/x.json", connector=connect), atv


async def test_status_and_apps():
    a, _ = make()
    st = await a.status()
    assert st.power == "on" and st.detail == {"state": "playing", "title": "[Show]", "series": None, "app": "TV"}
    assert a.describe()["apps"] == [{"name": "Netflix", "id": "com.netflix.Netflix"}]


async def test_standby_is_off_and_power_on():
    a, atv = make(FakeATV(power=pyatv_const.PowerState.Off))
    assert (await a.status()).power == "off"
    await a.command("power_on")
    assert (await a.status()).power == "on"


async def test_buttons_and_launch():
    a, atv = make()
    await a.command("button", "ENTER")
    await a.command("button", "BACK")
    await a.status()
    await a.command("launch", "Netflix")
    assert atv.log == ["select", "menu", ("launch", "com.netflix.Netflix")]


async def test_unpaired():
    a, _ = make(unpaired=True)
    st = await a.status()
    assert st.needs_pairing and st.power == "unknown"
    with pytest.raises(CommandError, match="paired"):
        await a.command("button", "UP")
