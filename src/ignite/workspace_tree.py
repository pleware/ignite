"""Workspace-tree verbs (port of ``pins/read-layout.sh`` + ``layout-apply.sh``).

A kind document is YAML the consumer writes (schema ``ignite.workspace-tree/1``,
alias ``ignite.layout/1``). The kit only implements the verbs ``dir`` /
``stub`` / ``absent`` against it; kinds are not built into the kit.
"""

from __future__ import annotations

import os
import re
import shutil
from dataclasses import dataclass, field

from . import _yaml

__all__ = [
    "Layout",
    "Kind",
    "LayoutError",
    "parse_layout",
    "parse_layout_file",
    "require_kind",
    "contains_kind",
    "analyze",
    "init",
]

ALLOWED_SCHEMAS = ("ignite.workspace-tree/1", "ignite.layout/1")
PLANTS = ("dir", "stub", "absent")
_KIND_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")


class LayoutError(RuntimeError):
    pass


@dataclass
class Kind:
    name: str
    gitignore: str | None = None
    contains: list[str] = field(default_factory=list)
    markdown_allow: list[str] = field(default_factory=list)
    markdown_forbid: list[str] = field(default_factory=list)
    gitignore_lines: list[str] = field(default_factory=list)
    tree: list[dict] = field(default_factory=list)


@dataclass
class Layout:
    schema: str
    kinds: dict[str, Kind]


def parse_layout(text: str) -> Layout:
    data = _yaml.loads(text)
    if not isinstance(data, dict):
        raise LayoutError("ignite workspace-tree: not a mapping document")
    schema = data.get("schema")
    if schema not in ALLOWED_SCHEMAS:
        raise LayoutError(
            'ignite workspace-tree: schema must be ignite.workspace-tree/1 '
            f'(or ignite.layout/1; got "{schema}")'
        )
    kinds_raw = data.get("kinds") or {}
    kinds: dict[str, Kind] = {}
    for name, raw in kinds_raw.items():
        if not _KIND_NAME.match(str(name)):
            raise LayoutError(f"ignite workspace-tree: bad kind name: {name}")
        if not isinstance(raw, dict):
            raw = {}
        gitignore = raw.get("gitignore")
        if gitignore is not None and gitignore not in ("deny-by-default", "allow-by-default"):
            raise LayoutError(
                "ignite workspace-tree: gitignore must be deny-by-default or allow-by-default"
            )
        tree = list(raw.get("tree") or [])
        for item in tree:
            if item.get("plant") not in PLANTS:
                raise LayoutError("ignite workspace-tree: plant must be dir, stub, or absent")
        kinds[str(name)] = Kind(
            name=str(name),
            gitignore=gitignore,
            contains=list(raw.get("contains") or []),
            markdown_allow=list(raw.get("markdown_allow") or []),
            markdown_forbid=list(raw.get("markdown_forbid") or []),
            gitignore_lines=list(raw.get("gitignore_lines") or []),
            tree=tree,
        )
    if not kinds:
        raise LayoutError("ignite workspace-tree: no kinds")
    return Layout(schema=str(schema), kinds=kinds)


def parse_layout_file(path: str) -> Layout:
    if not os.path.isfile(path):
        raise LayoutError(f"ignite workspace-tree: missing {path}")
    with open(path, encoding="utf-8") as fh:
        return parse_layout(fh.read())


def require_kind(layout: Layout, kind: str) -> Kind:
    if kind not in layout.kinds:
        listing = "\n".join(f"  {k}" for k in layout.kinds)
        raise LayoutError(
            f"ignite workspace-tree: unknown kind '{kind}'\n"
            f"ignite workspace-tree: kinds:\n{listing}"
        )
    return layout.kinds[kind]


def contains_kind(layout: Layout, parent: str, child: str) -> bool:
    kd = layout.kinds.get(parent)
    if kd is None:
        return False
    return child in kd.contains


def _rel_ok(p: str) -> bool:
    if p == "" or p.startswith("/") or "\\" in p:
        return False
    wrapped = "/" + p + "/"
    if "/./" in wrapped or "/../" in wrapped:
        return False
    return True


