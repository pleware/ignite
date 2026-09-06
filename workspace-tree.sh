#!/bin/sh
# Apply or check a workspace-tree document (ignite.workspace-tree/1).
# ignite.layout/1, [layout], --layout, and layout.sh are still accepted.
# The kit ships verbs. Kinds live in the consumer YAML.
# POSIX sh: Git Bash (Windows), macOS bash 3.2, Ubuntu dash/sh.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KIT_ROOT=$SCRIPT_DIR
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/resolve-workspace.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/read-ignite-toml.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/read-layout.sh"
# shellcheck disable=SC1091
. "$KIT_ROOT/pins/layout-apply.sh"

usage() {
	cat <<'EOF'
usage:
  workspace-tree.sh analyze [--tree FILE] [--kind KIND] [--dest DIR] [workspace]
  workspace-tree.sh init    [--tree FILE] [--kind KIND] [--dest DIR] [--parent-kind KIND] [workspace]

Defaults come from <workspace>/ignite.toml [workspace-tree] (file, kind).
[layout] and --layout are aliases.
--dest defaults to the workspace root.
init --dest elsewhere checks --parent-kind (or the workspace kind) contains.
EOF
}

CMD=${1:-}
if [ -z "$CMD" ] || [ "$CMD" = "-h" ] || [ "$CMD" = "--help" ]; then
	usage
	if [ -z "$CMD" ]; then
		exit 1
	fi
	exit 0
fi
shift

LAYOUT_FILE_ARG=
KIND_ARG=
DEST_ARG=
PARENT_KIND_ARG=
WORKSPACE_ARG=

while [ "$#" -gt 0 ]; do
	case "$1" in
	--tree | --layout)
		LAYOUT_FILE_ARG=${2:-}
		shift 2
		;;
	--kind)
		KIND_ARG=${2:-}
		shift 2
		;;
	--dest)
		DEST_ARG=${2:-}
		shift 2
		;;
	--parent-kind)
		PARENT_KIND_ARG=${2:-}
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	-*)
		echo "ignite workspace-tree: unknown option $1" >&2
		usage >&2
		exit 1
		;;
	*)
		if [ -n "$WORKSPACE_ARG" ]; then
			echo "ignite workspace-tree: unexpected argument $1" >&2
			exit 1
		fi
		WORKSPACE_ARG=$1
		shift
		;;
	esac
done

case "$CMD" in
analyze | init) ;;
*)
	echo "ignite workspace-tree: unknown command $CMD" >&2
	usage >&2
	exit 1
	;;
esac

WORKSPACE_ROOT=
if [ -n "$WORKSPACE_ARG" ]; then
	WORKSPACE_ROOT=$(resolve_workspace_root "$WORKSPACE_ARG")
elif [ -n "${IGNITE_WORKSPACE:-}" ] || [ -f ./ignite.toml ] || [ -f ./mani.yaml ] || [ -f ./mise.toml ]; then
	WORKSPACE_ROOT=$(resolve_workspace_root "${WORKSPACE_ARG:-}")
fi

LAYOUT_FILE=
LAYOUT_KIND=
if [ -n "$WORKSPACE_ROOT" ] && [ -f "$WORKSPACE_ROOT/ignite.toml" ]; then
	load_ignite_config
	load_layout_policy
	if [ -n "${LAYOUT_FILE:-}" ] && [ -n "$WORKSPACE_ROOT" ]; then
		case "$LAYOUT_FILE" in
		/*) ;;
		*)
			LAYOUT_FILE="$WORKSPACE_ROOT/$LAYOUT_FILE"
			;;
		esac
	fi
fi

if [ -n "$LAYOUT_FILE_ARG" ]; then
	case "$LAYOUT_FILE_ARG" in
	/*)
		LAYOUT_FILE=$LAYOUT_FILE_ARG
		;;
	*)
		LAYOUT_FILE=$(CDPATH= cd -- "$(dirname -- "$LAYOUT_FILE_ARG")" && pwd)/$(basename -- "$LAYOUT_FILE_ARG")
		;;
	esac
fi

if [ -n "$KIND_ARG" ]; then
	LAYOUT_KIND=$KIND_ARG
fi

if [ -z "$LAYOUT_FILE" ] || [ -z "$LAYOUT_KIND" ]; then
	echo "ignite workspace-tree: need --tree and --kind, or ignite.toml [workspace-tree]" >&2
	exit 1
fi

DEST=$WORKSPACE_ROOT
if [ -n "$DEST_ARG" ]; then
	mkdir -p "$DEST_ARG"
	DEST=$(CDPATH= cd -- "$DEST_ARG" && pwd)
elif [ -z "$DEST" ]; then
	echo "ignite workspace-tree: need --dest or a workspace" >&2
	exit 1
fi

PARENT_KIND=${PARENT_KIND_ARG:-${LAYOUT_KIND_FROM_TOML:-}}
if [ "$CMD" = init ] && [ -n "$WORKSPACE_ROOT" ] && [ "$DEST" != "$WORKSPACE_ROOT" ]; then
	if [ -z "$PARENT_KIND_ARG" ] && [ -n "${LAYOUT_KIND_FROM_TOML:-}" ]; then
		PARENT_KIND=$LAYOUT_KIND_FROM_TOML
	fi
	if [ -n "$PARENT_KIND" ] && [ "$PARENT_KIND" != "$LAYOUT_KIND" ]; then
		:
	fi
fi

LAYOUT_PACK=$(CDPATH= cd -- "$(dirname -- "$LAYOUT_FILE")" && pwd)
LAYOUT_DIR=$(mktemp -d)
trap 'rm -rf "$LAYOUT_DIR"' EXIT
parse_layout_to_dir "$LAYOUT_FILE" "$LAYOUT_DIR"

if [ "$CMD" = init ] && [ -n "$WORKSPACE_ROOT" ] && [ "$DEST" != "$WORKSPACE_ROOT" ]; then
	_parent=${PARENT_KIND_ARG:-${LAYOUT_KIND_FROM_TOML:-}}
	if [ -n "$_parent" ] && [ "$_parent" != "$LAYOUT_KIND" ]; then
		if ! layout_contains_kind "$_parent" "$LAYOUT_KIND"; then
			echo "ignite workspace-tree: kind '$LAYOUT_KIND' is not in contains of '$_parent'" >&2
			exit 1
		fi
	fi
fi

case "$CMD" in
analyze)
	layout_analyze "$DEST" "$LAYOUT_KIND"
	;;
init)
	layout_init "$DEST" "$LAYOUT_KIND" "$LAYOUT_PACK"
	;;
esac
