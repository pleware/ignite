"""Minimal TOML subset parser for the keys a consumer ``ignite.toml`` uses.

The engine only ever reads a handful of shapes, and it must run on a bare
machine before any dependency is installed. So instead of pulling in a TOML
library it parses the subset itself — the same decision the shell kit already
made (``pins/read-ignite-toml.sh`` does it with awk).

Supported:
- full-line and trailing ``#`` comments,
- ``[section]`` table headers,
- ``key = value`` where the key is bare (``A-Za-z0-9_.@-``) or
  double-quoted (so ``"php@8.4"`` is a legal key), and the value is a
  double/single-quoted string, an inline array of quoted strings
  (``["a", "b"]``), or a bare scalar (``true`` / ``false`` / a number /
  a word).

Not supported (raises :class:`TomlError`): dotted keys, ``[[array]]`` tables,
multiline strings, and any value shape outside the list above. A malformed
policy file fails loudly instead of half-parsing.
"""

from __future__ import annotations

import re
from typing import Any, Dict

__all__ = ["loads", "TomlError"]


class TomlError(ValueError):
    """Raised when a TOML document does not fit the supported subset."""


# key = value; key is bare (chars incl. `.` `@` `-` `_`) or double-quoted.
_KEYVAL = re.compile(r'^([A-Za-z0-9_.@-]+|"[^"]*")[ \t]*=[ \t]*(.*)$')


def _strip_comment(line: str) -> str:
    in_s = False
    in_d = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        elif ch == "#" and not in_s and not in_d:
            return line[:i]
    return line


def _unquote(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1].replace('\\"', '"')
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        return s[1:-1]
    return s


def _split_flow(s: str):
    out = []
    buf = []
    in_q = False
    q = None
    for ch in s:
        if ch in "\"'":
            if in_q and q == ch:
                in_q = False
            elif not in_q:
                in_q = True
                q = ch
            buf.append(ch)
        elif ch == "," and not in_q:
            out.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if buf:
        out.append("".join(buf))
    return out


def _parse_value(raw: str) -> Any:
    raw = raw.strip()
    if raw == "":
        return ""
    if raw[0] in "\"'":
        return _unquote(raw)
    if raw[0] == "[":
        if raw[-1] != "]":
            raise TomlError(f"unterminated inline array: {raw!r}")
        inner = raw[1:-1].strip()
        if inner == "":
            return []
        return [_unquote(p) for p in _split_flow(inner)]
    return _unquote(raw)


def loads(text: str) -> Dict[str, Dict[str, Any]]:
    """Parse a TOML document into ``{section: {key: value}}``."""
    result: Dict[str, Dict[str, Any]] = {}
    section: str | None = None
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = _strip_comment(raw.rstrip())
        if not line.strip():
            continue
        stripped = line.strip()
        if stripped.startswith("["):
            if not stripped.endswith("]"):
                raise TomlError(f"line {lineno}: bad section header {stripped!r}")
            section = stripped[1:-1].strip()
            result.setdefault(section, {})
            continue
        m = _KEYVAL.match(stripped)
        if not m:
            raise TomlError(f"line {lineno}: cannot parse {stripped!r}")
        key = _unquote(m.group(1))
        value = _parse_value(m.group(2))
        if section is None:
            raise TomlError(f"line {lineno}: key {key!r} outside a section")
        result[section][key] = value
    return result
