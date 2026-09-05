# Resolve the consuming workspace. This kit is not inside that tree.
# Order: $1, then IGNITE_WORKSPACE, then cwd if it looks like a workspace.

resolve_workspace_root() {
	_arg=${1:-}
	if [ -n "$_arg" ]; then
		CDPATH= cd -- "$_arg" && pwd
		return 0
	fi
	if [ -n "${IGNITE_WORKSPACE:-}" ]; then
		CDPATH= cd -- "$IGNITE_WORKSPACE" && pwd
		return 0
	fi
	if [ -f ./ignite.toml ] || [ -f ./mani.yaml ] || [ -f ./mise.toml ]; then
		pwd
		return 0
	fi
	echo "ignite: not a workspace (no ignite.toml, mani.yaml, or mise.toml)." >&2
	echo "ignite: cd to the workspace, set IGNITE_WORKSPACE, or pass the path." >&2
	return 1
}
