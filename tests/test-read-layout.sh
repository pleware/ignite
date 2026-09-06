#!/bin/sh
# Parse examples/layouts/minimal.yaml into a directory dump.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/read-layout.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

parse_layout_to_dir "$KIT/examples/layouts/minimal.yaml" "$tmp"

test "$(cat "$tmp/schema")" = "ignite.layout/1"

# Canonical schema id.
tmp2=$(mktemp -d)
parse_layout_to_dir "$KIT/examples/workspace/workspace-layout.yaml" "$tmp2"
test "$(cat "$tmp2/schema")" = "ignite.workspace-tree/1"
test "$(tr '\n' ' ' <"$tmp/kinds" | sed 's/ $//')" = "notes leaf"

test "$(cat "$tmp/kind/notes/gitignore")" = "deny-by-default"
test "$(cat "$tmp/kind/notes/contains")" = "leaf"
test "$(cat "$tmp/kind/notes/markdown_forbid")" = "drafts/"
test "$(cat "$tmp/kind/notes/tree/001/path")" = "README.md"
test "$(cat "$tmp/kind/notes/tree/001/plant")" = "stub"
test "$(cat "$tmp/kind/notes/tree/001/from")" = "stubs/README.md"
test "$(cat "$tmp/kind/notes/tree/002/plant")" = "dir"
test "$(cat "$tmp/kind/notes/tree/003/plant")" = "absent"

test "$(cat "$tmp/kind/leaf/gitignore")" = "allow-by-default"
test "$(cat "$tmp/kind/leaf/gitignore_lines")" = "/drafts/"

bad=$(mktemp -d)
printf '%s\n' "schema: not-this" "kinds:" "  x:" >"$tmp/bad.yaml"
if parse_layout_to_dir "$tmp/bad.yaml" "$bad"; then
	echo "read-layout: expected schema failure" >&2
	exit 1
fi

echo "read-layout: ok"
