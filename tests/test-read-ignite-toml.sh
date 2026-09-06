#!/bin/sh
# ignite.toml must exist; content may be comments-only.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/read-ignite-toml.sh"

WORKSPACE_ROOT="$KIT/examples/workspace"
load_ignite_config

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/ignite.toml" <<'EOF'
# empty policy
EOF
WORKSPACE_ROOT=$tmp
load_ignite_config

rm -f "$tmp/ignite.toml"
if load_ignite_config; then
	echo "read-ignite-toml: expected missing file to fail" >&2
	exit 1
fi

echo "read-ignite-toml: ok"
