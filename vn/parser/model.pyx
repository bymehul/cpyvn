from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List

from ..script import Command


@dataclass(frozen=True)
class Script:
    commands: List[Command]
    labels: Dict[str, int]


class ScriptParseError(ValueError):
    pass
