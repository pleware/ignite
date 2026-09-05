# POSIX helpers: read <workspace>/mani.yaml clone targets.
# Requires WORKSPACE_ROOT. No YAML library — bootstrap runs before Python.
# Extra keys (role, visibility, desc) are ignored.

_mani_path() {
	printf '%s\n' "$WORKSPACE_ROOT/mani.yaml"
}

# Emit shell assignments for bootstrap clone targets.
# Maps: url, path, sync → clone, tags containing "required" → required.
# Skips path "." (the umbrella itself).
emit_clone_repo_vars() {
	shared=$(_mani_path)
	if [ ! -f "$shared" ]; then
		echo "CLONE_SYNC_KEYS="
		return 0
	fi

	awk '
		function flush(    key) {
			if (repo == "" || clone != "true") {
				return
			}
			if (path == "." || path == "") {
				return
			}
			key = toupper(repo)
			gsub(/-/, "_", key)
			printf "CLONE_%s_URL=%s\n", key, url
			printf "CLONE_%s_DIR=%s\n", key, path
			printf "CLONE_%s_REQUIRED=%s\n", key, required
			if (sync_keys == "") {
				sync_keys = key
			} else {
				sync_keys = sync_keys " " key
			}
		}
		/^[a-zA-Z0-9_-]+:/ {
			key = $1
			sub(/:$/, "", key)
			if (key == "projects") {
				section = "projects"
				next
			}
			flush()
			section = "other"
			repo = ""
			next
		}
		section == "projects" && /^  [a-zA-Z0-9_-]+:[[:space:]]*$/ {
			flush()
			repo = $1
			sub(/:$/, "", repo)
			url = ""
			path = ""
			clone = "false"
			required = "false"
			next
		}
		section == "projects" && repo != "" && /^    url:/ {
			url = $0
			sub(/^    url:[[:space:]]*/, "", url)
			gsub(/^["'\'']|["'\'']$/, "", url)
			next
		}
		section == "projects" && repo != "" && /^    path:/ {
			path = $0
			sub(/^    path:[[:space:]]*/, "", path)
			gsub(/^["'\'']|["'\'']$/, "", path)
			next
		}
		section == "projects" && repo != "" && /^    sync:/ {
			clone = $0
			sub(/^    sync:[[:space:]]*/, "", clone)
			next
		}
		section == "projects" && repo != "" && /^    tags:/ {
			if ($0 ~ /required/) {
				required = "true"
			}
			next
		}
		END {
			flush()
			printf "CLONE_SYNC_KEYS=\"%s\"\n", sync_keys
		}
	' "$shared"
}

load_shared_clone_repos() {
	# shellcheck disable=SC2046
	eval "$(emit_clone_repo_vars)"
}
