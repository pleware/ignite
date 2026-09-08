#!/bin/sh
# The trampoline bootstraps the pinned uv with no preinstalled Python.
# Hermetic: no network. Exercises plant_uv's skip-when-present and
# checksum-mismatch paths; the real download is replaced by a stub curl.
#
# Note: the shell functions sourced below use `tmp` internally, so this
# script keeps its own scratch in `scratch` to avoid clobbering them.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

export KIT_ROOT=$KIT
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/toolchain.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/tools.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/bootstrap.sh"

export TOOLCHAIN_ROOT=$scratch/tc
detect_platform

# 1. Already-planted uv is a no-op (offline guard — no curl runs).
mkdir -p "$TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin"
printf '#!/bin/sh\nexit 0\n' >"$TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin/uv"
chmod +x "$TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin/uv"
if ! plant_uv >"$scratch/out" 2>&1; then
	echo "trampoline-uv: expected already-planted uv to succeed" >&2
	cat "$scratch/out" >&2
	exit 1
fi
grep -q "already at" "$scratch/out"

# 2. A pinned checksum that does not match the download fails loudly.
rm -rf "$TOOLCHAIN_ROOT/stack/uv"
PIN_UV_SHA256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef
mkdir -p "$scratch/bin"
cat >"$scratch/bin/curl" <<'EOF'
#!/bin/sh
# Write a fixed, wrong payload to the -o destination.
dest=
prev=
for a in "$@"; do
	if [ "$prev" = "-o" ]; then dest=$a; fi
	prev=$a
done
printf 'not-the-real-uv' >"$dest"
exit 0
EOF
chmod +x "$scratch/bin/curl"
PATH="$scratch/bin:$PATH"; export PATH
if plant_uv >"$scratch/out2" 2>&1; then
	echo "trampoline-uv: expected checksum mismatch to fail" >&2
	cat "$scratch/out2" >&2
	exit 1
fi
grep -q "checksum mismatch" "$scratch/out2"

echo "trampoline-uv: ok"
