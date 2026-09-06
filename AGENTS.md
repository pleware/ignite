# Agents

This repository is the **ignite kit** (`https://github.com/pleware/ignite`).

Commit product files here. Do not commit consuming workspaces
(`my-developer-workspace`, `initagent-workspace`, MassTrade) from this tree.

Language pins belong in the consumer `mise.toml`. Ignite policy belongs in
`ignite.toml`. Do not put either inside `.ignite/`.

Layout kinds are not part of this kit. The engine is `layout.sh` plus
`schema/layout.v1.json`. A consumer commits its own `workspace-layout.yaml`
(or any path in `[layout] file`). Do not add binder / workspace / product
as built-in profiles.

Ignite does not plant Docker, Postgres, Redis, LiteLLM, or other services.
Postgres and Redis may run in the consumer's **Compose** (Horizon, infra-dev,
tests). LiteLLM is hosted externally (URL + credentials) — not Compose, not
a toolchain binary.

Intelephense is not an ignite plant. PHP products pin it in **their**
`mise.toml` (MassTrade: ERP, B2B hub, image workers).

Graphify is a consumer pin (`pipx:graphifyy` in `mise.toml`), not an ignite
plant. Every product that uses the kit should pin it.
