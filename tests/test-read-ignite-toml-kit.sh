#!/bin/sh
# [kit] pin / url from ignite.toml. Section is optional.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/read-ignite-toml.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
WORKSPACE_ROOT=$tmp

printf '# no kit section\n' >"$tmp/ignite.toml"
load_kit_policy
test -z "${KIT_PIN:-}"
test -z "${KIT_URL:-}"

printf '%s\n' '[kit]' 'pin = "14a3b63"' >"$tmp/ignite.toml"
load_kit_policy
test "$KIT_PIN" = "14a3b63"
test "$KIT_URL" = "https://github.com/pleware/ignite.git"

printf '%s\n' '[kit]' 'pin = "v1"' 'url = "https://example.com/ignite.git"' >"$tmp/ignite.toml"
load_kit_policy
test "$KIT_PIN" = "v1"
test "$KIT_URL" = "https://example.com/ignite.git"

printf '%s\n' '[kit]' 'url = "https://example.com/ignite.git"' >"$tmp/ignite.toml"
if load_kit_policy; then
	echo "read-ignite-toml-kit: expected url-without-pin to fail" >&2
	exit 1
fi

echo "read-ignite-toml-kit: ok"
