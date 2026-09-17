#!/bin/sh
# ensure.sh installs workspace-local CLI pins through an already-present uv stub.
# Graphify is intentionally not one of them: it is a user/system CLI on PATH.
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

# uv stub: record the arguments and make the environment layout uv would create.
uv_log=$tmp/uv.log
mkdir -p "$IGNITE_TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin"
cat >"$IGNITE_TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin/uv" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$uv_log"
printf '%s\n' "UV_TOOL_DIR=\$UV_TOOL_DIR" >>"$uv_log"
env_root="\$UV_TOOL_DIR/$TOOL_POSTGRES_MCP_ENV"
mkdir -p "\$env_root/bin"
printf 'requirements = ["postgres-mcp"]\n' >"\$env_root/uv-receipt.toml"
EOF
chmod +x "$IGNITE_TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin/uv"

sh "$KIT/ensure.sh" "$ws" >"$tmp/out" 2>"$tmp/err"

grep -q "tool install --force git+https://github.com/pleware/postgres-mcp.git@v$PIN_POSTGRES_MCP" "$uv_log"
grep -q "UV_TOOL_DIR=$IGNITE_TOOLCHAIN_ROOT/uv-tools" "$uv_log"
if grep -qi graphify "$uv_log"; then
  echo "ensure-tools: graphify must not be installed into a workspace tool dir" >&2
  exit 1
fi
test ! -e "$ws/graphify-out/.graphify_python"
test ! -e "$ws/graphify-out/.graphify_root"

# Git specifications have no `==` version marker, so ensure refreshes the tool
# on each run. It still must not install Graphify.
: >"$uv_log"
sh "$KIT/ensure.sh" "$ws" >"$tmp/out2" 2>"$tmp/err2"
grep -q "tool install --force git+https://github.com/pleware/postgres-mcp.git@v$PIN_POSTGRES_MCP" "$uv_log"
if grep -qi graphify "$uv_log"; then
  echo "ensure-tools: graphify must not be installed into a workspace tool dir" >&2
  exit 1
fi

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
