# Kit tree

Two trees. Do not mix them.

1. **This kit** (this git repo) — source, cloned once per machine or per
   company tools checkout.
2. **The consumer working copy** (`<workspace>/.ignite/`) — binaries and
   other local files on *this* machine. Gitignored. Policy is `ignite.toml`
   at the workspace root, not a file inside `.ignite/`.

The **workspace tree** is a third thing: a consumer YAML of directory kinds
(`workspace-tree.sh`, schema `ignite.workspace-tree/1`). It is not this kit
tree and not `.ignite/`.

```
ignite/                          # this repository
├── README.md
├── LAYOUT.md
├── bootstrap.sh                 # trampoline: curl pinned uv → run engine
├── bootstrap.ps1                # PowerShell trampoline (same, native)
├── ensure.sh                    # trampoline: engine `ensure` (no clones)
├── ensure.ps1                   # PowerShell trampoline (same, native)
├── workspace-tree.sh            # trampoline: engine `workspace-tree`
├── workspace-tree.ps1           # PowerShell trampoline (same, native)
├── layout.sh                    # alias → workspace-tree.sh
├── layout.ps1                   # alias → workspace-tree.ps1
├── schema/layout.v1.json        # ignite.workspace-tree/1 — verbs, not kinds
├── pins/
│   ├── toolchain.sh             # PIN_MISE
│   ├── tools.sh                 # PIN_UV, PIN_PYTHON, PIN_UV_SHA256, TOOL_*
│   ├── resolve-workspace.sh     # cwd / $1 / IGNITE_WORKSPACE
│   ├── bootstrap.sh             # plant_uv + run_ignite (the sh trampoline)
│   └── bootstrap.ps1            # plant_uv + run_ignite (the ps1 trampoline)
├── src/ignite/                  # the Python engine — single source of logic
├── env/
│   └── env.sh                   # trampoline: engine `env` (eval-able PATH)
├── examples/workspace/          # copy these files to a consumer
├── examples/layouts/            # generic kind pack (not pware kinds)
└── tests/
```

Consumer after bootstrap:

```
<workspace>/
├── mani.yaml                    # committed
├── mise.toml                    # committed
├── ignite.toml                  # committed ([kit] pin optional)
└── .ignite/                     # gitignored
    ├── stack/uv/<PIN>/          # planted uv (layer 1 — the engine's host)
    ├── stack/mise/<PIN>/        # planted mise binary
    ├── mise/                    # MISE_DATA_DIR
    ├── venv/                    # the engine's pinned CPython environment
    ├── uv-tools/                # TOOL_* environments (uv tool install)
    └── cache/go/
```

`ignite which` / Python doctor land in a later slice. Until then, resolve
with `eval "$(sh env/env.sh)"` and `mise which`.
