"""What every device adapter looks like to the rest of the hub."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


class CommandError(Exception):
    """A command reached the adapter but could not be carried out."""


@dataclass
class DeviceStatus:
    power: str  # "on", "off" or "unknown"
    reachable: bool
    detail: dict[str, Any] = field(default_factory=dict)
    needs_pairing: bool = False


class Adapter(ABC):
    kind: str = ""

    def __init__(self, id: str, name: str):
        self.id = id
        self.name = name

    def describe(self) -> dict[str, Any]:
        """Static facts the apps need to draw controls: actions, apps, inputs."""
        return {"id": self.id, "name": self.name, "kind": self.kind, "actions": self.actions()}

    @abstractmethod
    def actions(self) -> list[str]: ...

    @abstractmethod
    async def status(self) -> DeviceStatus: ...

    @abstractmethod
    async def command(self, action: str, arg: Any = None) -> dict[str, Any]: ...

    async def close(self) -> None:
        pass
