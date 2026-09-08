# Apply or check a workspace-tree document. Thin trampoline: plant the pinned
# uv, then hand off to the Python engine's `workspace-tree` verb.
# Usage: .\workspace-tree.ps1 analyze|init [--tree FILE] [--kind KIND] [--dest DIR] [--parent-kind KIND] [workspace]
$ErrorActionPreference = "Stop"
$KIT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $KIT_ROOT "pins/bootstrap.ps1")

# workspace-tree may run without a workspace (--tree/--kind/--dest). Resolve
# one only if it is available; the engine re-resolves authoritatively.
$script:WORKSPACE_ROOT = ""
if ($env:IGNITE_WORKSPACE) {
    try { $script:WORKSPACE_ROOT = Resolve-IgniteWorkspaceRoot $env:IGNITE_WORKSPACE } catch { }
}
run_ignite workspace-tree @args
