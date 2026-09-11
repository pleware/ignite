# Sourced by ensure.sh, bootstrap.sh and env/env.sh. POSIX. No logic.
# Pinned CLI tools that mise does not carry (PyPI console scripts, planted by uv).
# Language pins stay in the consuming workspace mise.toml.
#
# EXTRA_TOOL_KEYS lists what ensure.sh installs. Per key:
#   TOOL_<KEY>_SPEC          uv tool install argument (a pinned requirement)
#   TOOL_<KEY>_ENV           the environment directory uv creates under UV_TOOL_DIR
#   TOOL_<KEY>_PYTHON_MARKER optional workspace file to receive that env's interpreter
#   TOOL_<KEY>_ROOT_MARKER   optional workspace file to receive the scan root (.)
#
# Keep PIN_UV in sync with an astral-sh/uv release tag (no leading v).

PIN_UV=0.12.3
PIN_GRAPHIFYY=0.9.51
PIN_POSTGRES_MCP=0.1.0

EXTRA_TOOL_KEYS="GRAPHIFYY POSTGRES_MCP"

# graphify reads its own interpreter back from graphify-out/.graphify_python:
# the git hooks probe that file first, so a machine without the launcher on
# PATH still rebuilds the graph.
TOOL_GRAPHIFYY_SPEC="graphifyy[ollama,sql]==$PIN_GRAPHIFYY"
TOOL_GRAPHIFYY_ENV=graphifyy
TOOL_GRAPHIFYY_PYTHON_MARKER=graphify-out/.graphify_python
TOOL_GRAPHIFYY_ROOT_MARKER=graphify-out/.graphify_root

# postgres-mcp: read-only Postgres MCP. Not on PyPI yet, so pinned to a git tag.
TOOL_POSTGRES_MCP_SPEC="git+https://github.com/pleware/postgres-mcp.git@v$PIN_POSTGRES_MCP"
TOOL_POSTGRES_MCP_ENV=postgres-mcp
