"""The mise toolchain edge: plant mise and run ``mise install``.

These are the thin network/process edges. Pure decisions (which archive,
which paths) live here as data; the heavy lifting is ``curl`` + ``mise``.
"""

from __future__ import annotations

import os
import subprocess
from typing import Callable, Optional

from .pins import Pins

__all__ = ["mise_binary", "plant_mise", "run_mise_install", "prepare_dirs"]

# release archive name per (os, arch) -> the mise release asset name.
_MISE_ARCHIVE = {
    ("windows", "amd64"): "mise-v{PIN}-windows-x64.zip",
    ("windows", "arm64"): "mise-v{PIN}-windows-arm64.zip",
    ("linux", "amd64"): "mise-v{PIN}-linux-x64.tar.gz",
    ("linux", "arm64"): "mise-v{PIN}-linux-arm64.tar.gz",
    ("darwin", "amd64"): "mise-v{PIN}-macos-x64.tar.gz",
    ("darwin", "arm64"): "mise-v{PIN}-macos-arm64.tar.gz",
}


def prepare_dirs(toolchain_root: str) -> None:
    os.makedirs(os.path.join(toolchain_root, "stack", "mise"), exist_ok=True)
    os.makedirs(os.path.join(toolchain_root, "cache", "go"), exist_ok=True)
    os.makedirs(os.path.join(toolchain_root, "mise"), exist_ok=True)


def mise_binary(toolchain_root: str, pins: Pins) -> Optional[str]:
    base = os.path.join(toolchain_root, "stack", "mise", pins.pin_mise, "bin")
    for name in ("mise.exe", "mise"):
        p = os.path.join(base, name)
        if os.path.isfile(p):
            return p
    return None


def plant_mise(
    toolchain_root: str,
    pins: Pins,
    go_os: str,
    go_arch: str,
    fetch: Callable[[str, str], None],
    log: Callable[[str], None] = print,
) -> str:
    """Download and extract the pinned mise. ``fetch(url, dest)`` is injected
    so tests can stub the network edge. Returns the planted binary path."""
    dest_dir = os.path.join(toolchain_root, "stack", "mise", pins.pin_mise)
    existing = mise_binary(toolchain_root, pins)
    if existing:
        log(f"ignite: mise {pins.pin_mise} already at {dest_dir}")
        return existing

    asset = _MISE_ARCHIVE.get((go_os, go_arch))
    if asset is None:
        raise RuntimeError(
            f"ignite: no official mise {pins.pin_mise} for {go_os}/{go_arch}"
        )
    name = asset.replace("{PIN}", pins.pin_mise)
    url = f"https://github.com/jdx/mise/releases/download/v{pins.pin_mise}/{name}"
    log(f"ignite: fetching {url}")

    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        archive = os.path.join(tmp, name)
        fetch(url, archive)
        extract_dir = os.path.join(tmp, "extract")
        _extract(archive, extract_dir)
        found = _find_binary(extract_dir, ("mise.exe", "mise"))
        if found is None:
            raise RuntimeError("ignite: expected mise binary in archive")
        if os.path.exists(dest_dir):
            import shutil

            shutil.rmtree(dest_dir)
        os.makedirs(os.path.join(dest_dir, "bin"), exist_ok=True)
        target_name = "mise.exe" if go_os == "windows" else "mise"
        target = os.path.join(dest_dir, "bin", target_name)
        import shutil

        shutil.move(found, target)
        if go_os != "windows":
            os.chmod(target, 0o755)
        # mise ships a shim next to the binary; carry it over.
        src_dir = os.path.dirname(found)
        for extra in ("mise-shim.exe", "mise-shim"):
            extra_src = os.path.join(src_dir, extra)
            if os.path.isfile(extra_src):
                shutil.move(extra_src, os.path.join(dest_dir, "bin", extra))
                if go_os != "windows":
                    os.chmod(os.path.join(dest_dir, "bin", extra), 0o755)
    log(f"ignite: planted mise {pins.pin_mise}")
    return mise_binary(toolchain_root, pins) or target


def _extract(archive: str, dest: str) -> None:
    os.makedirs(dest, exist_ok=True)
    if archive.endswith(".zip"):
        import zipfile

        with zipfile.ZipFile(archive) as zf:
            zf.extractall(dest)
    elif archive.endswith(".tar.gz"):
        import tarfile

        with tarfile.open(archive, "r:gz") as tf:
            tf.extractall(dest)
    elif archive.endswith(".tar.xz"):
        import tarfile

        with tarfile.open(archive, "r:xz") as tf:
            tf.extractall(dest)
    else:
        raise RuntimeError(f"ignite: unsupported archive: {archive}")


def _find_binary(root: str, names: tuple[str, ...]) -> Optional[str]:
    for dirpath, _dirs, files in os.walk(root):
        for name in names:
            candidate = os.path.join(dirpath, name)
            if os.path.isfile(candidate):
                return candidate
    return None


def run_mise_install(
    workspace: str,
    toolchain_root: str,
    mise_bin: str,
    extra_tools: list[str],
    run: Callable[[list[str], str | None, dict | None], None],
    log: Callable[[str], None] = print,
) -> None:
    """``mise trust`` + ``mise install`` (+ one install per extra tool)."""
    env = dict(os.environ)
    env["MISE_DATA_DIR"] = os.path.join(toolchain_root, "mise")
    env["MISE_YES"] = "1"
    if "GITHUB_TOKEN" in env and "MISE_GITHUB_TOKEN" not in env:
        env["MISE_GITHUB_TOKEN"] = env["GITHUB_TOKEN"]

    log(f"ignite: mise install (pins in mise.toml) -> {env['MISE_DATA_DIR']}")
    run([mise_bin, "trust", os.path.join(workspace, "mise.toml")], workspace, env)
    run([mise_bin, "install"], workspace, env)
    for tool in extra_tools:
        run([mise_bin, "install", tool], workspace, env)
    log("ignite: mise install done")
