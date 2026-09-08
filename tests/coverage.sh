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

# The first command must be the script file. `kcov out bash tests/run.sh`
# traces the bash ELF (0 lines after --include-path) and Codecov stays at 0%.
kcov \
	--include-path="$ROOT" \
	--exclude-pattern=/tests/,/examples/ \
	--bash-handle-sh-invocation \
	--bash-parse-files-in-dir="$ROOT" \
	"$OUT" \
	"$ROOT/tests/run.sh"

xml=$OUT/cobertura.xml
if [ ! -f "$xml" ]; then
	# kcov 38 reports under <out>/<script>.<hash>/, and leaves kcov-merged
	# empty when it traced a single script. ci.yml and Codecov read the path
	# below, so publish the report there.
	for candidate in "$OUT/kcov-merged/cobertura.xml" $(find "$OUT" -name cobertura.xml -type f); do
		if [ -f "$candidate" ]; then
			cp "$candidate" "$xml"
			break
		fi
	done
fi
if [ ! -f "$xml" ]; then
	echo "coverage.sh: kcov wrote no $xml" >&2
	exit 1
fi
if ! grep -q 'lines-valid="[1-9]' "$xml"; then
	echo "coverage.sh: kcov reported zero kit lines (empty cobertura)" >&2
	exit 1
fi

echo "coverage.sh: ok ($OUT)"
