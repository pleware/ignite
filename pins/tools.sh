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
PIN_POSTGRES_MCP=0.1.0

EXTRA_TOOL_KEYS="POSTGRES_MCP"

# Graphify is deliberately absent. It is a user/system CLI shared by every
# workspace (`uv tool install graphifyy[...]`), not a workspace toolchain pin.
# Agent/MCP configs call `graphify` and `graphify-mcp` from PATH.

# postgres-mcp: read-only Postgres MCP. Not on PyPI yet, so pinned to a git tag.
TOOL_POSTGRES_MCP_SPEC="git+https://github.com/pleware/postgres-mcp.git@v$PIN_POSTGRES_MCP"
TOOL_POSTGRES_MCP_ENV=postgres-mcp
