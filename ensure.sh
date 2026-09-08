#!/bin/sh
# Plant the pinned uv, then hand off to the Python engine's `ensure` verb.
# Usage: sh ensure.sh [workspace] [tool ...]
# Extra tools (php@7.4) are installed after the file pins. No mani clones.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$SCRIPT_DIR
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/bootstrap.sh"

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
run_ignite ensure "$@"
