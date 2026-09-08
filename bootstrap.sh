#!/bin/sh
# Clone siblings from mani.yaml, plant mise, then `mise install` from mise.toml.
# Thin trampoline: plant the pinned uv, then hand off to the Python engine.
# Usage: sh bootstrap.sh [workspace]
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$SCRIPT_DIR
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/bootstrap.sh"

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
run_ignite bootstrap "$@"
