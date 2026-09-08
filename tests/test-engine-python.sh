#!/bin/sh
# Run the Python engine tests (hermetic: no network, no real mise/uv/pecl).
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Prefer `python` (real interpreter on Windows; `python3` is often the
# Microsoft Store stub) and verify it actually imports before using it.
PY=
for cand in python python3 py; do
	if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys' >/dev/null 2>&1; then
		PY=$cand
		break
	fi
done
if [ -z "$PY" ]; then
	echo "engine-python: no working python interpreter on PATH" >&2
	exit 1
fi

PYTHONPATH="$KIT/src" "$PY" "$KIT/tests/test_engine.py"
echo "engine-python: ok"
