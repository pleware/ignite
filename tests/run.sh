#!/bin/sh
# Kit tests that do not plant mise (no network, no compiler downloads).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fail=0
for t in \
	"$ROOT/test-read-ignite-toml.sh" \
	"$ROOT/test-read-mani.sh" \
	"$ROOT/test-resolve-workspace.sh" \
	"$ROOT/test-bootstrap-missing-ignite-toml.sh"; do
	echo "run: $t"
	if ! sh "$t"; then
		echo "FAIL: $t" >&2
		fail=1
	fi
done
if [ "$fail" -ne 0 ]; then
	exit 1
fi
echo "tests/run.sh: ok"
