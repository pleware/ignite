#!/bin/sh
# Workspace detection from $1, IGNITE_WORKSPACE, then cwd.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/resolve-workspace.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if resolve_workspace_root "$tmp" >/dev/null 2>&1; then
	:
else
	echo "resolve-workspace: explicit path must work even if empty" >&2
	exit 1
fi

got=$(
	cd "$KIT/examples/workspace" || exit 1
	resolve_workspace_root
)
want=$(CDPATH= cd -- "$KIT/examples/workspace" && pwd)
test "$got" = "$want"

echo "resolve-workspace: ok"
