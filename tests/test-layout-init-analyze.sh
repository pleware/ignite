#!/bin/sh
# init a kind, then analyze; absent paths and contains are enforced.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sh "$KIT/workspace-tree.sh" init \
	--tree "$KIT/examples/layouts/minimal.yaml" \
	--kind notes \
	--dest "$tmp/ws"

test -f "$tmp/ws/README.md"
test -d "$tmp/ws/notes"
test ! -e "$tmp/ws/drafts"
grep -Fxq '/*' "$tmp/ws/.gitignore"
grep -Fxq '!/README.md' "$tmp/ws/.gitignore"

sh "$KIT/layout.sh" analyze \
	--layout "$KIT/examples/layouts/minimal.yaml" \
	--kind notes \
	--dest "$tmp/ws"

# Forbidden / absent path.
mkdir -p "$tmp/ws/drafts"
if sh "$KIT/layout.sh" analyze \
	--layout "$KIT/examples/layouts/minimal.yaml" \
	--kind notes \
	--dest "$tmp/ws"; then
	echo "layout-init-analyze: expected fail when drafts/ exists" >&2
	exit 1
fi
rmdir "$tmp/ws/drafts"

# Child kind must be in contains.
if sh "$KIT/layout.sh" init \
	--layout "$KIT/examples/workspace/workspace-layout.yaml" \
	--kind leaf \
	--parent-kind notes \
	--dest "$tmp/ws/child" \
	"$KIT/examples/workspace"; then
	:
else
	echo "layout-init-analyze: leaf should be allowed under notes" >&2
	exit 1
fi
test -f "$tmp/ws/child/README.md"

if sh "$KIT/layout.sh" init \
	--layout "$KIT/examples/workspace/workspace-layout.yaml" \
	--kind notes \
	--parent-kind leaf \
	--dest "$tmp/ws/bad" \
	"$KIT/examples/workspace"; then
	echo "layout-init-analyze: notes must not be contained by leaf" >&2
	exit 1
fi

echo "layout-init-analyze: ok"
