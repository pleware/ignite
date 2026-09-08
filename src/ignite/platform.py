"""Platform detection (mirrors the shell ``detect_platform``).

Returns the ``go_os`` / ``go_arch`` pair the release URLs are built from.
"""

from __future__ import annotations

import platform as _platform

__all__ = ["detect", "PlatformError"]


class PlatformError(RuntimeError):
    pass


def detect() -> tuple[str, str]:
    """Return ``(go_os, go_arch)``, e.g. ``("windows", "amd64")``."""
    system = _platform.system()
    if system == "Windows":
        go_os = "windows"
    elif system == "Linux":
        go_os = "linux"
    elif system == "Darwin":
        go_os = "darwin"
    else:
        raise PlatformError(f"ignite: unsupported OS: {system}")

    machine = _platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        go_arch = "amd64"
    elif machine in ("aarch64", "arm64"):
        go_arch = "arm64"
    else:
        raise PlatformError(f"ignite: unsupported arch: {machine}")

    return go_os, go_arch
