# Plant uv and `uv tool install` the pins in pins/tools.sh. Sourced by
# ensure.sh and bootstrap.sh. Requires KIT_ROOT, PIN_UV, EXTRA_TOOL_KEYS,
# WORKSPACE_ROOT, STACK, TOOLCHAIN_ROOT, and detect_platform already run.

uv_tool_dir() {
	printf '%s\n' "$TOOLCHAIN_ROOT/uv-tools"
}

uv_binary() {
	uv_dest="$STACK/uv/$PIN_UV/bin"
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
	uv_dest="$STACK/uv/$PIN_UV"
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
	echo "ignite: extracting into $uv_dest"
	mkdir -p "$tmp/extract"
	extract_archive "$tmp/$uv_file" "$tmp/extract"
	# The Windows zip is flat; the tarballs carry a directory named after the
	# artifact. Same shape as plant_mise, so the same candidate walk applies.
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

# The environment uv built for this tool holds the interpreter the workspace
# probes back (graphify's hooks read graphify-out/.graphify_python). Writing it
# here is what keeps that discovery out of the consuming repo.
_tool_env_python() {
	env_root=$1
	for sub in Scripts/python.exe bin/python bin/python3; do
		if [ -x "$env_root/$sub" ] || [ -f "$env_root/$sub" ]; then
			printf '%s\n' "$env_root/$sub"
			return 0
		fi
	done
	return 1
}

# Git Bash hands us /f/work/repo, which only a POSIX shell can execute. The
# marker is also read by PowerShell (Windows is the main dev host), so emit the
# mixed form D:/work/repo — both shells run that.
_native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m -- "$1"
	else
		printf '%s\n' "$1"
	fi
}

_write_marker() {
	rel=$1
	value=$2
	target="$WORKSPACE_ROOT/$rel"
	mkdir -p "$(dirname -- "$target")"
	printf '%s\n' "$value" >"$target"
	echo "ignite: wrote $rel"
}

_write_tool_markers() {
	key=$1
	eval "env_dir=\${TOOL_${key}_ENV:-}"
	eval "py_marker=\${TOOL_${key}_PYTHON_MARKER:-}"
	eval "root_marker=\${TOOL_${key}_ROOT_MARKER:-}"
	if [ -z "$env_dir" ]; then
		return 0
	fi
	env_root="$(uv_tool_dir)/$env_dir"
	if [ -n "$py_marker" ]; then
		if py=$(_tool_env_python "$env_root"); then
			_write_marker "$py_marker" "$(_native_path "$py")"
		else
			echo "ignite: no interpreter under $env_root — skipped $py_marker" >&2
		fi
	fi
	if [ -n "$root_marker" ]; then
		# Relative on purpose: the graph is addressed from the workspace root,
		# so the file stays valid across clones and machines.
		_write_marker "$root_marker" "."
	fi
}

# uv reinstalls on --force, and these tools are large, so skip a tool whose
# receipt already names the pinned version.
_tool_is_current() {
	env_root=$1
	pin=$2
	receipt="$env_root/uv-receipt.toml"
	if [ -z "$pin" ] || [ ! -f "$receipt" ]; then
		return 1
	fi
	grep -q "$pin" "$receipt"
}

install_extra_tools() {
	if [ -z "${EXTRA_TOOL_KEYS:-}" ]; then
		return 0
	fi
	plant_uv
	uv_bin=$(uv_binary)
	UV_TOOL_DIR=$(uv_tool_dir)
	UV_TOOL_BIN_DIR="$UV_TOOL_DIR/bin"
	export UV_TOOL_DIR UV_TOOL_BIN_DIR
	mkdir -p "$UV_TOOL_BIN_DIR"

	for key in $EXTRA_TOOL_KEYS; do
		eval "spec=\${TOOL_${key}_SPEC:-}"
		eval "env_dir=\${TOOL_${key}_ENV:-}"
		if [ -z "$spec" ]; then
			echo "ignite: tool $key has no TOOL_${key}_SPEC — skipped" >&2
			continue
		fi
		# `graphifyy[extras]==0.9.51` → `0.9.51`. A spec without `==` never
		# matches a receipt, so an unpinned tool refreshes every run.
		pin=${spec##*==}
		if [ "$pin" = "$spec" ]; then
			pin=
		fi
		if [ -n "$env_dir" ] && _tool_is_current "$UV_TOOL_DIR/$env_dir" "$pin"; then
			echo "ignite: $spec already at $UV_TOOL_DIR/$env_dir"
			_write_tool_markers "$key"
			continue
		fi
		echo "ignite: uv tool install $spec → $UV_TOOL_DIR"
		eval "with=\${TOOL_${key}_WITH:-}"
		if [ -n "$with" ]; then
			"$uv_bin" tool install --force --with "$with" "$spec"
		else
			"$uv_bin" tool install --force "$spec"
		fi
		_write_tool_markers "$key"
	done
	echo "ignite: extra tools done"
}
