#!/bin/sh
# Alias. Prefer workspace-tree.sh.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$SCRIPT_DIR/workspace-tree.sh" "$@"
