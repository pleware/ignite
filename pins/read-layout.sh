# POSIX helpers: parse an ignite.workspace-tree/1 YAML document into a directory.
# ignite.layout/1 is still accepted.
# No YAML library — same constraint as read-mani.sh (bootstrap before Python).
# Supported subset: block keys, 2-space indent, quoted or bare scalars.
# Block scalars, flow maps, and tags other than quoted "!" lines are out.

# $1 = layout yaml path
# $2 = empty output directory
parse_layout_to_dir() {
	_yaml=$1
	_out=$2
	if [ ! -f "$_yaml" ]; then
		echo "ignite workspace-tree: missing $_yaml" >&2
		return 1
	fi
	mkdir -p "$_out"
	awk -v out="$_out" '
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
		function mkdirp(p,    cmd, rc) {
			cmd = "mkdir -p \"" p "\""
			rc = system(cmd)
			if (rc != 0) {
				print "ignite workspace-tree: mkdir failed: " p > "/dev/stderr"
				exit 1
			}
		}
		function write_file(p, body) {
			print body > p
			close(p)
		}
		function append_file(p, body) {
			print body >> p
			close(p)
		}
		function reset_lists() {
			in_contains = 0
			in_allow = 0
			in_forbid = 0
			in_glines = 0
			in_tree = 0
		}
		function finish_tree_item() {
			if (kind == "" || tree_n == 0 || item_path == "") {
				return
			}
			if (item_plant == "") {
				print "ignite workspace-tree: tree item missing plant: " item_path > "/dev/stderr"
				exit 1
			}
			d = out "/kind/" kind "/tree/" sprintf("%03d", tree_n)
			mkdirp(d)
			write_file(d "/path", item_path)
			write_file(d "/plant", item_plant)
			if (item_from != "") {
				write_file(d "/from", item_from)
			}
			write_file(d "/required", item_required)
			item_path = ""
			item_plant = ""
			item_from = ""
			item_required = "true"
		}
		function start_kind(name) {
			finish_tree_item()
			if (name !~ /^[A-Za-z][A-Za-z0-9_-]*$/) {
				print "ignite workspace-tree: bad kind name: " name > "/dev/stderr"
				exit 1
			}
			kind = name
			tree_n = 0
			reset_lists()
			mkdirp(out "/kind/" kind)
			if (kinds == "") {
				kinds = name
			} else {
				kinds = kinds "\n" name
			}
		}
		BEGIN {
			schema = ""
			kind = ""
			kinds = ""
			tree_n = 0
			item_required = "true"
		}
		{
			line = $0
			gsub(/\r/, "", line)
			if (line ~ /^[[:space:]]*#/ || trim(line) == "") {
				next
			}
		}
		line ~ /^schema:[[:space:]]*/ {
			schema = unquote(substr(line, index(line, ":") + 1))
			next
		}
		line ~ /^kinds:[[:space:]]*$/ {
			in_kinds = 1
			next
		}
		in_kinds && line ~ /^  [A-Za-z][A-Za-z0-9_-]*:[[:space:]]*$/ {
			name = trim(line)
			sub(/:$/, "", name)
			start_kind(name)
			next
		}
		kind != "" && line ~ /^    gitignore:[[:space:]]*/ {
			reset_lists()
			finish_tree_item()
			val = unquote(substr(line, index(line, ":") + 1))
			if (val != "deny-by-default" && val != "allow-by-default") {
				print "ignite workspace-tree: gitignore must be deny-by-default or allow-by-default" > "/dev/stderr"
				exit 1
			}
			write_file(out "/kind/" kind "/gitignore", val)
			next
		}
		kind != "" && line ~ /^    contains:[[:space:]]*$/ {
			finish_tree_item()
			reset_lists()
			in_contains = 1
			next
		}
		kind != "" && line ~ /^    markdown_allow:[[:space:]]*$/ {
			finish_tree_item()
			reset_lists()
			in_allow = 1
			next
		}
		kind != "" && line ~ /^    markdown_forbid:[[:space:]]*$/ {
			finish_tree_item()
			reset_lists()
			in_forbid = 1
			next
		}
		kind != "" && line ~ /^    gitignore_lines:[[:space:]]*$/ {
			finish_tree_item()
			reset_lists()
			in_glines = 1
			next
		}
		kind != "" && line ~ /^    tree:[[:space:]]*$/ {
			finish_tree_item()
			reset_lists()
			in_tree = 1
			next
		}
		in_contains && line ~ /^      -[[:space:]]+/ {
			append_file(out "/kind/" kind "/contains", unquote(substr(line, index(line, "-") + 1)))
			next
		}
		in_allow && line ~ /^      -[[:space:]]+/ {
			append_file(out "/kind/" kind "/markdown_allow", unquote(substr(line, index(line, "-") + 1)))
			next
		}
		in_forbid && line ~ /^      -[[:space:]]+/ {
			append_file(out "/kind/" kind "/markdown_forbid", unquote(substr(line, index(line, "-") + 1)))
			next
		}
		in_glines && line ~ /^      -[[:space:]]+/ {
			append_file(out "/kind/" kind "/gitignore_lines", unquote(substr(line, index(line, "-") + 1)))
			next
		}
		in_tree && line ~ /^      -[[:space:]]+path:[[:space:]]*/ {
			finish_tree_item()
			tree_n++
			item_path = unquote(substr(line, index(line, ":") + 1))
			item_plant = ""
			item_from = ""
			item_required = "true"
			next
		}
		in_tree && line ~ /^        plant:[[:space:]]*/ {
			item_plant = unquote(substr(line, index(line, ":") + 1))
			if (item_plant != "dir" && item_plant != "stub" && item_plant != "absent") {
				print "ignite workspace-tree: plant must be dir, stub, or absent" > "/dev/stderr"
				exit 1
			}
			next
		}
		in_tree && line ~ /^        from:[[:space:]]*/ {
			item_from = unquote(substr(line, index(line, ":") + 1))
			next
		}
		in_tree && line ~ /^        required:[[:space:]]*/ {
			val = unquote(substr(line, index(line, ":") + 1))
			if (val == "false" || val == "no") {
				item_required = "false"
			} else {
				item_required = "true"
			}
			next
		}
		{
			print "ignite workspace-tree: unsupported line: " line > "/dev/stderr"
			exit 1
		}
		END {
			finish_tree_item()
			if (schema != "ignite.workspace-tree/1" && schema != "ignite.layout/1") {
				print "ignite workspace-tree: schema must be ignite.workspace-tree/1 (or ignite.layout/1; got \"" schema "\")" > "/dev/stderr"
				exit 1
			}
			if (kinds == "") {
				print "ignite workspace-tree: no kinds" > "/dev/stderr"
				exit 1
			}
			write_file(out "/schema", schema)
			write_file(out "/kinds", kinds)
		}
	' "$_yaml" || return 1
}
