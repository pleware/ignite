# Agents

This repository is the **ignite kit** (`https://github.com/pleware/ignite`).

Commit product files here. Do not commit consuming workspaces
(`my-developer-workspace`, `initagent-workspace`, MassTrade) from this tree.

Language pins belong in the consumer `mise.toml`. Ignite policy belongs in
`ignite.toml`. Do not put either inside `.ignite/`.

Ignite does not plant Docker, Postgres, or other services. Those run only
through Compose in the owning workspace (infra-dev, ops guest, product
testdata) — never as toolchain binaries.
