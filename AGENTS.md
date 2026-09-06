# Agents

This repository is the **ignite kit** (`https://github.com/pleware/ignite`).

Commit product files here. Do not commit consuming workspaces
(`my-developer-workspace`, `initagent-workspace`, MassTrade) from this tree.

Language pins belong in the consumer `mise.toml`. Ignite policy belongs in
`ignite.toml`. Do not put either inside `.ignite/`. Optional `[kit] pin`
(and `url`) is the git ref a consumer or agentize clones when the kit is
missing on this machine. Do not float `main` on a fleet — pin a commit.

Workspace-tree kinds are not part of this kit. The engine is
`workspace-tree.sh` plus `schema/layout.v1.json`. A consumer commits its
own `workspace-layout.yaml` (or any path in `[workspace-tree] file`).
`layout.sh`, `[layout]`, and `ignite.layout/1` are aliases. Do not add
binder / workspace / product as built-in profiles.

Ignite does not plant Docker, Postgres, Redis, LiteLLM, or other services.
Postgres and Redis may run in the consumer's **Compose** (Horizon, infra-dev,
tests). LiteLLM is hosted externally (URL + credentials) — not Compose, not
a toolchain binary.

Intelephense and PHPantom are not ignite plants. PHP products pin them in
**their** `mise.toml`. Agentize names the command and, on `run --agent`,
calls `ensure.sh` so mise installs those pins. Do not clone `mani.yaml`
from that path.

Graphify is a consumer pin (`pipx:graphifyy` in `mise.toml`), not an ignite
plant. Every product that uses the kit should pin it.
