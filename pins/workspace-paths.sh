# Sourced after WORKSPACE_ROOT is set.
# Machine files always live under <workspace>/.ignite/ (working copy / cache).
# Policy lives in ignite.toml. Override: IGNITE_TOOLCHAIN_ROOT (tests / one-off).

# shellcheck disable=SC1091
. "$KIT_ROOT/pins/read-ignite-toml.sh"

resolve_toolchain_root() {
	if [ -n "${IGNITE_TOOLCHAIN_ROOT:-}" ]; then
		printf '%s\n' "$IGNITE_TOOLCHAIN_ROOT"
		return 0
	fi
	printf '%s\n' "$WORKSPACE_ROOT/.ignite"
}
