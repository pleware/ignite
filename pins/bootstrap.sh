# Shared bootstrap trampoline. Sourced by ensure.sh / bootstrap.sh /
# workspace-tree.sh / env/env.sh.
#
# The shell is the *bootstrap* language, not the engine. Its only job is to
# turn git + curl into a Python interpreter, then hand off to the engine
# (src/ignite/): curl the pinned `uv` (layer 1), verify its checksum when one
# is pinned, and run the engine as a plain script on the pinned CPython.
#
# Expects KIT_ROOT and (optionally) WORKSPACE_ROOT to be set by the caller.
# WORKSPACE_ROOT may be empty for workspace-less verbs (workspace-tree with
# --tree/--kind/--dest and no ignite.toml).

. "$KIT_ROOT/pins/toolchain.sh"     # PIN_MISE
. "$KIT_ROOT/pins/tools.sh"         # PIN_UV, PIN_PYTHON, PIN_UV_SHA256, TOOL_*
. "$KIT_ROOT/pins/resolve-workspace.sh"

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

uv_binary() {
	uv_dest="$TOOLCHAIN_ROOT/stack/uv/$PIN_UV/bin"
	if [ -x "$uv_dest/uv.exe" ]; then
		printf '%s\n' "$uv_dest/uv.exe"
		return 0
	fi
	if [ -x "$uv_dest/uv" ]; then
		printf '%s\n' "$uv_dest/uv"
		return 0
	fi
	echo "ignite: uv binary missing; plant_uv failed" >&2
	return 1
}

plant_uv() {
	uv_dest="$TOOLCHAIN_ROOT/stack/uv/$PIN_UV"
	if [ -x "$uv_dest/bin/uv" ] || [ -x "$uv_dest/bin/uv.exe" ]; then
		echo "ignite: uv $PIN_UV already at $uv_dest"
		return 0
	fi

	case "$go_os-$go_arch" in
	windows-amd64)
		uv_file="uv-x86_64-pc-windows-msvc.zip"
		;;
	windows-arm64)
		uv_file="uv-aarch64-pc-windows-msvc.zip"
		;;
	linux-amd64)
		uv_file="uv-x86_64-unknown-linux-gnu.tar.gz"
		;;
	linux-arm64)
		uv_file="uv-aarch64-unknown-linux-gnu.tar.gz"
		;;
	darwin-amd64)
		uv_file="uv-x86_64-apple-darwin.tar.gz"
		;;
	darwin-arm64)
		uv_file="uv-aarch64-apple-darwin.tar.gz"
		;;
	*)
		echo "ignite: no official uv $PIN_UV for $go_os/$go_arch" >&2
		return 1
		;;
	esac

	uv_url="https://github.com/astral-sh/uv/releases/download/${PIN_UV}/${uv_file}"
	echo "ignite: fetching $uv_url"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fsSL -L -o "$tmp/$uv_file" "$uv_url"

	if [ -n "$PIN_UV_SHA256" ]; then
		actual=""
		if command -v sha256sum >/dev/null 2>&1; then
			actual=$(sha256sum "$tmp/$uv_file" | awk '{print $1}')
		elif command -v shasum >/dev/null 2>&1; then
			actual=$(shasum -a 256 "$tmp/$uv_file" | awk '{print $1}')
		fi
		if [ -z "$actual" ] || [ "$actual" != "$PIN_UV_SHA256" ]; then
			echo "ignite: uv checksum mismatch (expected $PIN_UV_SHA256, got ${actual:-<no sha tool>})" >&2
			return 1
		fi
	fi

	echo "ignite: extracting into $uv_dest"
	mkdir -p "$tmp/extract"
	extract_archive "$tmp/$uv_file" "$tmp/extract"
	found=""
	for candidate in \
		"$tmp/extract/uv.exe" \
		"$tmp/extract/uv" \
		"$tmp/extract"/*/uv.exe \
		"$tmp/extract"/*/uv; do
		if [ -f "$candidate" ]; then
			found=$candidate
			break
		fi
	done
	if [ -z "$found" ]; then
		found=$(find "$tmp/extract" -type f \( -name uv -o -name uv.exe \) 2>/dev/null | sed -n '1p')
	fi
	if [ -z "$found" ]; then
		echo "ignite: expected uv binary in archive" >&2
		return 1
	fi
	rm -rf "$uv_dest"
	mkdir -p "$uv_dest/bin"
	src_dir=$(CDPATH= cd -- "$(dirname -- "$found")" && pwd)
	if [ "$go_os" = windows ]; then
		mv "$found" "$uv_dest/bin/uv.exe"
	else
		mv "$found" "$uv_dest/bin/uv"
		chmod +x "$uv_dest/bin/uv"
	fi
	for extra in uvx uvx.exe uvw uvw.exe; do
		if [ -f "$src_dir/$extra" ]; then
			mv "$src_dir/$extra" "$uv_dest/bin/$extra"
			if [ "$go_os" != windows ]; then
				chmod +x "$uv_dest/bin/$extra"
			fi
		fi
	done
	rm -rf "$tmp"
	trap - EXIT
	echo "ignite: planted uv $PIN_UV"
}