def _is_required(item: dict) -> bool:
    val = item.get("required", True)
    return val not in (False, "false", "no", "False")


def _gitignore_has_line(path: str, want: str) -> bool:
    if not os.path.isfile(path):
        return False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.rstrip("\r\n") == want:
                return True
    return False


def _append_gitignore(path: str, line: str) -> None:
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")


def analyze(root: str, kind: str, layout: Layout) -> list[str]:
    """Return problem lines (empty list = ok)."""
    kd = require_kind(layout, kind)
    errors: list[str] = []

    for item in kd.tree:
        path = item.get("path", "")
        plant = item.get("plant", "")
        required = _is_required(item)
        if not _rel_ok(path):
            errors.append(f"ignite workspace-tree: bad path: {path}")
            continue
        target = os.path.join(root, path)
        if plant == "dir":
            if required and not os.path.isdir(target):
                errors.append(f"ignite workspace-tree: missing dir {path}")
        elif plant == "stub":
            if required and not os.path.isfile(target):
                errors.append(f"ignite workspace-tree: missing file {path}")
        elif plant == "absent":
            if os.path.exists(target):
                errors.append(f"ignite workspace-tree: path should be absent: {path}")
        else:
            errors.append(f"ignite workspace-tree: unknown plant {plant}")

    for line in kd.markdown_forbid:
        if not _rel_ok(line):
            errors.append(f"ignite workspace-tree: bad markdown_forbid: {line}")
            continue
        if os.path.exists(os.path.join(root, line)):
            errors.append(f"ignite workspace-tree: forbidden path exists: {line}")

    gi = os.path.join(root, ".gitignore")
    if kd.gitignore == "deny-by-default":
        if not _gitignore_has_line(gi, "/*"):
            errors.append("ignite workspace-tree: deny-by-default needs a /* line in .gitignore")

    for line in kd.gitignore_lines:
        if not _gitignore_has_line(gi, line):
            errors.append(f"ignite workspace-tree: .gitignore missing line: {line}")

    return errors


def init(root: str, kind: str, pack: str, layout: Layout) -> list[str]:
    """Apply a kind to a directory. Returns problem lines (empty = ok)."""
    kd = require_kind(layout, kind)
    errors: list[str] = []
    os.makedirs(root, exist_ok=True)

    for item in kd.tree:
        path = item.get("path", "")
        plant = item.get("plant", "")
        from_ = item.get("from", "")
        if not _rel_ok(path):
            errors.append(f"ignite workspace-tree: bad path: {path}")
            return errors
        target = os.path.join(root, path)
        if plant == "dir":
            os.makedirs(target, exist_ok=True)
        elif plant == "stub":
            os.makedirs(os.path.dirname(target), exist_ok=True)
            if not os.path.exists(target):
                _copy_stub(from_, target, pack)
        elif plant == "absent":
            pass
        else:
            errors.append(f"ignite workspace-tree: unknown plant {plant}")
            return errors

    gi = os.path.join(root, ".gitignore")
    if kd.gitignore == "deny-by-default":
        if not _gitignore_has_line(gi, "/*"):
            _append_gitignore(gi, "/*")
    for line in kd.gitignore_lines:
        if not _gitignore_has_line(gi, line):
            _append_gitignore(gi, line)

    return errors


def _copy_stub(from_: str, dest: str, pack: str) -> None:
    if not from_:
        with open(dest, "w", encoding="utf-8") as fh:
            fh.write(f"# {os.path.basename(dest)}\n")
        return
    if not _rel_ok(from_):
        raise LayoutError(f"ignite workspace-tree: bad from: {from_}")
    src = os.path.join(pack, from_)
    if not os.path.isfile(src):
        raise LayoutError(f"ignite workspace-tree: stub missing: {src}")
    pack_abs = os.path.abspath(pack)
    src_abs = os.path.abspath(src)
    if os.path.commonpath([pack_abs, src_abs]) != pack_abs:
        raise LayoutError(f"ignite workspace-tree: from escapes pack: {from_}")
    shutil.copyfile(src, dest)
