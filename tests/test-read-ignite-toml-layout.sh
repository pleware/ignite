#!/bin/sh
# [workspace-tree] file / kind from ignite.toml. [layout] is still accepted.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/read-ignite-toml.sh"

WORKSPACE_ROOT="$KIT/examples/workspace"
load_ignite_config
load_layout_policy
test "$LAYOUT_FILE" = "workspace-layout.yaml"
test "$LAYOUT_KIND" = "notes"
test "$LAYOUT_KIND_FROM_TOML" = "notes"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '# empty policy\n' >"$tmp/ignite.toml"
WORKSPACE_ROOT=$tmp
load_ignite_config
load_layout_policy
test -z "${LAYOUT_FILE:-}"
test -z "${LAYOUT_KIND:-}"

printf '%s\n' '[layout]' 'file = "old-name.yaml"' 'kind = "leaf"' >"$tmp/ignite.toml"
load_layout_policy
test "$LAYOUT_FILE" = "old-name.yaml"
test "$LAYOUT_KIND" = "leaf"

printf '%s\n' '[layout]' 'file = "old-name.yaml"' 'kind = "leaf"' \
	'[workspace-tree]' 'file = "new-name.yaml"' 'kind = "notes"' >"$tmp/ignite.toml"
load_layout_policy
test "$LAYOUT_FILE" = "new-name.yaml"
test "$LAYOUT_KIND" = "notes"

echo "read-ignite-toml-layout: ok"
