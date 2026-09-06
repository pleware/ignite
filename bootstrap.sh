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
. "$KIT_ROOT/pins/resolve-workspace.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/read-mani.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/workspace-paths.sh"

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

extract_archive() {
	archive=$1
	dest=$2
	mkdir -p "$dest"
	case "$archive" in
	*.zip)
		if ! command -v unzip >/dev/null 2>&1; then
			echo "bootstrap: unzip required for $archive (Git for Windows includes it)." >&2
			return 1
		fi
		unzip -q "$archive" -d "$dest"
		;;
	*.tar.gz)
		tar -xzf "$archive" -C "$dest"
		;;
	*.tar.xz)
		tar -xJf "$archive" -C "$dest"
		;;
	*)
		echo "bootstrap: unsupported archive: $archive" >&2
		return 1
		;;
	esac
}

plant_mise() {
	mise_dest="$STACK/mise/$PIN_MISE"
	if [ -x "$mise_dest/bin/mise" ] || [ -x "$mise_dest/bin/mise.exe" ]; then
		echo "bootstrap: mise $PIN_MISE already at $mise_dest"
		return 0
	fi

	case "$go_os-$go_arch" in
	windows-amd64)
		mise_file="mise-v${PIN_MISE}-windows-x64.zip"
		;;
	windows-arm64)
		mise_file="mise-v${PIN_MISE}-windows-arm64.zip"
		;;
	linux-amd64)
		mise_file="mise-v${PIN_MISE}-linux-x64.tar.gz"
		;;
	linux-arm64)
		mise_file="mise-v${PIN_MISE}-linux-arm64.tar.gz"
		;;
	darwin-amd64)
		mise_file="mise-v${PIN_MISE}-macos-x64.tar.gz"
		;;
	darwin-arm64)
		mise_file="mise-v${PIN_MISE}-macos-arm64.tar.gz"
		;;
	*)
		echo "bootstrap: no official mise $PIN_MISE for $go_os/$go_arch" >&2
		return 1
		;;
	esac

	mise_url="https://github.com/jdx/mise/releases/download/v${PIN_MISE}/${mise_file}"
	echo "bootstrap: fetching $mise_url"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fsSL -L -o "$tmp/$mise_file" "$mise_url"
	echo "bootstrap: extracting into $mise_dest"
	mkdir -p "$tmp/extract"
	extract_archive "$tmp/$mise_file" "$tmp/extract"
	found=""
	for candidate in \
		"$tmp/extract/mise.exe" \
		"$tmp/extract/mise" \
		"$tmp/extract"/mise/bin/mise.exe \
		"$tmp/extract"/mise/bin/mise \
		"$tmp/extract"/*/mise.exe \
		"$tmp/extract"/*/mise \
		"$tmp/extract"/*/bin/mise.exe \
		"$tmp/extract"/*/bin/mise; do
		if [ -f "$candidate" ]; then
			found=$candidate
			break
		fi
	done
	if [ -z "$found" ]; then
		found=$(find "$tmp/extract" -type f \( -name mise -o -name mise.exe \) 2>/dev/null | sed -n '1p')
	fi
	if [ -z "$found" ]; then
		echo "bootstrap: expected mise binary in archive" >&2
		return 1
	fi
	rm -rf "$mise_dest"
	mkdir -p "$mise_dest/bin"
	src_dir=$(CDPATH= cd -- "$(dirname -- "$found")" && pwd)
	if [ "$go_os" = windows ]; then
		mv "$found" "$mise_dest/bin/mise.exe"
	else
		mv "$found" "$mise_dest/bin/mise"
		chmod +x "$mise_dest/bin/mise"
	fi
	for extra in mise-shim.exe mise-shim; do
		if [ -f "$src_dir/$extra" ]; then
			mv "$src_dir/$extra" "$mise_dest/bin/$extra"
			if [ "$go_os" != windows ]; then
				chmod +x "$mise_dest/bin/$extra"
			fi
		fi
	done
	rm -rf "$tmp"
	trap - EXIT
	echo "bootstrap: planted mise $PIN_MISE"
}

run_mise_install() {
	mise_bin="$STACK/mise/$PIN_MISE/bin/mise"
	if [ -x "${mise_bin}.exe" ]; then
		mise_bin="${mise_bin}.exe"
	fi
	if [ ! -x "$mise_bin" ]; then
		echo "bootstrap: mise binary missing; plant_mise failed" >&2
		return 1
	fi
	if [ ! -f "$WORKSPACE_ROOT/mise.toml" ]; then
		echo "bootstrap: missing $WORKSPACE_ROOT/mise.toml" >&2
		return 1
	fi
	export MISE_DATA_DIR="$TOOLCHAIN_ROOT/mise"
	export MISE_YES=1
	if [ -n "${GITHUB_TOKEN:-}" ] && [ -z "${MISE_GITHUB_TOKEN:-}" ]; then
		export MISE_GITHUB_TOKEN="$GITHUB_TOKEN"
	fi
	echo "bootstrap: mise install (pins in mise.toml) → $MISE_DATA_DIR"
	(
		cd "$WORKSPACE_ROOT" || exit 1
		"$mise_bin" trust "$WORKSPACE_ROOT/mise.toml"
		"$mise_bin" install
	)
	echo "bootstrap: mise install done"
}

need_cmd git
need_cmd curl
need_cmd tar
need_cmd uname

WORKSPACE_ROOT=$(resolve_workspace_root "${1:-}")
echo "bootstrap: workspace $WORKSPACE_ROOT"
echo "bootstrap: kit $KIT_ROOT"

load_ignite_config
TOOLCHAIN_ROOT=$(resolve_toolchain_root)
STACK="$TOOLCHAIN_ROOT/stack"
CACHE="$TOOLCHAIN_ROOT/cache"

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

os=$(uname -s | tr '[:upper:]' '[:lower:]')
arch=$(uname -m)

case "$os" in
mingw* | msys* | cygwin*) go_os=windows ;;
linux*) go_os=linux ;;
darwin*) go_os=darwin ;;
*)
	echo "bootstrap: unsupported uname -s: $(uname -s)" >&2
	exit 1
	;;
esac

case "$arch" in
x86_64 | amd64) go_arch=amd64 ;;
aarch64 | arm64) go_arch=arm64 ;;
*)
	echo "bootstrap: unsupported uname -m: $arch" >&2
	exit 1
	;;
esac

mkdir -p "$STACK/mise" "$CACHE/go" "$TOOLCHAIN_ROOT/mise"

plant_mise
run_mise_install

echo "bootstrap: done. Next:"
echo "  eval \"\$(sh $KIT_ROOT/env/env.sh)\""
echo "  mise --version"
echo "  mani --version"
