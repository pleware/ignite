#!/bin/sh
# ensure.sh installs the pins/tools.sh CLIs through an already-present uv stub
# and writes the workspace markers. No network, no real uv.
set -eu

KIT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$KIT/pins/toolchain.sh"
# shellcheck disable=SC1091
. "$KIT/pins/tools.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ws=$tmp/ws
mkdir -p "$ws"
printf '# policy\n' >"$ws/ignite.toml"
printf '[tools]\n' >"$ws/mise.toml"

export IGNITE_TOOLCHAIN_ROOT=$tmp/tc
mkdir -p "$IGNITE_TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin"
cat >"$IGNITE_TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin/mise" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$IGNITE_TOOLCHAIN_ROOT/stack/mise/$PIN_MISE/bin/mise"

# uv stub: record the arguments, then build the environment layout uv would
# create so the marker step has something real to find.
uv_log=$tmp/uv.log
mkdir -p "$IGNITE_TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin"
cat >"$IGNITE_TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin/uv" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$uv_log"
printf '%s\n' "UV_TOOL_DIR=\$UV_TOOL_DIR" >>"$uv_log"
env_root="\$UV_TOOL_DIR/$TOOL_GRAPHIFYY_ENV"
mkdir -p "\$env_root/bin"
printf '#!/bin/sh\n' >"\$env_root/bin/python"
chmod +x "\$env_root/bin/python"
printf 'requirements = ["graphifyy==%s"]\n' "$PIN_GRAPHIFYY" >"\$env_root/uv-receipt.toml"
EOF
chmod +x "$IGNITE_TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin/uv"

sh "$KIT/ensure.sh" "$ws" >"$tmp/out" 2>"$tmp/err"

grep -q "tool install --force graphifyy\[ollama,sql\]==$PIN_GRAPHIFYY" "$uv_log"
grep -q "UV_TOOL_DIR=$IGNITE_TOOLCHAIN_ROOT/uv-tools" "$uv_log"

# The interpreter marker is what the consuming repo's git hooks read.
test -f "$ws/$TOOL_GRAPHIFYY_PYTHON_MARKER"
grep -q "uv-tools/$TOOL_GRAPHIFYY_ENV/bin/python" "$ws/$TOOL_GRAPHIFYY_PYTHON_MARKER"
test "$(cat "$ws/$TOOL_GRAPHIFYY_ROOT_MARKER")" = "."

# Second run: the receipt already names the pin, so uv is not called again.
: >"$uv_log"
sh "$KIT/ensure.sh" "$ws" >"$tmp/out2" 2>"$tmp/err2"
if grep -q "tool install" "$uv_log"; then
	echo "ensure-tools: expected the pinned tool to be skipped on re-run" >&2
	exit 1
fi
grep -q "already at" "$tmp/out2"

# A workspace with no extra pins must not need uv at all.
bare=$tmp/bare
mkdir -p "$bare"
printf '# policy\n' >"$bare/ignite.toml"
printf '[tools]\n' >"$bare/mise.toml"
rm -rf "$IGNITE_TOOLCHAIN_ROOT/stack/uv"
sh -c '
	set -eu
	KIT_ROOT=$1
	ws=$2
	. "$KIT_ROOT/pins/toolchain.sh"
	. "$KIT_ROOT/pins/tools.sh"
	. "$KIT_ROOT/pins/resolve-workspace.sh"
	. "$KIT_ROOT/pins/workspace-paths.sh"
	. "$KIT_ROOT/pins/ensure-toolchain.sh"
	. "$KIT_ROOT/pins/ensure-tools.sh"
	WORKSPACE_ROOT=$ws
	prepare_toolchain_dirs
	EXTRA_TOOL_KEYS=
	install_extra_tools
' _ "$KIT" "$bare"
test ! -d "$bare/graphify-out"

echo "ensure-tools: ok"
