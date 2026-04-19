# Idle burn-in recipe wrapper.
#
#   .\run_burn_in.ps1                  # 10-minute default
#   .\run_burn_in.ps1 -Duration 600    # 10 minutes explicit
#   .\run_burn_in.ps1 -Duration 10800  # 3-hour long burn-in
#
# The exported build or godot binary must be on PATH. Resulting log is
# written under user:// (on Windows: %APPDATA%\Godot\app_userdata\Buddy Runtime\perf\).

param(
    [int]$Duration = 600,
    [string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$runtime = Join-Path $PSScriptRoot ".."
Push-Location $runtime
try {
    Write-Host "idle_profile: launching Godot for $Duration s..."
    & $Godot --headless --path . res://tests/IdleProfile.tscn -- "--duration=$Duration"
    Write-Host "idle_profile: godot exited with $LASTEXITCODE"
} finally {
    Pop-Location
}
