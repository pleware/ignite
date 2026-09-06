# ignite

[![CI](https://github.com/pleware/ignite/actions/workflows/ci.yml/badge.svg)](https://github.com/pleware/ignite/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/pleware/ignite/branch/main/graph/badge.svg)](https://codecov.io/gh/pleware/ignite)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

Workspace toolchain bootstrapper. It plants [mise](https://mise.jdx.dev),
then mise plants languages and [mani](https://github.com/alajmo/mani) from
the consuming workspace's `mise.toml`. It is not OpenCode ([agentize](https://github.com/pleware/agentize)).

This repository is the **kit**. A company workspace (binder, MassTrade,
initagent, …) is the **consumer**. Ignite does not live inside that tree as
a nested `*-developer` folder.

Chicken-egg: first plant needs **git + curl** (Windows: Git Bash). Not
system Go, Python, or Node. Mani and mise are outputs of bootstrap, not
inputs.

## Consumer layout

Same shape as mise: a committed TOML at the workspace root, plus a local
directory for the working copy.

```text
<workspace>/
  mani.yaml                 # repo registry (optional clones)
  mise.toml                 # language pins (mise)
  ignite.toml               # ignite policy — commit this ([kit] pin for a fleet)
  workspace-layout.yaml     # optional workspace-tree document (kinds are data)
  .ignite/                  # working copy / planted toolchain — gitignore this
```

Do not use `.mise.toml`, `.tool-versions`, `rtx.toml`, `.ignite.toml`,
`ignite.yaml`, or `.settings.ignite.yaml`. Do not put `GIT_AUTHOR_*` in
mise `[env]`.

Example files: [`examples/workspace/`](examples/workspace/).

## Bootstrap

From the **workspace** (or pass its path):

```sh
sh /path/to/ignite/bootstrap.sh
# or
sh /path/to/ignite/bootstrap.sh /path/to/workspace
```

Windows PowerShell:

```powershell
.\bootstrap.ps1
.\bootstrap.ps1 D:\path\to\workspace
```

Then:

```sh
eval "$(sh /path/to/ignite/env/env.sh)"
mise --version
mani --version
```

`.gitignore` on the consumer: `.ignite/` (the whole working copy). Policy
stays in `ignite.toml`.

## Workspace tree

Ignite does not ship binder / workspace / product profiles. It implements
verbs from schema [`schema/layout.v1.json`](schema/layout.v1.json)
(`ignite.workspace-tree/1`): `dir`, `stub`, `absent`. Kinds are names in a
YAML document the consumer writes. Anyone can ship their own file.

`ignite.layout/1`, `[layout]`, `--layout`, and `layout.sh` are aliases.

```toml
# ignite.toml
[workspace-tree]
file = "workspace-layout.yaml"
kind = "notes"
```

```sh
sh /path/to/ignite/workspace-tree.sh analyze
sh /path/to/ignite/workspace-tree.sh init --kind leaf --dest ./app
# or without ignite.toml:
sh /path/to/ignite/workspace-tree.sh analyze --tree ./workspace-layout.yaml --kind notes --dest .
```

Windows: `.\workspace-tree.ps1` with the same arguments.

A generic pack: [`examples/layouts/minimal.yaml`](examples/layouts/minimal.yaml)
(still uses the `ignite.layout/1` alias). Canonical id:
`ignite.workspace-tree/1`.

## What v0 does

1. Require `ignite.toml`. Cache is always `.ignite/`.
2. Clone `mani.yaml` projects with `sync: true` (`required` tag fails hard).
3. Plant the mise binary (`pins/toolchain.sh` → `PIN_MISE`).
4. `mise trust` + `mise install` from `mise.toml`.
5. `workspace-tree.sh analyze` / `init` against a consumer kind document.

`ensure.sh` (Windows: `ensure.ps1`) is steps 3–4 only — no `mani.yaml` clones.
Pass extra tool names after the workspace path (`php@7.4`) when a slug needs
a pin that is not the default in `mise.toml`. Agentize calls this on `run`.

Not in v0: Python `doctor` / TUI, git hooks, inspiration clones.
Not in this kit: Docker, Postgres, Redis, LiteLLM, or any service plant.
Local containers are Compose-only in the consumer tree. LiteLLM is hosted
externally — ignite does not plant a proxy.

## Tests

Git Bash / POSIX sh, from this repo:

```sh
sh tests/run.sh
```
