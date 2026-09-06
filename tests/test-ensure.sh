#!/bin/sh
# ensure.sh plants mise via an already-present stub and never clones mani.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/toolchain.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if sh "$KIT/ensure.sh" "$tmp" >"$tmp/out" 2>"$tmp/err"; then
	echo "ensure: expected missing ignite.toml to fail" >&2
	cat "$tmp/err" >&2
	exit 1
fi
grep -q "ignite: missing" "$tmp/err"

printf '# policy\n' >"$tmp/ignite.toml"
if sh "$KIT/ensure.sh" "$tmp" >"$tmp/out" 2>"$tmp/err"; then
	echo "ensure: expected missing mise.toml to fail" >&2
	cat "$tmp/err" >&2
	exit 1
fi
grep -q "mise.toml" "$tmp/err"

ws=$tmp/ws
mkdir -p "$ws"
printf '# policy\n' >"$ws/ignite.toml"
printf '[tools]\n' >"$ws/mise.toml"
cat >"$ws/mani.yaml" <<'EOF'
projects:
  should-not-clone:
    url: https://example.invalid/nope.git
    path: sibling
    sync: true
    required: true
EOF

export IGNITE_TOOLCHAIN_ROOT=$tmp/tc
mkdir -p "$IGNITE_TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin"
log=$tmp/mise.log
cat >"$IGNITE_TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin/mise" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$log"
EOF
chmod +x "$IGNITE_TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin/mise"

sh "$KIT/ensure.sh" "$ws" php@7.4 >"$tmp/out" 2>"$tmp/err"
test ! -d "$ws/sibling"
grep -q "trust " "$log"
grep -q "^install$" "$log"
grep -q "install php@7.4" "$log"

if grep -qE 'clone_repo|git clone' "$KIT/ensure.sh"; then
	echo "ensure: ensure.sh must not clone remotes" >&2
	exit 1
fi

echo "ensure: ok"
