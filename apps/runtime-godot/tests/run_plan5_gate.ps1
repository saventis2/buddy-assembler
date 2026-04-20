param(
    [string]$OutputPath = "",
    [switch]$SkipHeadless,
    [switch]$SkipRuntimeLaunch,
    [switch]$UseDefaults,
    [ValidateSet("pass", "fail", "pending")]
    [string]$DefaultResult = "pending",
    [string]$Reviewer = ""
)

$ErrorActionPreference = "Stop"

$testsRoot = (Resolve-Path $PSScriptRoot).Path
$projectRoot = (Resolve-Path (Join-Path $testsRoot "..")).Path
$headlessScript = Join-Path $testsRoot "run_headless_checks.ps1"
$manualScript = Join-Path $testsRoot "run_manual_checklist.ps1"

if (-not (Test-Path $headlessScript)) {
    throw "Missing headless checks script: $headlessScript"
}
if (-not (Test-Path $manualScript)) {
    throw "Missing manual checklist script: $manualScript"
}

if (-not $SkipHeadless) {
    Write-Host "Running headless verification gate..." -ForegroundColor Cyan
    & pwsh -NoLogo -File $headlessScript
    $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($exitCode -ne 0) {
        throw "Headless verification failed with exit code $exitCode"
    }
}

if (-not $SkipRuntimeLaunch) {
    $godotCmd = Get-Command godot -ErrorAction SilentlyContinue
    if (-not $godotCmd) {
        throw "Godot is not on PATH. Install Godot 4 or run with -SkipRuntimeLaunch."
    }

    Write-Host "Launching runtime session for Overlay/Multi-Monitor/Behavior checks..." -ForegroundColor Cyan
    Write-Host "Close the runtime window when finished with that section." -ForegroundColor Yellow
    & godot --path $projectRoot
    $runtimeExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($runtimeExit -ne 0) {
        throw "Runtime session exited with code $runtimeExit"
    }

    Write-Host "Launching vertical-slice session for VS/Speech Bubble checks..." -ForegroundColor Cyan
    Write-Host "Close the vertical-slice window when finished with that section." -ForegroundColor Yellow
    & godot --path $projectRoot -- --vertical-slice
    $sliceExit = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($sliceExit -ne 0) {
        throw "Vertical-slice session exited with code $sliceExit"
    }
}

Write-Host "Running guided manual checklist logger..." -ForegroundColor Cyan
$manualArgs = @("-NoLogo", "-File", $manualScript)
if ($OutputPath -ne "") {
    $manualArgs += @("-OutputPath", $OutputPath)
}
if ($UseDefaults) {
    $manualArgs += "-UseDefaults"
    $manualArgs += @("-DefaultResult", $DefaultResult)
}
if ($Reviewer -ne "") {
    $manualArgs += @("-Reviewer", $Reviewer)
}

& pwsh @manualArgs
$manualExitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
if ($manualExitCode -ne 0) {
    throw "Manual checklist logger failed with exit code $manualExitCode"
}

Write-Host "Plan 5 gate runner completed." -ForegroundColor Green
