#!/bin/sh
# Print exports for the planted toolchain. Usage: eval "$(sh env/env.sh)"
# Thin trampoline: plant the pinned uv, then the engine prints the shim.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/bootstrap.sh"

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
run_ignite env "$@"
