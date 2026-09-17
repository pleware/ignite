# ignite

[![CI](https://github.com/pleware/ignite/actions/workflows/ci.yml/badge.svg)](https://github.com/pleware/ignite/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/pleware/ignite/branch/main/graph/badge.svg)](https://codecov.io/gh/pleware/ignite)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

Workspace toolchain bootstrapper. It plants [mise](https://mise.jdx.dev),
then mise plants languages and [mani](https://github.com/alajmo/mani) from
the consuming workspace's `mise.toml`. It is not an agent host
([agentize](https://github.com/pleware/agentize) calls this kit), and it
does not decide which skills may fire
([skillize](https://github.com/pleware/skillize) does that).

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

## Kit pin

The kit is this git repo. The consumer does not vendor it. A fleet machine
that has never seen ignite clones the ref in `[kit]`:

```toml
[kit]
pin = "fee062f"
# url defaults to https://github.com/pleware/ignite.git
```

`pin` is required when the section is present. Do not float `main` on a
fleet — twenty machines would drift. Agentize reads the same keys and clones
into `~/.agentize/ignite/<pin>/` (or `$AGENTIZE_HOME`).

## Ensure (no clones)

`bootstrap.sh` clones `mani.yaml` siblings, then plants mise. A bot start
must not clone the rest of the company.

```sh
sh /path/to/ignite/ensure.sh /path/to/workspace
sh /path/to/ignite/ensure.sh /path/to/workspace php@7.4 phpantom
```

Windows: `.\ensure.ps1` with the same arguments.

That is plant mise + `mise trust` + `mise install` from `mise.toml`. Extra
names after the workspace path install a pin that is not the default
(`php@7.4` next to `php@8.3`). Two versions in one checkout is a
`mise.toml` choice:

```toml
# mise.toml
[tools]
"php@7.4" = "7.4.33"
"php@8.3" = "8.3.6"
```

PATH afterwards:

```sh
eval "$(sh /path/to/ignite/env/env.sh)"
```

## Pinned CLI tools (kit-owned)

A PyPI console script that one workspace needs is a `mise.toml` line
(`"pipx:<package>" = "<version>"`). Two things move a tool out of the
consumer and into the kit: the pin has to be the same on every machine of a
fleet, or something has to know the path of the interpreter the tool runs on.

[`pins/tools.sh`](pins/tools.sh) holds workspace-local tools such as
`postgres-mcp`, and `bootstrap.sh` / `ensure.sh` plant them with `uv` after
`mise install`. **Graphify is deliberately not one of them.** It is installed
once in the user's system tool directory and shared by every workspace:

```sh
uv tool install --force \
  --with git+https://github.com/pleware/graphify-postpass.git@v0.1.0 \
  "graphifyy[openai,sql,mcp]"
```

That one environment owns `graphify`, `graphify-mcp` and graphify-postpass.
Agent/MCP configs call those executables from PATH; a consumer must not pin
`pipx:graphifyy` in `mise.toml`, use `uv run --with graphifyy`, or create a
workspace `.ignite/uv-tools/graphifyy` copy.

[graphify-workspace](https://github.com/pleware/graphify-workspace) merges
per-checkout graphs for an umbrella. Membership is a `graphify:` key on the
consumer `mani.yaml` (project keys, sibling registries, and optional `backend` /
`model` for Markdown). The API key is not in that file. The mani CLI ignores
unknown fields. Do not plant a host path or add a sidecar yaml; run the merge
kit from its checkout until it has a release.

Workspace-local tool environments still land in `.ignite/uv-tools/<TOOL_*_ENV>`
and launchers in `.ignite/uv-tools/bin` (on PATH via `env/env.sh`). A pinned
tool whose `uv-receipt.toml` names the version is skipped, so a second run is a
no-op. `TOOL_*_PYTHON_MARKER` and `TOOL_*_ROOT_MARKER` remain available for
future workspace-local tools that genuinely need them; Graphify does not.

## Workspace tree

Ignite does not ship binder / workspace / product profiles. It implements
verbs from schema [`schema/layout.v1.json`](schema/layout.v1.json)
(`ignite.workspace-tree/1`): `dir`, `stub`, `absent`. Kinds are names in a
YAML document the consumer writes. Anyone can ship their own file.

`ignite.layout/1`, `[layout]`, `--layout`, and `layout.sh` are aliases.

```toml
# ignite.toml — [kit] is documented above
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
5. Plant the CLI pins in `pins/tools.sh` with `uv` (`PIN_UV`).
6. `workspace-tree.sh analyze` / `init` against a consumer kind document.

`ensure.sh` is steps 3–5 only. Agentize `run --agent` calls it.

Not in v0: Python `doctor` / TUI, git hooks, inspiration clones.
Not in this kit: Docker, Postgres, Redis, LiteLLM, or any service plant.
Local containers are Compose-only in the consumer tree. LiteLLM is hosted
externally — ignite does not plant a proxy.

## Tests

Git Bash / POSIX sh, from this repo:

```sh
sh tests/run.sh
```
