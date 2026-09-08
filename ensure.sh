#!/bin/sh
# Plant mise and `mise install` from mise.toml, then the CLI pins in
# pins/tools.sh. No mani clones.
# Usage: sh ensure.sh [workspace] [tool ...]
# Extra tools (php@7.4) are installed after the file pins.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$SCRIPT_DIR
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/toolchain.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/tools.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/resolve-workspace.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/workspace-paths.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/ensure-toolchain.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/ensure-tools.sh"

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "ensure: missing '$1'. Install git (Git for Windows includes curl) and retry." >&2
		exit 1
	fi
}

need_cmd curl
need_cmd tar
need_cmd uname

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
if [ "$#" -gt 0 ]; then
	shift
fi
echo "ensure: workspace $WORKSPACE_ROOT"
echo "ensure: kit $KIT_ROOT"

load_ignite_config
if [ ! -f "$WORKSPACE_ROOT/mise.toml" ]; then
	echo "ignite: missing $WORKSPACE_ROOT/mise.toml" >&2
	exit 1
fi

prepare_toolchain_dirs
detect_platform
plant_mise
run_mise_install "$@"
install_extra_tools

echo "ensure: done. Next:"
echo "  eval \"\$(sh $KIT_ROOT/env/env.sh)\""
