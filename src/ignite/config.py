"""Consumer ``ignite.toml`` policy (mirrors ``pins/read-ignite-toml.sh``).

Reads ``[kit]`` (pin / url), ``[runtime-extensions]``, and
``[workspace-tree]`` (alias ``[layout]``) file / kind.
"""

from __future__ import annotations

import os

from . import _toml

__all__ = ["Config", "ConfigError", "DEFAULT_KIT_URL"]

DEFAULT_KIT_URL = "https://github.com/pleware/ignite.git"


class ConfigError(RuntimeError):
    pass


class Config:
    def __init__(self, workspace: str):
        self.workspace = workspace
        self.path = os.path.join(workspace, "ignite.toml")
        self._data: dict | None = None

    def load(self) -> "Config":
        """Require the file. Content may be comments-only."""
        if not os.path.isfile(self.path):
            raise ConfigError(f"ignite: missing {self.path}")
        with open(self.path, encoding="utf-8") as fh:
            self._data = _toml.loads(fh.read())
        return self

    def kit_policy(self) -> tuple[str | None, str | None]:
        """``(pin, url)``. ``[kit]`` is optional; ``pin`` is required when the
        section is present; ``url`` defaults to the public kit remote."""
        kit = self._data.get("kit", {}) if self._data else {}
        pin = kit.get("pin")
        url = kit.get("url")
        if pin is None and url is None:
            return None, None
        if pin is None:
            raise ConfigError(
                f"ignite: {self.path} [kit] needs pin (git tag, branch, or commit)"
            )
        return pin, (url or DEFAULT_KIT_URL)

    def runtime_extensions(self) -> dict[str, list[str]]:
        """``[runtime-extensions]``: ``runtime -> [extension, ...]``. Empty
        when absent. Never merged with ``TOOL_*`` (family a)."""
        table = self._data.get("runtime-extensions", {}) if self._data else {}
        out: dict[str, list[str]] = {}
        for runtime, extensions in table.items():
            if isinstance(extensions, list):
                out[runtime] = [str(e) for e in extensions]
            else:
                out[runtime] = [str(extensions)]
        return out

    def layout_policy(self) -> tuple[str | None, str | None, str | None]:
        """``(file, kind, kind_from_toml)``. ``[workspace-tree]`` wins over
        ``[layout]``; the third element is the kind as read from the file
        (used by ``init --parent-kind``)."""
        tree = self._data.get("workspace-tree") if self._data else None
        alias = self._data.get("layout") if self._data else None
        file_: str | None = None
        kind: str | None = None
        kind_from: str | None = None
        if tree:
            file_ = tree.get("file")
            kind = tree.get("kind")
            kind_from = kind
        elif alias:
            file_ = alias.get("file")
            kind = alias.get("kind")
            kind_from = kind
        return file_, kind, kind_from
