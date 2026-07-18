# Idle burn-in recipe wrapper.
#
#   .\run_burn_in.ps1                  # 10-minute default
#   .\run_burn_in.ps1 -Duration 600    # 10 minutes explicit
#   .\run_burn_in.ps1 -Duration 10800  # 3-hour long burn-in
#
# Exact Godot 4.2.2-stable must be on PATH or supplied with -Godot. This
# wrapper runs the source-project IdleProfile scene; it is not exported-build
# evidence. The log is written under user:// (on Windows:
# %APPDATA%\Godot\app_userdata\Buddy Runtime\perf\).

param(
    [int]$Duration = 600,
    [string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$runtime = Join-Path $PSScriptRoot ".."
$toolchainPath = Join-Path $runtime "toolchain.json"
$toolchain = Get-Content -Raw -LiteralPath $toolchainPath | ConvertFrom-Json
$expectedVersionPrefix = [string]$toolchain.reported_version_prefix

$versionOutput = @(& $Godot --version 2>&1)
$versionExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
$versionText = ($versionOutput -join "`n").Trim()
if ($versionExit -ne 0 -or -not $versionText.StartsWith($expectedVersionPrefix)) {
    Write-Error "Godot version mismatch: expected prefix '$expectedVersionPrefix', got exit=$versionExit output='$versionText'"
    exit 2
}
Write-Host "idle_profile: verified Godot $versionText"

$godotExit = 0
Push-Location $runtime
try {
    Write-Host "idle_profile: launching Godot for $Duration s..."
    & $Godot --headless --path . res://tests/IdleProfile.tscn -- "--duration=$Duration"
    $godotExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    Write-Host "idle_profile: godot exited with $godotExit"
} finally {
    Pop-Location
}

if ($godotExit -ne 0) {
    exit $godotExit
}
