# POSIX helpers: require <workspace>/ignite.toml.
# Requires WORKSPACE_ROOT. File may be comments-only.
# Optional [layout] file / kind — kinds are not built into the kit.

_ignite_toml_path() {
	printf '%s\n' "$WORKSPACE_ROOT/ignite.toml"
}

load_ignite_config() {
	config=$(_ignite_toml_path)
	if [ ! -f "$config" ]; then
		echo "ignite: missing $config" >&2
		return 1
	fi
}

# Sets LAYOUT_FILE, LAYOUT_KIND, LAYOUT_KIND_FROM_TOML (empty when absent).
load_layout_policy() {
	LAYOUT_FILE=
	LAYOUT_KIND=
	LAYOUT_KIND_FROM_TOML=
	config=$(_ignite_toml_path)
	if [ ! -f "$config" ]; then
		return 0
	fi
	# shellcheck disable=SC2046
	eval "$(
		awk '
			function trim(s) {
				gsub(/\r/, "", s)
				sub(/^[[:space:]]+/, "", s)
				sub(/[[:space:]]+$/, "", s)
				return s
			}
			function unquote(s) {
				s = trim(s)
				if ((s ~ /^".*"$/) || (s ~ /^'\''.*'\''$/)) {
					return substr(s, 2, length(s) - 2)
				}
				return s
			}
			BEGIN { in_layout = 0 }
			{
				line = $0
				gsub(/\r/, "", line)
				t = trim(line)
				if (t ~ /^#/ || t == "") {
					next
				}
				if (t ~ /^\[/) {
					in_layout = (t == "[layout]")
					next
				}
				if (!in_layout) {
					next
				}
				if (t ~ /^file[[:space:]]*=/) {
					val = t
					sub(/^file[[:space:]]*=[[:space:]]*/, "", val)
					printf "LAYOUT_FILE=%s\n", unquote(val)
					next
				}
				if (t ~ /^kind[[:space:]]*=/) {
					val = t
					sub(/^kind[[:space:]]*=[[:space:]]*/, "", val)
					printf "LAYOUT_KIND=%s\n", unquote(val)
					printf "LAYOUT_KIND_FROM_TOML=%s\n", unquote(val)
					next
				}
			}
		' "$config"
	)"
}
