# Layout

Two trees. Do not mix them.

1. **This kit** (this git repo) — source, cloned once per machine or per
   company tools checkout.
2. **The consumer working copy** (`<workspace>/.ignite/`) — binaries and
   other local files on *this* machine. Gitignored. Policy is `ignite.toml`
   at the workspace root, not a file inside `.ignite/`.

```
ignite/                          # this repository
├── README.md
├── LAYOUT.md
├── bootstrap.sh                 # git + curl → mise → mise install
├── bootstrap.ps1                # Windows: Git Bash wrapper
├── layout.sh                    # analyze / init a consumer layout YAML
├── layout.ps1
├── schema/layout.v1.json        # ignite.layout/1 — verbs, not kinds
├── pins/
│   ├── toolchain.sh             # PIN_MISE only
│   ├── resolve-workspace.sh     # cwd / $1 / IGNITE_WORKSPACE
│   ├── read-ignite-toml.sh      # ignite.toml
│   ├── read-mani.sh             # mani.yaml clone targets
│   ├── workspace-paths.sh       # .ignite/ (or IGNITE_TOOLCHAIN_ROOT)
│   ├── read-layout.sh           # ignite.layout/1 YAML → directory dump
│   └── layout-apply.sh          # analyze / init
├── env/
│   └── env.sh                   # eval-able PATH / MISE_DATA_DIR / GOCACHE
├── examples/workspace/          # copy these files to a consumer
├── examples/layouts/            # generic layout pack (not pware kinds)
└── tests/
```

Consumer after bootstrap:

```
<workspace>/
├── mani.yaml                    # committed
├── mise.toml                    # committed
├── ignite.toml                  # committed
└── .ignite/                     # gitignored
    ├── stack/mise/<PIN>/        # planted mise binary
    ├── mise/                    # MISE_DATA_DIR
    └── cache/go/
```

`ignite which` / Python doctor land in a later slice. Until then, resolve
with `eval "$(sh env/env.sh)"` and `mise which`.
