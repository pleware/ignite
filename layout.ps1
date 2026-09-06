# Alias. Prefer workspace-tree.ps1.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $here "workspace-tree.ps1") @args
exit $LASTEXITCODE
