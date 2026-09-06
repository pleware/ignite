#!/bin/sh
# Bootstrap must refuse a directory with no ignite.toml.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if sh "$KIT/bootstrap.sh" "$tmp" >"$tmp/out" 2>"$tmp/err"; then
	echo "bootstrap-missing-ignite-toml: expected failure" >&2
	cat "$tmp/err" >&2
	exit 1
fi
grep -q "ignite: missing" "$tmp/err"

echo "bootstrap-missing-ignite-toml: ok"
