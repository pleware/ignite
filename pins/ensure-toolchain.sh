# Plant mise and run `mise install`. Sourced by ensure.sh and bootstrap.sh.
# No mani clones. Requires KIT_ROOT, PIN_MISE, WORKSPACE_ROOT, STACK, TOOLCHAIN_ROOT.

detect_platform() {
	os=$(uname -s | tr '[:upper:]' '[:lower:]')
	arch=$(uname -m)

	case "$os" in
	mingw* | msys* | cygwin*) go_os=windows ;;
	linux*) go_os=linux ;;
	darwin*) go_os=darwin ;;
	*)
		echo "ignite: unsupported uname -s: $(uname -s)" >&2
		return 1
		;;
	esac

	case "$arch" in
	x86_64 | amd64) go_arch=amd64 ;;
	aarch64 | arm64) go_arch=arm64 ;;
	*)
		echo "ignite: unsupported uname -m: $(uname -m)" >&2
		return 1
		;;
	esac
}

extract_archive() {
	archive=$1
	dest=$2
	mkdir -p "$dest"
	case "$archive" in
	*.zip)
		if ! command -v unzip >/dev/null 2>&1; then
			echo "ignite: unzip required for $archive (Git for Windows includes it)." >&2
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
		echo "ignite: unsupported archive: $archive" >&2
		return 1
		;;
	esac
}

plant_mise() {
	mise_dest="$STACK/mise/$PIN_MISE"
	if [ -x "$mise_dest/bin/mise" ] || [ -x "$mise_dest/bin/mise.exe" ]; then
		echo "ignite: mise $PIN_MISE already at $mise_dest"
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
		echo "ignite: no official mise $PIN_MISE for $go_os/$go_arch" >&2
		return 1
		;;
	esac

	mise_url="https://github.com/jdx/mise/releases/download/v${PIN_MISE}/${mise_file}"
	echo "ignite: fetching $mise_url"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fsSL -L -o "$tmp/$mise_file" "$mise_url"
	echo "ignite: extracting into $mise_dest"
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
		echo "ignite: expected mise binary in archive" >&2
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
	echo "ignite: planted mise $PIN_MISE"
}

run_mise_install() {
	mise_bin="$STACK/mise/$PIN_MISE/bin/mise"
	if [ -x "${mise_bin}.exe" ]; then
		mise_bin="${mise_bin}.exe"
	fi
	if [ ! -x "$mise_bin" ]; then
		echo "ignite: mise binary missing; plant_mise failed" >&2
		return 1
	fi
	if [ ! -f "$WORKSPACE_ROOT/mise.toml" ]; then
		echo "ignite: missing $WORKSPACE_ROOT/mise.toml" >&2
		return 1
	fi
	export MISE_DATA_DIR="$TOOLCHAIN_ROOT/mise"
	export MISE_YES=1
	if [ -n "${GITHUB_TOKEN:-}" ] && [ -z "${MISE_GITHUB_TOKEN:-}" ]; then
		export MISE_GITHUB_TOKEN="$GITHUB_TOKEN"
	fi
	echo "ignite: mise install (pins in mise.toml) → $MISE_DATA_DIR"
	(
		cd "$WORKSPACE_ROOT" || exit 1
		"$mise_bin" trust "$WORKSPACE_ROOT/mise.toml"
		"$mise_bin" install
		for tool in "$@"; do
			"$mise_bin" install "$tool"
		done
	)
	echo "ignite: mise install done"
}

prepare_toolchain_dirs() {
	TOOLCHAIN_ROOT=$(resolve_toolchain_root)
	STACK="$TOOLCHAIN_ROOT/stack"
	CACHE="$TOOLCHAIN_ROOT/cache"
	mkdir -p "$STACK/mise" "$CACHE/go" "$TOOLCHAIN_ROOT/mise"
}
