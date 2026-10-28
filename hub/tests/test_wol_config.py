import pytest

from homebase_hub import config, wol


def test_magic_packet():
    p = wol.magic_packet("80:5b:65:f5:17:00")
    assert len(p) == 102 and p[:6] == b"\xff" * 6 and p[6:12] == bytes.fromhex("805b65f51700")
    with pytest.raises(ValueError):
        wol.magic_packet("nope")


def test_config_loads_devices(tmp_path):
    f = tmp_path / "hub.toml"
    f.write_text('[hub]\nport = 5000\ndata_dir = "%s"\n\n[[devices]]\nid = "lg"\nkind = "lg_webos"\nname = "LG TV"\nip = "1.2.3.4"\nmac = "aa:bb:cc:dd:ee:ff"\n' % tmp_path)
    cfg = config.load(f)
    assert cfg.port == 5000 and cfg.devices[0].options == {"ip": "1.2.3.4", "mac": "aa:bb:cc:dd:ee:ff"}


def test_example_config_parses():
    from pathlib import Path
    cfg = config.load(Path(__file__).parent.parent / "hub.example.toml")
    assert [d.id for d in cfg.devices] == ["lg"]
