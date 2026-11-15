param(
    [switch]$Profile,
    [string]$Godot = "godot",
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$projectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
$runner = Join-Path $repoRoot "packages\content-validator\headless_suite.py"
$contract = Join-Path $PSScriptRoot "required_headless_scenes.json"
$toolchain = Join-Path $projectPath "toolchain.json"

Write-Host "Runtime project path: $projectPath"
& $Python $runner `
    --godot $Godot `
    --project $projectPath `
    --contract $contract `
    --toolchain $toolchain `
    --timeout 90
$suiteExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
if ($suiteExit -ne 0) {
    Write-Error "Required headless suite failed with exit $suiteExit"
    exit $suiteExit
}

if ($Profile) {
    Write-Host ""
    Write-Host "=== Frame-time profiling (20 actors, 300 frames; non-blocking) ==="
    & $Godot --headless --path $projectPath res://tests/ProfileScene.tscn
    Write-Host "Profiling run exited with $LASTEXITCODE (non-blocking)."
}

Write-Host "All required headless checks completed successfully."
