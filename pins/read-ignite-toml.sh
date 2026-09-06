# POSIX helpers: require <workspace>/ignite.toml.
# Requires WORKSPACE_ROOT. File may be comments-only.
# Optional [workspace-tree] (or [layout]) file / kind — kinds are not built into the kit.

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
# [workspace-tree] wins when both that and [layout] are present.
load_layout_policy() {
	LAYOUT_FILE=
	LAYOUT_KIND=
	LAYOUT_KIND_FROM_TOML=
	TREE_FILE=
	TREE_KIND=
	ALIAS_FILE=
	ALIAS_KIND=
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
			BEGIN { section = "" }
			{
				line = $0
				gsub(/\r/, "", line)
				t = trim(line)
				if (t ~ /^#/ || t == "") {
					next
				}
				if (t ~ /^\[/) {
					if (t == "[workspace-tree]") {
						section = "tree"
					} else if (t == "[layout]") {
						section = "alias"
					} else {
						section = ""
					}
					next
				}
				if (section == "") {
					next
				}
				if (t ~ /^file[[:space:]]*=/) {
					val = t
					sub(/^file[[:space:]]*=[[:space:]]*/, "", val)
					if (section == "tree") {
						printf "TREE_FILE=%s\n", unquote(val)
					} else {
						printf "ALIAS_FILE=%s\n", unquote(val)
					}
					next
				}
				if (t ~ /^kind[[:space:]]*=/) {
					val = t
					sub(/^kind[[:space:]]*=[[:space:]]*/, "", val)
					if (section == "tree") {
						printf "TREE_KIND=%s\n", unquote(val)
					} else {
						printf "ALIAS_KIND=%s\n", unquote(val)
					}
					next
				}
			}
		' "$config"
	)"
	if [ -n "${TREE_FILE:-}" ]; then
		LAYOUT_FILE=$TREE_FILE
	elif [ -n "${ALIAS_FILE:-}" ]; then
		LAYOUT_FILE=$ALIAS_FILE
	fi
	if [ -n "${TREE_KIND:-}" ]; then
		LAYOUT_KIND=$TREE_KIND
		LAYOUT_KIND_FROM_TOML=$TREE_KIND
	elif [ -n "${ALIAS_KIND:-}" ]; then
		LAYOUT_KIND=$ALIAS_KIND
		LAYOUT_KIND_FROM_TOML=$ALIAS_KIND
	fi
}

# Sets KIT_PIN, KIT_URL. [kit] is optional. pin is required when the section
# is present. url defaults to the public kit remote.
DEFAULT_KIT_URL=https://github.com/pleware/ignite.git

load_kit_policy() {
	KIT_PIN=
	KIT_URL=
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
			BEGIN { section = "" }
			{
				line = $0
				gsub(/\r/, "", line)
				t = trim(line)
				if (t ~ /^#/ || t == "") {
					next
				}
				if (t ~ /^\[/) {
					if (t == "[kit]") {
						section = "kit"
					} else {
						section = ""
					}
					next
				}
				if (section != "kit") {
					next
				}
				if (t ~ /^pin[[:space:]]*=/) {
					val = t
					sub(/^pin[[:space:]]*=[[:space:]]*/, "", val)
					printf "KIT_PIN=%s\n", unquote(val)
					next
				}
				if (t ~ /^url[[:space:]]*=/) {
					val = t
					sub(/^url[[:space:]]*=[[:space:]]*/, "", val)
					printf "KIT_URL=%s\n", unquote(val)
					next
				}
			}
		' "$config"
	)"
	if [ -z "${KIT_PIN:-}" ] && [ -z "${KIT_URL:-}" ]; then
		return 0
	fi
	if [ -z "${KIT_PIN:-}" ]; then
		echo "ignite: $config [kit] needs pin (git tag, branch, or commit)" >&2
		return 1
	fi
	if [ -z "${KIT_URL:-}" ]; then
		KIT_URL=$DEFAULT_KIT_URL
	fi
}
