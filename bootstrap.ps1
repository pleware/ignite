# Clone siblings from mani.yaml, plant mise, then `mise install` from mise.toml.
# Thin trampoline: plant the pinned uv, then hand off to the Python engine.
# Usage: .\bootstrap.ps1 [workspace]
$ErrorActionPreference = "Stop"
$KIT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $KIT_ROOT "pins/bootstrap.ps1")

$script:WORKSPACE_ROOT = Resolve-IgniteWorkspaceRoot $args[0]
run_ignite bootstrap @args
