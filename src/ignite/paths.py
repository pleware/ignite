"""Workspace and toolchain path resolution (mirrors ``pins/resolve-workspace.sh``
and ``pins/workspace-paths.sh``).
"""

from __future__ import annotations

import os
import re
from pathlib import Path

__all__ = [
    "kit_root",
    "to_native",
    "to_posix",
    "resolve_workspace_root",
    "resolve_toolchain_root",
    "WorkspaceError",
]

_WORKSPACE_MARKERS = ("ignite.toml", "mani.yaml", "mise.toml")
_DRIVE_POSIX = re.compile(r"^/[a-zA-Z](/|$)")


class WorkspaceError(RuntimeError):
    pass


def kit_root() -> Path:
    """The kit checkout. Set by the trampoline via ``IGNITE_KIT_ROOT``; when
    the engine runs straight from source (tests), derive it from this file."""
    env = os.environ.get("IGNITE_KIT_ROOT")
    if env:
        return Path(env)
    # src/ignite/paths.py -> kit root
    return Path(__file__).resolve().parent.parent.parent


def to_native(p: str) -> str:
    """Convert a Git Bash POSIX path (``/f/foo``) to the native form Windows
    Python understands (``F:\\foo``). The trampoline runs under Git Bash and
    passes POSIX ``$@`` to the engine, which runs under Windows CPython — this
    is the seam that reconciles them. No-op on non-Windows and for paths that
    are already native (``D:/foo``, ``C:\\foo``, relative)."""
    if os.name != "nt":
        return p
    if _DRIVE_POSIX.match(p):
        return p[1].upper() + ":" + p[2:].replace("/", "\\")
    return p


def to_posix(p: str) -> str:
    """Convert a native Windows path (``F:\\foo``) to the Git Bash POSIX form
    (``/f/foo``). The ``env`` verb is ``eval``-ed by a POSIX shell, so its
    PATH must be POSIX even though the engine runs under Windows CPython."""
    if os.name != "nt":
        return p
    drive, rest = os.path.splitdrive(p)
    if len(drive) == 2 and drive[1] == ":":
        return "/" + drive[0].lower() + rest.replace("\\", "/")
    return p.replace("\\", "/")


def resolve_workspace_root(arg: str | None = None, cwd: str | None = None) -> str:
    """Order: ``$1``, then ``IGNITE_WORKSPACE``, then cwd if it looks like a
    workspace (has one of the marker files). Raises when none resolves."""
    cwd = cwd or os.getcwd()
    if arg:
        p = os.path.abspath(to_native(arg))
        if not os.path.isdir(p):
            raise WorkspaceError(f"ignite: no such workspace directory: {arg}")
        return os.path.realpath(p)
    env = os.environ.get("IGNITE_WORKSPACE")
    if env:
        p = os.path.abspath(to_native(env))
        if not os.path.isdir(p):
            raise WorkspaceError(f"ignite: no such IGNITE_WORKSPACE: {env}")
        return os.path.realpath(p)
    for marker in _WORKSPACE_MARKERS:
        if os.path.isfile(os.path.join(cwd, marker)):
            return os.path.realpath(cwd)
    raise WorkspaceError(
        "ignite: not a workspace (no ignite.toml, mani.yaml, or mise.toml).\n"
        "ignite: cd to the workspace, set IGNITE_WORKSPACE, or pass the path."
    )


def resolve_toolchain_root(workspace: str) -> str:
    """Machine files live under ``<workspace>/.ignite`` unless overridden."""
    env = os.environ.get("IGNITE_TOOLCHAIN_ROOT")
    if env:
        return env
    return os.path.join(workspace, ".ignite")
