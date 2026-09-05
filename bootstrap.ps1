# Find Git Bash and run the POSIX bootstrap. No install logic here.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$bashCandidates = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
    Write-Error "Git Bash not found. Install Git for Windows and retry."
}
& $bash (Join-Path $here "bootstrap.sh") @args
exit $LASTEXITCODE