# $1 = verb; the rest are engine arguments. Replaces the shell with the engine.
run_ignite() {
	_verb=$1
	shift

	if [ -n "${IGNITE_TOOLCHAIN_ROOT:-}" ]; then
		TOOLCHAIN_ROOT=$IGNITE_TOOLCHAIN_ROOT
	elif [ -n "${WORKSPACE_ROOT:-}" ]; then
		TOOLCHAIN_ROOT="$WORKSPACE_ROOT/.ignite"
	else
		# Workspace-less verbs (workspace-tree without ignite.toml) still need
		# layer-1 uv; use a machine fallback.
		TOOLCHAIN_ROOT="${IGNITE_UV_HOME:-$HOME/.ignite}"
	fi

	detect_platform
	plant_uv
	_uv=$(uv_binary)

	# The engine is a plain script, not an installed package: `uv venv` on
	# the pinned standalone CPython (fetched once, cached), then run that
	# interpreter directly. No build backend, no PyPI fetch beyond Python.
	_venv="$TOOLCHAIN_ROOT/venv/ignite-$PIN_PYTHON"
	if [ -x "$_venv/bin/python3" ]; then
		_py="$_venv/bin/python3"
	elif [ -x "$_venv/Scripts/python.exe" ]; then
		_py="$_venv/Scripts/python.exe"
	else
		"$_uv" venv --python "$PIN_PYTHON" "$_venv"
		if [ -x "$_venv/bin/python3" ]; then
			_py="$_venv/bin/python3"
		elif [ -x "$_venv/Scripts/python.exe" ]; then
			_py="$_venv/Scripts/python.exe"
		else
			echo "ignite: could not find python in $_venv" >&2
			return 1
		fi
	fi

	# Git Bash hands the engine (a Windows CPython) POSIX paths in env vars,
	# but env *values* are not auto-converted (only argv is). Emit native
	# F:\... paths for everything the engine reads so it never sees /f/... .
	if [ "$go_os" = windows ] && command -v cygpath >/dev/null 2>&1; then
		_kit_native=$(cygpath -w "$KIT_ROOT")
		_uv_native=$(cygpath -w "$_uv")
		_py_native=$(cygpath -w "$_py")
		_pypath="$_kit_native/src"
		_pysep=";"
	else
		_kit_native=$KIT_ROOT
		_uv_native=$_uv
		_py_native=$_py
		_pypath="$KIT_ROOT/src"
		_pysep=":"
	fi

	export IGNITE_KIT_ROOT="$_kit_native"
	export IGNITE_UV="$_uv_native"
	export PYTHONPATH="$_pypath${PYTHONPATH:+$_pysep$PYTHONPATH}"
	exec "$_py_native" -m ignite "$_verb" "$@"
}
