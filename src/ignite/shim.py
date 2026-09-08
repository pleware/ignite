"""The ``env`` verb: print the PATH/eval shim for the consumer shell.

Output matches the previous ``env/env.sh`` line-for-line so ``eval "$(sh
env/env.sh)"`` keeps working through the trampoline.
"""

from __future__ import annotations

import os

from .pins import Pins
from .paths import resolve_toolchain_root, to_posix

__all__ = ["env_exports"]


def env_exports(workspace: str, pins: Pins) -> str:
    toolchain = to_posix(resolve_toolchain_root(workspace))
    mise_data = toolchain + "/mise"
    mise_bin_dir = f"{toolchain}/stack/mise/{pins.pin_mise}/bin"
    uv_bin_dir = f"{toolchain}/stack/uv/{pins.pin_uv}/bin"
    uv_tools = f"{toolchain}/uv-tools"
    gocache = f"{toolchain}/cache/go/build"
    gomodcache = f"{toolchain}/cache/go/mod"

    return "\n".join(
        [
            f'export IGNITE_TOOLCHAIN_ROOT="{toolchain}"',
            f'export MISE_DATA_DIR="{mise_data}"',
            f'export UV_TOOL_DIR="{uv_tools}"',
            f'export UV_TOOL_BIN_DIR="{uv_tools}/bin"',
            "unset GOROOT",
            f'export GOCACHE="{gocache}"',
            f'export GOMODCACHE="{gomodcache}"',
            f'export PATH="{mise_data}/shims:{mise_bin_dir}:{uv_tools}/bin:{uv_bin_dir}:$PATH"',
        ]
    )
