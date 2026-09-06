#!/bin/sh
# [layout] file / kind from ignite.toml. Comments-only stays empty.
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

echo "read-ignite-toml-layout: ok"
