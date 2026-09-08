#!/bin/sh
# Apply or check a workspace-tree document. Thin trampoline: plant the pinned
# uv, then hand off to the Python engine's `workspace-tree` verb.
# Usage: sh workspace-tree.sh analyze|init [--tree FILE] [--kind KIND] [--dest DIR] [--parent-kind KIND] [workspace]
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$SCRIPT_DIR
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/bootstrap.sh"

# workspace-tree may run without a workspace (--tree/--kind/--dest). Resolve
# one only if it is available; the engine re-resolves authoritatively.
WORKSPACE_ROOT=$(resolve_workspace_root "${IGNITE_WORKSPACE:-}" 2>/dev/null || true)
run_ignite workspace-tree "$@"
