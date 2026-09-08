#!/bin/sh
# Clone siblings from mani.yaml, plant mise, then `mise install` from mise.toml.
# Cache lands in .ignite/. Databases and LiteLLM are not part of this toolchain.
# POSIX sh: Git Bash (Windows), macOS bash 3.2, Ubuntu dash/sh.
#
# This kit is a separate git repo. The workspace is cwd, $1, or IGNITE_WORKSPACE.
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
. "$KIT_ROOT/pins/read-mani.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/workspace-paths.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/ensure-toolchain.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/ensure-tools.sh"

need_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "bootstrap: missing '$1'. Install git (Git for Windows includes curl) and retry." >&2
		exit 1
	fi
}

clone_repo() {
	url=$1
	dir=$2
	optional=$3
	dest="$WORKSPACE_ROOT/$dir"

	if [ -d "$dest/.git" ]; then
		echo "bootstrap: $dir already cloned"
		return 0
	fi

	if [ -d "$dest" ]; then
		if [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
			echo "bootstrap: $dir exists but is not a git repo — skip clone" >&2
			if [ "$optional" != optional ]; then
				return 1
			fi
			return 0
		fi
	fi

	echo "bootstrap: cloning $url -> $dir"
	if git clone "$url" "$dest"; then
		echo "bootstrap: cloned $dir"
		return 0
	fi

	if [ "$optional" = optional ]; then
		echo "bootstrap: warning: could not clone $dir (private repo or no auth)" >&2
		return 0
	fi

	echo "bootstrap: failed to clone $dir" >&2
	return 1
}

need_cmd git
need_cmd curl
need_cmd tar
need_cmd uname

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
echo "bootstrap: workspace $WORKSPACE_ROOT"
echo "bootstrap: kit $KIT_ROOT"

load_ignite_config
prepare_toolchain_dirs

if [ -f "$WORKSPACE_ROOT/mani.yaml" ]; then
	load_shared_clone_repos
	# shellcheck disable=SC2153
	for key in $CLONE_SYNC_KEYS; do
		eval "url=\$CLONE_${key}_URL"
		eval "dir=\$CLONE_${key}_DIR"
		eval "req=\$CLONE_${key}_REQUIRED"
		if [ -z "$url" ] || [ -z "$dir" ]; then
			continue
		fi
		if [ "$req" = true ]; then
			clone_repo "$url" "$dir" required
		else
			clone_repo "$url" "$dir" optional
		fi
	done
else
	echo "bootstrap: no mani.yaml — skip clones"
fi

detect_platform
plant_mise
run_mise_install
install_extra_tools

echo "bootstrap: done. Next:"
echo "  eval \"\$(sh $KIT_ROOT/env/env.sh)\""
echo "  mise --version"
echo "  mani --version"
