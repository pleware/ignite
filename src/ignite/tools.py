"""The ``TOOL_*`` plant and layer-2 ``uv sync``.

``TOOL_*`` (family a) are fleet-pinned CLI tools installed with ``uv tool
install`` into isolated environments under ``.ignite/uv-tools``. This is the
same logic ``pins/ensure-tools.sh`` held; it runs *inside* the engine now,
which is itself bootstrapped on the planted ``uv``.

Layer 2 is the ``uv sync`` that installs the product's own lockfile deps
(family b). Composer/npm are not wired yet (draft 69).
"""

from __future__ import annotations

import os
import shutil
from typing import Callable, Optional

from .pins import Pins

__all__ = [
    "uv_binary",
    "uv_tool_dir",
    "install_tools",
    "uv_sync",
]


def uv_binary() -> Optional[str]:
    """The planted ``uv`` the engine runs on. The trampoline exports
    ``IGNITE_UV``; fall back to ``uv`` on PATH."""
    env = os.environ.get("IGNITE_UV")
    if env and os.path.isfile(env):
        return env
    return shutil.which("uv")


def uv_tool_dir(toolchain_root: str) -> str:
    return os.path.join(toolchain_root, "uv-tools")


def _native_path(p: str) -> str:
    # Git Bash hands the shell /f/work/repo; only PowerShell needs the
    # drive-letter form, so on Windows emit D:/work/repo — both shells run it.
    if os.name == "nt":
        return p.replace("\\", "/")
    return p


def _tool_env_python(env_root: str) -> Optional[str]:
    for sub in ("Scripts/python.exe", "bin/python", "bin/python3"):
        p = os.path.join(env_root, sub)
        if os.path.isfile(p):
            return p
    return None


def _write_marker(workspace: str, rel: str, value: str) -> None:
    target = os.path.join(workspace, rel)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(value + "\n")


def _tool_is_current(env_root: str, pin: str) -> bool:
    if not pin:
        return False
    receipt = os.path.join(env_root, "uv-receipt.toml")
    if not os.path.isfile(receipt):
        return False
    with open(receipt, encoding="utf-8") as fh:
        return pin in fh.read()


def _write_tool_markers(
    workspace: str, tool_dir: str, tool: dict[str, str], log: Callable[[str], None]
) -> None:
    env_dir = tool["env"]
    if not env_dir:
        return
    env_root = os.path.join(tool_dir, env_dir)
    py_marker = tool["python_marker"]
    root_marker = tool["root_marker"]
    if py_marker:
        py = _tool_env_python(env_root)
        if py:
            _write_marker(workspace, py_marker, _native_path(py))
        else:
            log(f"ignite: no interpreter under {env_root} — skipped {py_marker}")
    if root_marker:
        # Relative on purpose: valid across clones and machines.
        _write_marker(workspace, root_marker, ".")


def install_tools(
    toolchain_root: str,
    workspace: str,
    pins: Pins,
    uv: str,
    run: Callable[[list[str], str | None, dict | None], None],
    log: Callable[[str], None] = print,
) -> None:
    keys = pins.extra_tool_keys
    if not keys:
        return
    tool_dir = uv_tool_dir(toolchain_root)
    bin_dir = os.path.join(tool_dir, "bin")
    os.makedirs(bin_dir, exist_ok=True)
    env = {"UV_TOOL_DIR": tool_dir, "UV_TOOL_BIN_DIR": bin_dir}

    for key in keys:
        tool = pins.tool(key)
        spec = tool["spec"]
        env_dir = tool["env"]
        if not spec:
            log(f"ignite: tool {key} has no TOOL_{key}_SPEC — skipped")
            continue
        pin = spec.rsplit("==", 1)[-1]
        if pin == spec:
            pin = ""
        if env_dir and _tool_is_current(os.path.join(tool_dir, env_dir), pin):
            log(f"ignite: {spec} already at {os.path.join(tool_dir, env_dir)}")
            _write_tool_markers(workspace, tool_dir, tool, log)
            continue
        log(f"ignite: uv tool install {spec} -> {tool_dir}")
        run([uv, "tool", "install", "--force", spec], workspace, env)
        _write_tool_markers(workspace, tool_dir, tool, log)
    log("ignite: extra tools done")


def uv_sync(
    workspace: str,
    uv: str,
    run: Callable[[list[str], str | None, dict | None], None],
    log: Callable[[str], None] = print,
) -> None:
    """Layer 2: install the product's own lockfile deps. No-op without a
    ``pyproject.toml``. Composer/npm are future work (draft 69)."""
    if not os.path.isfile(os.path.join(workspace, "pyproject.toml")):
        return
    log("ignite: uv sync (layer 2)")
    run([uv, "sync"], workspace, None)
