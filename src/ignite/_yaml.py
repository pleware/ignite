"""Minimal YAML subset parser for the documents ignite consumes.

Two documents are parsed: a ``mani.yaml`` clone registry and a
``workspace-tree`` kind document. Both are block-structured, 2-space
indented, and use only a small feature set. This parser covers exactly
that set (the same decision the shell kit made with ``pins/read-mani.sh``
and ``pins/read-layout.sh``):

- block mappings (``key: value``, and ``key:`` opening a nested map),
- block sequences of scalars (``- item``) and of single-key maps
  (``- key: value`` with further indented keys),
- flow sequences of scalars (``[a, b]``) for ``tags``.

No anchors, no multiline scalars, no flow mappings. Anything else raises
:class:`YamlError`.
"""

from __future__ import annotations

from typing import Any, List, Tuple

__all__ = ["loads", "YamlError"]


class YamlError(ValueError):
    """Raised when a YAML document does not fit the supported subset."""


def _strip_comment(line: str) -> str:
    in_s = False
    in_d = False
    for i, ch in enumerate(line):
        if ch == "'" and not in_d:
            in_s = not in_s
        elif ch == '"' and not in_s:
            in_d = not in_d
        elif ch == "#" and not in_s and not in_d:
            if i == 0 or line[i - 1] in " \t":
                return line[:i]
    return line


def _unquote(s: str) -> str:
    if len(s) >= 2 and s[0] == s[-1] and s[0] in "\"'":
        return s[1:-1]
    return s


def _split_flow(s: str) -> List[str]:
    out: List[str] = []
    buf: List[str] = []
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


def _scalar(s: str) -> Any:
    s = s.strip()
    if s == "":
        return ""
    if s[0] in "\"'":
        return _unquote(s)
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if inner == "":
            return []
        return [_scalar(p) for p in _split_flow(inner)]
    low = s.lower()
    if low == "true":
        return True
    if low == "false":
        return False
    if low in ("null", "~"):
        return None
    return s


def _find_colon(s: str) -> int:
    """Index of the first top-level ``:``, or -1."""
    depth = 0
    in_q = False
    q = None
    for i, ch in enumerate(s):
        if ch in "\"'":
            if in_q and q == ch:
                in_q = False
            elif not in_q:
                in_q = True
                q = ch
            continue
        if in_q:
            continue
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        elif ch == ":" and depth == 0:
            return i
    return -1


def _is_kv(s: str) -> bool:
    i = _find_colon(s)
    return i >= 0 and s[:i].strip() != ""


def _split_kv(s: str) -> Tuple[str, str]:
    i = _find_colon(s)
    if i < 0:
        return s, ""
    return s[:i].strip(), s[i + 1 :].strip()


def loads(text: str) -> Any:
    """Parse a YAML document into nested dicts/lists/scalars."""
    lines: List[Tuple[int, str]] = []
    for raw in text.splitlines():
        s = _strip_comment(raw).rstrip()
        if s.strip() == "":
            continue
        indent = len(s) - len(s.lstrip(" "))
        lines.append((indent, s.strip()))
    if not lines:
        return None

    pos = [0]

    def parse_block(indent: int) -> Any:
        if pos[0] >= len(lines):
            return None
        _, content = lines[pos[0]]
        if content.startswith("- "):
            return parse_list(lines[pos[0]][0])
        return parse_map(indent)

    def parse_list(indent: int) -> List[Any]:
        out: List[Any] = []
        while pos[0] < len(lines):
            ind, content = lines[pos[0]]
            if not content.startswith("- ") or ind != indent:
                break
            pos[0] += 1
            rest = content[2:].strip()
            if rest == "":
                if pos[0] < len(lines) and lines[pos[0]][0] > indent:
                    out.append(parse_block(lines[pos[0]][0]))
                else:
                    out.append(None)
            elif _is_kv(rest):
                k, v = _split_kv(rest)
                node = {k: parse_value(v, indent)}
                # A list item that is a map may carry further indented keys.
                while (
                    pos[0] < len(lines)
                    and lines[pos[0]][0] > indent
                    and _is_kv(lines[pos[0]][1])
                ):
                    k2, v2 = _split_kv(lines[pos[0]][1])
                    pos[0] += 1
                    node[k2] = parse_value(v2, indent)
                out.append(node)
            else:
                out.append(_scalar(rest))
        return out

    def parse_value(v: str, parent_indent: int) -> Any:
        if v == "":
            if pos[0] < len(lines) and lines[pos[0]][0] > parent_indent:
                return parse_block(lines[pos[0]][0])
            return None
        return _scalar(v)

    def parse_map(indent: int) -> dict:
        out: dict = {}
        while pos[0] < len(lines):
            ind, content = lines[pos[0]]
            if ind != indent:
                break
            if content.startswith("- "):
                break
            if not _is_kv(content):
                raise YamlError(f"expected `key: value`, got {content!r}")
            k, v = _split_kv(content)
            pos[0] += 1
            out[k] = parse_value(v, indent)
        return out

    return parse_block(lines[0][0])
