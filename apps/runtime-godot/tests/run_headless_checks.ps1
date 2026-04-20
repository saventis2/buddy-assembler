param(
    [switch]$Profile
)

$ErrorActionPreference = "Stop"

$projectPath = Join-Path $PSScriptRoot ".."
$projectPath = (Resolve-Path $projectPath).Path

Write-Host "Runtime project path: $projectPath"

$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "Godot is not on PATH. Install Godot 4 and rerun this script."
    exit 2
}

function Invoke-GodotHeadless {
    param([string[]]$ExtraArgs, [string]$Label)
    & godot --headless --path $projectPath @ExtraArgs
    $code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    return $code
}

# --- Parse check ---
Write-Host ""
Write-Host "=== Parse check ==="
$parseCode = Invoke-GodotHeadless -ExtraArgs @("--quit") -Label "parse"
if ($parseCode -ne 0) {
    Write-Host "Parse check FAILED (exit $parseCode)"
    exit $parseCode
}
Write-Host "Parse check PASSED."

# --- Smoke floor-lock test ---
Write-Host ""
Write-Host "=== Smoke floor-lock test ==="
$smokeCode = Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/SmokeFloorLockTest.tscn") -Label "smoke"
if ($smokeCode -ne 0) {
    Write-Host "Smoke floor-lock test FAILED (exit $smokeCode)"
    exit $smokeCode
}
Write-Host "Smoke floor-lock test PASSED."

# --- Save store durability test ---
Write-Host ""
Write-Host "=== Save store durability test ==="
$saveCode = Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/SaveStoreTest.tscn") -Label "save-store"
if ($saveCode -ne 0) {
    Write-Host "Save store durability test FAILED (exit $saveCode)"
    exit $saveCode
}
Write-Host "Save store durability test PASSED."

# --- Pack validation + fallback test ---
Write-Host ""
Write-Host "=== Pack validation + fallback test ==="
$packCode = Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/PackValidationTest.tscn") -Label "pack-validation"
if ($packCode -ne 0) {
    Write-Host "Pack validation test FAILED (exit $packCode)"
    exit $packCode
}
Write-Host "Pack validation test PASSED."

# --- World + economy flow test ---
Write-Host ""
Write-Host "=== World + economy flow test ==="
$worldEcoCode = Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/WorldEconomyFlowTest.tscn") -Label "world-economy-flow"
if ($worldEcoCode -ne 0) {
    Write-Host "World + economy flow test FAILED (exit $worldEcoCode)"
    exit $worldEcoCode
}
Write-Host "World + economy flow test PASSED."

# --- Companion depth cadence test ---
Write-Host ""
Write-Host "=== Companion depth cadence test ==="
$depthCode = Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/CompanionDepthTest.tscn") -Label "companion-depth"
if ($depthCode -ne 0) {
    Write-Host "Companion depth cadence test FAILED (exit $depthCode)"
    exit $depthCode
}
Write-Host "Companion depth cadence test PASSED."

# --- Economy tuning test ---
Write-Host ""
Write-Host "=== Economy tuning test ==="
$economyCode = Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/EconomyTuningTest.tscn") -Label "economy-tuning"
if ($economyCode -ne 0) {
    Write-Host "Economy tuning test FAILED (exit $economyCode)"
    exit $economyCode
}
Write-Host "Economy tuning test PASSED."

# --- Optional: frame-time profiling ---
if ($Profile) {
    Write-Host ""
    Write-Host "=== Frame-time profiling (20 actors, 300 frames) ==="
    Invoke-GodotHeadless -ExtraArgs @("--scene", "res://tests/ProfileScene.tscn") -Label "profile" | Out-Null
    Write-Host "Profiling run complete (non-blocking)."
}

Write-Host ""
Write-Host "All headless checks completed successfully."
