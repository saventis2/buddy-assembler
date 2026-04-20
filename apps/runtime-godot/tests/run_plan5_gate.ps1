param(
    [string]$OutputPath = "",
    [switch]$SkipHeadless,
    [switch]$UseDefaults,
    [ValidateSet("pass", "fail", "pending")]
    [string]$DefaultResult = "pending",
    [string]$Reviewer = ""
)

$ErrorActionPreference = "Stop"

$testsRoot = (Resolve-Path $PSScriptRoot).Path
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
