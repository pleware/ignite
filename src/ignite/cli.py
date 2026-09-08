"""CLI entry point for the ignite engine.

Verb dispatch mirrors the shell argument shapes:

- ``ignite ensure [workspace] [tool ...]``
- ``ignite bootstrap [workspace]``
- ``ignite workspace-tree analyze|init [--tree FILE] [--kind KIND] [--dest DIR] [--parent-kind KIND] [workspace]``
- ``ignite env [workspace]``
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from typing import Callable

from .config import Config, ConfigError
from .manifest import ManifestError, clone_targets
from .paths import (
    WorkspaceError,
    kit_root,
    resolve_toolchain_root,
    resolve_workspace_root,
    to_native,
)
from .pins import Pins, PinsError
from .platform import PlatformError, detect
from .runtime_extensions import RuntimeExtensionsError, apply, plan
from .shim import env_exports
from .toolchain import plant_mise, prepare_dirs, run_mise_install
from .tools import install_tools, uv_binary, uv_sync
from .workspace_tree import (
    LayoutError,
    analyze,
    contains_kind,
    init,
    parse_layout_file,
)

__all__ = ["main"]

_WORKSPACE_MARKERS = ("ignite.toml", "mani.yaml", "mise.toml")


class CloneError(RuntimeError):
    pass


# -- thin process edges ---------------------------------------------------


def _subprocess_runner() -> Callable[[list[str], str | None, dict | None], None]:
    def run(cmd: list[str], cwd: str | None = None, env: dict | None = None) -> None:
        full_env = dict(os.environ)
        if env:
            full_env.update(env)
        subprocess.run(cmd, cwd=cwd, env=full_env, check=True)

    return run


def _fetch(url: str, dest: str) -> None:
    subprocess.run(["curl", "-fsSL", "-L", "-o", dest, url], check=True)


def _log(msg: str) -> None:
    print(msg)


# -- verbs ----------------------------------------------------------------


def _runtime_extensions(workspace: str, cfg: Config, go_os: str) -> None:
    extensions = cfg.runtime_extensions()
    if not extensions:
        return
    result = plan(extensions, go_os)
    apply(result, log=_log)


def _resolve_uv() -> str:
    return uv_binary() or "uv"


def _clone_repos(workspace: str) -> None:
    targets = clone_targets(workspace)
    if not targets:
        if not os.path.isfile(os.path.join(workspace, "mani.yaml")):
            _log("bootstrap: no mani.yaml — skip clones")
        return
    for t in targets:
        dest = os.path.join(workspace, t.dir)
        if os.path.isdir(os.path.join(dest, ".git")):
            _log(f"bootstrap: {t.dir} already cloned")
            continue
        if os.path.isdir(dest):
            if os.listdir(dest):
                print(f"bootstrap: {t.dir} exists but is not a git repo — skip clone", file=sys.stderr)
                if t.required:
                    raise CloneError(f"bootstrap: cannot clone required repo {t.dir}")
                continue
        _log(f"bootstrap: cloning {t.url} -> {t.dir}")
        try:
            subprocess.run(["git", "clone", t.url, dest], check=True)
            _log(f"bootstrap: cloned {t.dir}")
        except subprocess.CalledProcessError:
            if not t.required:
                print(
                    f"bootstrap: warning: could not clone {t.dir} (private repo or no auth)",
                    file=sys.stderr,
                )
                continue
            print(f"bootstrap: failed to clone {t.dir}", file=sys.stderr)
            raise CloneError(f"bootstrap: failed to clone {t.dir}")


def cmd_ensure(args: argparse.Namespace, pins: Pins, go_os: str, go_arch: str) -> int:
    workspace = resolve_workspace_root(args.workspace)
    cfg = Config(workspace).load()
    if not os.path.isfile(os.path.join(workspace, "mise.toml")):
        print(f"ignite: missing {os.path.join(workspace, 'mise.toml')}", file=sys.stderr)
        return 1

    print(f"ensure: workspace {workspace}")
    print(f"ensure: kit {kit_root()}")

    toolchain = resolve_toolchain_root(workspace)
    prepare_dirs(toolchain)

    run = _subprocess_runner()
    mise = plant_mise(toolchain, pins, go_os, go_arch, _fetch, _log)
    run_mise_install(workspace, toolchain, mise, args.tools, run, _log)
    _runtime_extensions(workspace, cfg, go_os)
    install_tools(toolchain, workspace, pins, _resolve_uv(), run, _log)
    uv_sync(workspace, _resolve_uv(), run, _log)

    print("ensure: done. Next:")
    print(f'  eval "$(sh {kit_root()}/env/env.sh)"')
    return 0


def cmd_bootstrap(args: argparse.Namespace, pins: Pins, go_os: str, go_arch: str) -> int:
    workspace = resolve_workspace_root(args.workspace)
    cfg = Config(workspace).load()

    print(f"bootstrap: workspace {workspace}")
    print(f"bootstrap: kit {kit_root()}")

    _clone_repos(workspace)

    toolchain = resolve_toolchain_root(workspace)
    prepare_dirs(toolchain)

    run = _subprocess_runner()
    mise = plant_mise(toolchain, pins, go_os, go_arch, _fetch, _log)
    run_mise_install(workspace, toolchain, mise, [], run, _log)
    _runtime_extensions(workspace, cfg, go_os)
    install_tools(toolchain, workspace, pins, _resolve_uv(), run, _log)
    uv_sync(workspace, _resolve_uv(), run, _log)

    print("bootstrap: done. Next:")
    print(f'  eval "$(sh {kit_root()}/env/env.sh)"')
    print("  mise --version")
    print("  mani --version")
    return 0


def cmd_env(args: argparse.Namespace, pins: Pins) -> int:
    workspace = resolve_workspace_root(args.workspace)
    print(env_exports(workspace, pins))
    return 0


def _optional_workspace(arg: str | None) -> str | None:
    if arg:
        return resolve_workspace_root(arg)
    if os.environ.get("IGNITE_WORKSPACE") or any(
        os.path.isfile(os.path.join(os.getcwd(), m)) for m in _WORKSPACE_MARKERS
    ):
        return resolve_workspace_root()
    return None


def cmd_workspace_tree(args: argparse.Namespace) -> int:
    cmd = args.wt_cmd
    workspace = _optional_workspace(args.workspace)

    layout_file: str | None = None
    layout_kind: str | None = None
    kind_from_toml: str | None = None

    if workspace and os.path.isfile(os.path.join(workspace, "ignite.toml")):
        cfg = Config(workspace).load()
        layout_file, layout_kind, kind_from_toml = cfg.layout_policy()
        if layout_file and not os.path.isabs(layout_file):
            layout_file = os.path.join(workspace, layout_file)

    if args.tree:
        layout_file = (
            args.tree
            if os.path.isabs(args.tree)
            else os.path.abspath(to_native(args.tree))
        )
    if args.kind:
        layout_kind = args.kind

    if not layout_file or not layout_kind:
        print(
            "ignite workspace-tree: need --tree and --kind, or ignite.toml [workspace-tree]",
            file=sys.stderr,
        )
        return 1

    dest = workspace
    if args.dest:
        dest = os.path.abspath(to_native(args.dest))
        os.makedirs(dest, exist_ok=True)
    elif not dest:
        print("ignite workspace-tree: need --dest or a workspace", file=sys.stderr)
        return 1

    parent_kind = args.parent_kind or kind_from_toml
    layout = parse_layout_file(layout_file)

    if cmd == "init" and workspace and dest != workspace:
        p = args.parent_kind or kind_from_toml
        if p and p != layout_kind:
            if not contains_kind(layout, p, layout_kind):
                print(
                    f"ignite workspace-tree: kind '{layout_kind}' is not in contains of '{p}'",
                    file=sys.stderr,
                )
                return 1

    if cmd == "analyze":
        errors = analyze(dest, layout_kind, layout)
    else:
        pack = os.path.dirname(layout_file)
        errors = init(dest, layout_kind, pack, layout)

    for line in errors:
        print(line, file=sys.stderr)
    if errors:
        return 1
    print(f"ignite workspace-tree: {cmd} ok ({layout_kind} @ {dest})")
    return 0


# -- parser ---------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="ignite")
    sub = parser.add_subparsers(dest="verb", required=True)

    p_ensure = sub.add_parser("ensure", help="plant mise and install pins (no clones)")
    p_ensure.add_argument("workspace", nargs="?")
    p_ensure.add_argument("tools", nargs="*")

    p_boot = sub.add_parser("bootstrap", help="clone mani sync repos, then ensure")
    p_boot.add_argument("workspace", nargs="?")

    p_env = sub.add_parser("env", help="print the PATH/eval shim")
    p_env.add_argument("workspace", nargs="?")

    p_wt = sub.add_parser("workspace-tree", help="apply/check a kind document")
    wt = p_wt.add_subparsers(dest="wt_cmd", required=True)
    for name in ("analyze", "init"):
        c = wt.add_parser(name)
        c.add_argument("--tree", "--layout", dest="tree")
        c.add_argument("--kind", dest="kind")
        c.add_argument("--dest", dest="dest")
        c.add_argument("--parent-kind", dest="parent_kind")
        c.add_argument("workspace", nargs="?")

    return parser


_KNOWN_ERRORS = (
    ConfigError,
    WorkspaceError,
    PinsError,
    LayoutError,
    ManifestError,
    CloneError,
    PlatformError,
    RuntimeExtensionsError,
)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        pins = Pins(kit_root())
        go_os, go_arch = detect()
    except (PinsError, PlatformError) as exc:
        print(str(exc), file=sys.stderr)
        return 1

    try:
        if args.verb == "ensure":
            return cmd_ensure(args, pins, go_os, go_arch)
        if args.verb == "bootstrap":
            return cmd_bootstrap(args, pins, go_os, go_arch)
        if args.verb == "env":
            return cmd_env(args, pins)
        if args.verb == "workspace-tree":
            return cmd_workspace_tree(args)
    except _KNOWN_ERRORS as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(f"ignite: unknown verb {args.verb}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
