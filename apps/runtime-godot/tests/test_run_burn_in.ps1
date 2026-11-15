$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$wrapper = Join-Path $PSScriptRoot "run_burn_in.ps1"
$fakeGodot = Join-Path $PSScriptRoot "fixtures\fake_godot.ps1"
$pwsh = (Get-Process -Id $PID).Path
$cases = @(
    @{ Name = "success"; ChildExit = 0; Expected = 0 },
    @{ Name = "child-failure"; ChildExit = 23; Expected = 23 }
)

$ran = 0
foreach ($case in $cases) {
    $ran += 1
    $env:BUDDY_FAKE_GODOT_EXIT_CODE = [string]$case.ChildExit
    try {
        $output = @(& $pwsh -NoProfile -File $wrapper -Duration 1 -Godot $fakeGodot 2>&1)
        $actual = $LASTEXITCODE
    } finally {
        Remove-Item Env:BUDDY_FAKE_GODOT_EXIT_CODE -ErrorAction SilentlyContinue
    }
    if ($actual -ne $case.Expected) {
        Write-Error "burn-in wrapper case '$($case.Name)' expected exit $($case.Expected), got $actual. Output: $($output -join ' | ')"
        exit 1
    }
    if (-not ($output -match "idle_profile: godot exited with $($case.ChildExit)")) {
        Write-Error "burn-in wrapper case '$($case.Name)' did not report the child exit. Output: $($output -join ' | ')"
        exit 1
    }
    Write-Host "test_run_burn_in[$($case.Name)]: ok"
}

Write-Host "test_run_burn_in: PASS ($ran cases)"
