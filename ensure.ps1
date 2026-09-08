# Plant the pinned uv, then hand off to the Python engine's `ensure` verb.
# Usage: .\ensure.ps1 [workspace] [tool ...]
# Extra tools (php@7.4) are installed after the file pins. No mani clones.
$ErrorActionPreference = "Stop"
$KIT_ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $KIT_ROOT "pins/bootstrap.ps1")

$script:WORKSPACE_ROOT = Resolve-IgniteWorkspaceRoot $args[0]
run_ignite ensure @args
