"""Read the kit-owned pins (``pins/toolchain.sh``, ``pins/tools.sh``).

Those two files are data, not code: plain ``KEY=value`` shell assignments with
no logic (see their headers). The shell trampoline sources them; the engine
reads the same files so there is exactly one source of truth. Values may
reference each other (``TOOL_GRAPHIFYY_SPEC="...==$PIN_GRAPHIFYY"``), which is
resolved here the same way the shell would.
"""

from __future__ import annotations

import os
import re
from pathlib import Path

__all__ = ["Pins", "PinsError"]

_ASSIGN = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
_REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")


class PinsError(RuntimeError):
    """Raised when the pin data cannot be read."""


class Pins:
    """The kit pin set, parsed from the shell pin files."""

    def __init__(self, kit_root: str | os.PathLike):
        self.kit_root = Path(kit_root)
        self.values: dict[str, str] = {}
        self._load()

    def _load(self) -> None:
        raw: dict[str, str] = {}
        for name in ("pins/toolchain.sh", "pins/tools.sh"):
            path = self.kit_root / name
            if not path.is_file():
                continue
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[7:].strip()
                m = _ASSIGN.match(line)
                if not m:
                    continue
                key, val = m.group(1), m.group(2).strip()
                if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
                    val = val[1:-1]
                raw[key] = val

        def expand(value: str) -> str:
            return _REF.sub(lambda m: raw.get(m.group(1), ""), value)

        # A few passes settle chained references (spec -> PIN_*).
        for key in list(raw):
            val = raw[key]
            for _ in range(3):
                val = expand(val)
            raw[key] = val
        self.values = raw

    def get(self, key: str, default: str = "") -> str:
        return self.values.get(key, default)

    # -- the pins the engine and trampoline share -------------------------
    @property
    def pin_mise(self) -> str:
        return self.get("PIN_MISE")

    @property
    def pin_uv(self) -> str:
        return self.get("PIN_UV")

    @property
    def pin_python(self) -> str:
        return self.get("PIN_PYTHON")

    @property
    def pin_uv_sha256(self) -> str:
        return self.get("PIN_UV_SHA256")

    # -- the fleet CLI tools (family a) -----------------------------------
    @property
    def extra_tool_keys(self) -> list[str]:
        return [k for k in self.get("EXTRA_TOOL_KEYS").split() if k]

    def tool(self, key: str) -> dict[str, str]:
        """Return the TOOL_<KEY>_* block for one pinned CLI tool."""
        return {
            "spec": self.get(f"TOOL_{key}_SPEC"),
            "env": self.get(f"TOOL_{key}_ENV"),
            "python_marker": self.get(f"TOOL_{key}_PYTHON_MARKER"),
            "root_marker": self.get(f"TOOL_{key}_ROOT_MARKER"),
        }
