# POSIX helpers: require <workspace>/ignite.toml.
# Requires WORKSPACE_ROOT. File may be comments-only for now.

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
