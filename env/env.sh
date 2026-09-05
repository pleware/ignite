#!/bin/sh
# Print exports for the planted toolchain. Usage: eval "$(sh env/env.sh)"
# Compilers come from mise shims (workspace mise.toml).
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/toolchain.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/resolve-workspace.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/workspace-paths.sh"

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
TOOLCHAIN_ROOT=$(resolve_toolchain_root)
MISE_DATA="$TOOLCHAIN_ROOT/mise"
MISE_BIN_DIR="$TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin"
GOCACHE_PIN="$TOOLCHAIN_ROOT/cache/go/build"
GOMODCACHE_PIN="$TOOLCHAIN_ROOT/cache/go/mod"

echo "export IGNITE_TOOLCHAIN_ROOT=\"$TOOLCHAIN_ROOT\""
echo "export MISE_DATA_DIR=\"$MISE_DATA\""
echo "unset GOROOT"
echo "export GOCACHE=\"$GOCACHE_PIN\""
echo "export GOMODCACHE=\"$GOMODCACHE_PIN\""
echo "export PATH=\"$MISE_DATA/shims:$MISE_BIN_DIR:\$PATH\""
