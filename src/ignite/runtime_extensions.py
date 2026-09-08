"""Runtime extensions (draft 69): binary extensions baked into a runtime.

A runtime is one thing; the libraries and extensions loaded *into* it are
another. ``php@8.4`` is a mise tool; ``imagick`` is not. This module maps:

    runtime (php@8.4)  ->  extension (imagick)  ->  recipe (pecl | apt | dll)

``TOOL_*`` (family a: fleet-pinned CLI tools) and ``runtime-extensions``
(family c: binaries the product's code needs) are different objects and stay
two separate keys. GD is compiled into PHP, so it is the fallback when a
recipe is missing (documented in README).

The *plan* is pure (testable). The *apply* step is a thin edge that runs the
real package manager, and is stubbed in tests.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from typing import Callable, Optional

__all__ = ["RuntimeExtensionsError", "plan", "apply", "RECIPE_MAP"]

# recipe per (runtime, extension, os). ``None`` means "no recipe on this OS".
# The gap today is PHP-shaped: a few native binaries.
RECIPE_MAP: dict[str, dict[str, dict[str, Optional[str]]]] = {
    "php": {
        "imagick": {"linux": "pecl", "windows": "dll"},
        "pcntl": {"linux": "pecl", "windows": None},
        "posix": {"linux": "pecl", "windows": None},
        "redis": {"linux": "pecl", "windows": "dll"},
        "gd": {"linux": "builtin", "windows": "builtin"},
    },
}

KNOWN_RUNTIMES = frozenset(RECIPE_MAP)


class RuntimeExtensionsError(RuntimeError):
    pass


@dataclass
class Step:
    runtime: str
    extension: str
    os: str
    recipe: Optional[str]


@dataclass
class Plan:
    os: str = ""
    steps: list[Step] = field(default_factory=list)
    # (runtime, extension) pairs that have no recipe on this OS -> fall back.
    fallbacks: list[tuple[str, str]] = field(default_factory=list)


def _recipe(runtime: str, extension: str, go_os: str) -> Optional[str]:
    # The config key is a mise tool ("php@8.4"); the recipe map is keyed by
    # the runtime *family* ("php"). Strip the version suffix.
    base = runtime.split("@", 1)[0]
    table = RECIPE_MAP.get(base)
    if table is None:
        return None
    per_ext = table.get(extension)
    if per_ext is None:
        return None
    return per_ext.get(go_os)


def plan(runtime_extensions: dict[str, list[str]], go_os: str) -> Plan:
    """Resolve every declared extension to a recipe for this OS. Extensions
    without a recipe are collected as ``fallbacks`` (GD path), never merged
    into ``TOOL_*``."""
    result = Plan(os=go_os)
    for runtime, extensions in runtime_extensions.items():
        for extension in extensions:
            recipe = _recipe(runtime, extension, go_os)
            if recipe in (None, "builtin"):
                result.fallbacks.append((runtime, extension))
            else:
                result.steps.append(Step(runtime, extension, go_os, recipe))
    return result


def _command_for(step: Step, runtime_pecl: str) -> list[str]:
    """The concrete install command for a resolved step. ``pecl`` / ``apt`` /
    ``dll`` only; ``builtin`` never reaches here."""
    if step.recipe == "pecl":
        # pecl installs the extension into the runtime's own pecl. In a real
        # consumer the runtime provides ``pecl`` on PATH; the engine invokes
        # ``<runtime> pecl install <ext>``-style via the shim is out of scope
        # for the fallback path, so install through the ``pecl`` command.
        return ["pecl", "install", step.extension]
    if step.recipe == "apt":
        return ["apt-get", "install", "-y", f"php-{step.extension}"]
    if step.recipe == "dll":
        # Windows: copy the extension DLL next to the runtime and install
        # ImageMagick. Not wired to a real source yet (GD stays default).
        return ["ignite-dll", step.extension]
    raise RuntimeExtensionsError(
        f"ignite: unknown recipe {step.recipe!r} for {step.runtime} {step.extension}"
    )


def apply(
    plan: Plan,
    runner: Callable[[list[str]], None] | None = None,
    log: Callable[[str], None] | None = None,
) -> None:
    """Execute a plan. ``runner`` and ``log`` are injectable so tests can
    stub the package-manager edge without touching the network."""
    runner = runner or _default_runner
    log = log or (lambda msg: print(msg))
    for step in plan.steps:
        log(f"ignite: {step.runtime} {step.extension} ({step.recipe})")
        runner(_command_for(step, ""))
    for runtime, extension in plan.fallbacks:
        log(
            f"ignite: no {plan.os} recipe for {runtime} {extension} "
            f"— GD/fallback applies"
        )


def _default_runner(cmd: list[str]) -> None:
    subprocess.run(cmd, check=True)
