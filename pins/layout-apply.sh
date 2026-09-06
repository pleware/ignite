# POSIX: analyze / init a parsed ignite.layout/1 kind against a directory.

layout_rel_ok() {
	_p=$1
	case "$_p" in
	"" | /* | *\\*)
		return 1
		;;
	esac
	case "/$_p/" in
	*/./* | */../*)
		return 1
		;;
	esac
	return 0
}

layout_kind_dir() {
	printf '%s\n' "$LAYOUT_DIR/kind/$1"
}

layout_require_kind() {
	if [ ! -d "$(layout_kind_dir "$1")" ]; then
		echo "ignite layout: unknown kind '$1'" >&2
		echo "ignite layout: kinds:" >&2
		sed 's/^/  /' "$LAYOUT_DIR/kinds" >&2
		return 1
	fi
}

layout_contains_kind() {
	_parent=$1
	_child=$2
	_f=$(layout_kind_dir "$_parent")/contains
	if [ ! -f "$_f" ]; then
		return 1
	fi
	_c_line=
	while IFS= read -r _c_line || [ -n "$_c_line" ]; do
		if [ "$_c_line" = "$_child" ]; then
			return 0
		fi
	done <"$_f"
	return 1
}

layout_gitignore_has_line() {
	_gi=$1
	_want=$2
	if [ ! -f "$_gi" ]; then
		return 1
	fi
	_gi_line=
	while IFS= read -r _gi_line || [ -n "$_gi_line" ]; do
		_gi_line=$(printf '%s\n' "$_gi_line" | tr -d '\r')
		if [ "$_gi_line" = "$_want" ]; then
			return 0
		fi
	done <"$_gi"
	return 1
}

layout_copy_stub() {
	_from=$1
	_dest=$2
	_pack=$3
	if [ -z "$_from" ]; then
		printf '# %s\n' "$(basename "$_dest")" >"$_dest"
		return 0
	fi
	if ! layout_rel_ok "$_from"; then
		echo "ignite layout: bad from: $_from" >&2
		return 1
	fi
	_src="$_pack/$_from"
	if [ ! -f "$_src" ]; then
		echo "ignite layout: stub missing: $_src" >&2
		return 1
	fi
	# Keep the copy inside the pack (no .. after join).
	case "$_src" in
	"$_pack"/*) ;;
	*)
		echo "ignite layout: from escapes pack: $_from" >&2
		return 1
		;;
	esac
	cp "$_src" "$_dest"
}

layout_analyze() {
	_root=$1
	_kind=$2
	layout_require_kind "$_kind" || return 1
	_kd=$(layout_kind_dir "$_kind")
	_fail=0

	if [ -d "$_kd/tree" ]; then
		for _item in "$_kd"/tree/*; do
			[ -d "$_item" ] || continue
			_path=$(cat "$_item/path")
			_plant=$(cat "$_item/plant")
			_req=true
			if [ -f "$_item/required" ]; then
				_req=$(cat "$_item/required")
			fi
			if ! layout_rel_ok "$_path"; then
				echo "ignite layout: bad path: $_path" >&2
				_fail=1
				continue
			fi
			_target="$_root/$_path"
			case "$_plant" in
			dir)
				if [ "$_req" = true ] && [ ! -d "$_target" ]; then
					echo "ignite layout: missing dir $_path" >&2
					_fail=1
				fi
				;;
			stub)
				if [ "$_req" = true ] && [ ! -f "$_target" ]; then
					echo "ignite layout: missing file $_path" >&2
					_fail=1
				fi
				;;
			absent)
				if [ -e "$_target" ]; then
					echo "ignite layout: path should be absent: $_path" >&2
					_fail=1
				fi
				;;
			*)
				echo "ignite layout: unknown plant $_plant" >&2
				_fail=1
				;;
			esac
		done
	fi

	if [ -f "$_kd/markdown_forbid" ]; then
		_line=
		while IFS= read -r _line || [ -n "$_line" ]; do
			[ -n "$_line" ] || continue
			if ! layout_rel_ok "$_line"; then
				echo "ignite layout: bad markdown_forbid: $_line" >&2
				_fail=1
				continue
			fi
			if [ -e "$_root/$_line" ]; then
				echo "ignite layout: forbidden path exists: $_line" >&2
				_fail=1
			fi
		done <"$_kd/markdown_forbid"
	fi

	_gi="$_root/.gitignore"
	if [ -f "$_kd/gitignore" ]; then
		_mode=$(cat "$_kd/gitignore")
		if [ "$_mode" = deny-by-default ]; then
			if ! layout_gitignore_has_line "$_gi" "/*"; then
				echo "ignite layout: deny-by-default needs a /* line in .gitignore" >&2
				_fail=1
			fi
		fi
	fi
	if [ -f "$_kd/gitignore_lines" ]; then
		_line=
		while IFS= read -r _line || [ -n "$_line" ]; do
			[ -n "$_line" ] || continue
			if ! layout_gitignore_has_line "$_gi" "$_line"; then
				echo "ignite layout: .gitignore missing line: $_line" >&2
				_fail=1
			fi
		done <"$_kd/gitignore_lines"
	fi

	if [ "$_fail" -ne 0 ]; then
		return 1
	fi
	echo "ignite layout: analyze ok ($_kind @ $_root)"
}

layout_init() {
	_root=$1
	_kind=$2
	_pack=$3
	layout_require_kind "$_kind" || return 1
	_kd=$(layout_kind_dir "$_kind")
	mkdir -p "$_root"

	if [ -d "$_kd/tree" ]; then
		for _item in "$_kd"/tree/*; do
			[ -d "$_item" ] || continue
			_path=$(cat "$_item/path")
			_plant=$(cat "$_item/plant")
			_from=
			if [ -f "$_item/from" ]; then
				_from=$(cat "$_item/from")
			fi
			if ! layout_rel_ok "$_path"; then
				echo "ignite layout: bad path: $_path" >&2
				return 1
			fi
			_target="$_root/$_path"
			case "$_plant" in
			dir)
				mkdir -p "$_target"
				;;
			stub)
				mkdir -p "$(dirname "$_target")"
				if [ ! -e "$_target" ]; then
					layout_copy_stub "$_from" "$_target" "$_pack" || return 1
				fi
				;;
			absent)
				;;
			*)
				echo "ignite layout: unknown plant $_plant" >&2
				return 1
				;;
			esac
		done
	fi

	_gi="$_root/.gitignore"
	_need_gi=0
	if [ -f "$_kd/gitignore" ] && [ "$(cat "$_kd/gitignore")" = deny-by-default ]; then
		_need_gi=1
		if ! layout_gitignore_has_line "$_gi" "/*"; then
			if [ -f "$_gi" ]; then
				printf '%s\n' "/*" >>"$_gi"
			else
				printf '%s\n' "/*" >"$_gi"
			fi
		fi
	fi
	if [ -f "$_kd/gitignore_lines" ]; then
		_need_gi=1
		_line=
		while IFS= read -r _line || [ -n "$_line" ]; do
			[ -n "$_line" ] || continue
			if ! layout_gitignore_has_line "$_gi" "$_line"; then
				if [ -f "$_gi" ]; then
					printf '%s\n' "$_line" >>"$_gi"
				else
					printf '%s\n' "$_line" >"$_gi"
				fi
			fi
		done <"$_kd/gitignore_lines"
	fi
	if [ "$_need_gi" -eq 1 ]; then
		:
	fi
	echo "ignite layout: init ok ($_kind @ $_root)"
}
