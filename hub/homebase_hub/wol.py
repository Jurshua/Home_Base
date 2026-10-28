"""Wake-on-LAN magic packets."""
from __future__ import annotations

import socket


def magic_packet(mac: str) -> bytes:
    hexmac = mac.replace(":", "").replace("-", "")
    if len(hexmac) != 12:
        raise ValueError(f"bad MAC address {mac!r}")
    return b"\xff" * 6 + bytes.fromhex(hexmac) * 16


def send(mac: str, ip: str | None = None) -> None:
    """Broadcast the packet on ports 9 and 7, and also send it straight to the device's last IP."""
    pkt = magic_packet(mac)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        for port in (9, 7):
            s.sendto(pkt, ("255.255.255.255", port))
            if ip:
                s.sendto(pkt, (ip, port))
