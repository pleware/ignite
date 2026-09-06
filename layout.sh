#!/bin/sh
# Alias. Prefer workspace-tree.sh (same as README: sh workspace-tree.sh).
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$SCRIPT_DIR/workspace-tree.sh" "$@"
