# Shared bootstrap trampoline for PowerShell. Dot-sourced by ensure.ps1 /
# bootstrap.ps1 / workspace-tree.ps1.
#
# PowerShell is the *bootstrap* language, not the engine. Its only job is to
# turn curl into the pinned static uv (layer 1), verify its checksum when one
# is pinned, then run the engine (src/ignite/) as a plain script on the pinned
# standalone CPython. Mirrors pins/bootstrap.sh — one source of logic, two
# thin host shells.
#
# Expects $KIT_ROOT (and, for ensure/bootstrap, $script:WORKSPACE_ROOT) to be
# set by the caller. The .ps1 trampolines are Windows-only, like ensure.ps1
# always was.

$ErrorActionPreference = "Stop"

function Get-IgnitePin {
    param([string]$Name, [string]$File)
    $content = Get-Content -Path $File -Raw
    if ($content -match "(?m)^${Name}=(.*)$") {
        return $Matches[1].Trim()
    }
    throw "ignite: missing ${Name} in ${File}"
}

$script:PIN_UV        = Get-IgnitePin "PIN_UV"        (Join-Path $KIT_ROOT "pins/tools.sh")
$script:PIN_PYTHON    = Get-IgnitePin "PIN_PYTHON"    (Join-Path $KIT_ROOT "pins/tools.sh")
$script:PIN_UV_SHA256 = Get-IgnitePin "PIN_UV_SHA256" (Join-Path $KIT_ROOT "pins/tools.sh")

function Resolve-IgniteWorkspaceRoot {
    param([string]$Arg)
    if ($Arg) {
        $p = Resolve-Path -LiteralPath $Arg -ErrorAction SilentlyContinue
        if ($p) { return $p.Path }
        throw "ignite: no such workspace directory: $Arg"
    }
    if ($env:IGNITE_WORKSPACE) {
        $p = Resolve-Path -LiteralPath $env:IGNITE_WORKSPACE -ErrorAction SilentlyContinue
        if ($p) { return $p.Path }
        throw "ignite: no such IGNITE_WORKSPACE: $env:IGNITE_WORKSPACE"
    }
    foreach ($m in @("ignite.toml", "mani.yaml", "mise.toml")) {
        if (Test-Path (Join-Path (Get-Location) $m)) {
            return (Get-Location).Path
        }
    }
    throw "ignite: not a workspace (no ignite.toml, mani.yaml, or mise.toml). cd to the workspace, set IGNITE_WORKSPACE, or pass the path."
}

function Detect-IgnitePlatform {
    $script:go_os = "windows"
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    switch ($arch.ToUpperInvariant()) {
        "AMD64" { $script:go_arch = "amd64" }
        "ARM64" { $script:go_arch = "arm64" }
        default { throw "ignite: unsupported architecture: $arch" }
    }
}

function Get-IgniteUvBinary {
    $exe = Join-Path $script:TOOLCHAIN_ROOT "stack/uv/$script:PIN_UV/bin/uv.exe"
    if (Test-Path $exe) { return $exe }
    throw "ignite: uv binary missing; plant_uv failed"
}

function Plant-IgniteUv {
    $uv_dest = Join-Path $script:TOOLCHAIN_ROOT "stack/uv/$script:PIN_UV"
    $uv_exe  = Join-Path $uv_dest "bin/uv.exe"
    if (Test-Path $uv_exe) {
        Write-Host "ignite: uv $script:PIN_UV already at $uv_dest"
        return
    }

    $file = switch ("$script:go_os-$script:go_arch") {
        "windows-amd64" { "uv-x86_64-pc-windows-msvc.zip" }
        "windows-arm64" { "uv-aarch64-pc-windows-msvc.zip" }
        default { throw "ignite: no official uv $script:PIN_UV for $script:go_os/$script:go_arch" }
    }
    $url = "https://github.com/astral-sh/uv/releases/download/$script:PIN_UV/$file"
    Write-Host "ignite: fetching $url"

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        $archive = Join-Path $tmp $file
        & curl.exe -fsSL -o $archive $url
        if ($LASTEXITCODE -ne 0) { throw "ignite: curl failed for $url" }

        if ($script:PIN_UV_SHA256) {
            $actual = (Get-FileHash -Algorithm SHA256 -Path $archive).Hash.ToLowerInvariant()
            if ($actual -ne $script:PIN_UV_SHA256.ToLowerInvariant()) {
                throw "ignite: uv checksum mismatch (expected $script:PIN_UV_SHA256, got $actual)"
            }
        }

        Write-Host "ignite: extracting into $uv_dest"
        $extract = Join-Path $tmp "extract"
        Expand-Archive -Path $archive -DestinationPath $extract -Force
        $found = Get-ChildItem -Path $extract -Recurse -Filter "uv.exe" | Select-Object -First 1
        if (-not $found) { throw "ignite: expected uv binary in archive" }

        if (Test-Path $uv_dest) { Remove-Item -Recurse -Force $uv_dest }
        New-Item -ItemType Directory -Path (Join-Path $uv_dest "bin") -Force | Out-Null
        Move-Item -Path $found.FullName -Destination $uv_exe

        # Carry companion binaries (uvx, uvw) from the same source dir.
        $srcDir = Split-Path -Parent $found.FullName
        foreach ($extra in @("uvx.exe", "uvw.exe")) {
            $extraPath = Join-Path $srcDir $extra
            if (Test-Path $extraPath) {
                Move-Item -Path $extraPath -Destination (Join-Path $uv_dest "bin/$extra")
            }
        }
        Write-Host "ignite: planted uv $script:PIN_UV"
    }
    finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

function run_ignite {
    param([string]$Verb)

    # The rest of the positional arguments are the engine's own arguments.
    $engineArgs = $args

    if ($env:IGNITE_TOOLCHAIN_ROOT) {
        $script:TOOLCHAIN_ROOT = $env:IGNITE_TOOLCHAIN_ROOT
    }
    elseif ($script:WORKSPACE_ROOT) {
        $script:TOOLCHAIN_ROOT = Join-Path $script:WORKSPACE_ROOT ".ignite"
    }
    else {
        # Workspace-less verbs (workspace-tree without ignite.toml) still need
        # layer-1 uv; use a machine fallback.
        $home = if ($env:IGNITE_UV_HOME) { $env:IGNITE_UV_HOME } else { Join-Path $env:USERPROFILE ".ignite" }
        $script:TOOLCHAIN_ROOT = $home
    }

    Detect-IgnitePlatform
    Plant-IgniteUv
    $uv = Get-IgniteUvBinary

    # The engine is a plain script, not an installed package: `uv venv` on
    # the pinned standalone CPython (fetched once, cached), then run that
    # interpreter directly. No build backend, no PyPI fetch beyond Python.
    $venv = Join-Path $script:TOOLCHAIN_ROOT "venv/ignite-$script:PIN_PYTHON"
    $py = Join-Path $venv "Scripts/python.exe"
    if (-not (Test-Path $py)) {
        & $uv venv --python $script:PIN_PYTHON $venv
        if ($LASTEXITCODE -ne 0) { throw "ignite: uv venv failed" }
    }

    $env:IGNITE_KIT_ROOT = $KIT_ROOT
    $env:IGNITE_UV = $uv
    $env:PYTHONPATH = Join-Path $KIT_ROOT "src"

    & $py -m ignite $Verb @engineArgs
    exit $LASTEXITCODE
}
