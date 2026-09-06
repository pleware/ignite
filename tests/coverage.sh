#!/bin/sh
# Run tests/run.sh under kcov. Linux CI only — Windows Git Bash has no kcov.
# Writes cobertura.xml for Codecov. Do not treat a coverage % as a kit gate.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${COVER_OUT:-"$ROOT/coverage"}

if ! command -v kcov >/dev/null 2>&1; then
	echo "coverage.sh: kcov is not installed" >&2
	exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT"

kcov \
	--include-path="$ROOT" \
	--exclude-pattern=/tests/,/examples/ \
	--bash-handle-sh-invocation \
	"$OUT" \
	bash "$ROOT/tests/run.sh"

if ! find "$OUT" -name cobertura.xml -print -quit | grep -q .; then
	echo "coverage.sh: kcov wrote no cobertura.xml under $OUT" >&2
	exit 1
fi

echo "coverage.sh: ok ($OUT)"
