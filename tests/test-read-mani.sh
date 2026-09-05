#!/bin/sh
# Parse examples/workspace/mani.yaml clone targets.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/read-mani.sh"

WORKSPACE_ROOT="$KIT/examples/workspace"
# shellcheck disable=SC2046
eval "$(emit_clone_repo_vars)"

test "$CLONE_PRODUCT_URL" = "https://example.com/example-product.git"
test "$CLONE_PRODUCT_DIR" = "example-product"
test "$CLONE_PRODUCT_REQUIRED" = "true"
test "$CLONE_OPTIONAL_OPS_URL" = "https://example.com/example-ops.git"
test "$CLONE_OPTIONAL_OPS_DIR" = "example-ops"
test "$CLONE_OPTIONAL_OPS_REQUIRED" = "false"
test "$CLONE_SYNC_KEYS" = "PRODUCT OPTIONAL_OPS"

if [ -n "${CLONE_WORKSPACE_URL:-}" ]; then
	echo "read-mani: workspace path . must not be a clone target" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
WORKSPACE_ROOT=$tmp
# shellcheck disable=SC2046
eval "$(emit_clone_repo_vars)"
test -z "${CLONE_SYNC_KEYS:-}"

echo "read-mani: ok"
