"""``mani.yaml`` clone targets (port of ``pins/read-mani.sh``).

``bootstrap`` clones every project with ``sync: true`` (a ``required`` tag
fails hard; everything else is optional). ``path: "."`` (the umbrella itself)
is skipped.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

from . import _yaml

__all__ = ["clone_targets", "CloneTarget", "ManifestError"]


class ManifestError(RuntimeError):
    pass


@dataclass
class CloneTarget:
    key: str
    url: str
    dir: str
    required: bool


def clone_targets(workspace: str) -> list[CloneTarget]:
    path = os.path.join(workspace, "mani.yaml")
    if not os.path.isfile(path):
        return []
    data = _yaml.loads(_read(path))
    if not isinstance(data, dict):
        return []
    projects = data.get("projects") or {}
    out: list[CloneTarget] = []
    for key, project in projects.items():
        if not isinstance(project, dict):
            continue
        sync = project.get("sync")
        if sync is not True:
            continue
        dest = project.get("path") or ""
        if dest in ("", "."):
            continue
        url = project.get("url") or ""
        if not url:
            continue
        tags = project.get("tags") or []
        required = "required" in tags
        out.append(CloneTarget(key=key, url=url, dir=dest, required=required))
    return out


def _read(path: str) -> str:
    with open(path, encoding="utf-8") as fh:
        return fh.read()
