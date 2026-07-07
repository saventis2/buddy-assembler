param(
    [string]$OutputPath = "",
    [switch]$UseDefaults,
    [ValidateSet("pass", "fail", "skipped", "pending")]
    [string]$DefaultResult = "pending",
    [string]$Reviewer = ""
)

$ErrorActionPreference = "Stop"

function New-ScenarioItem {
    param(
        [string]$Id,
        [int]$Number,
        [string]$Title,
        [string]$Prompt
    )
    return [pscustomobject]@{
        Id     = $Id
        Number = $Number
        Title  = $Title
        Prompt = $Prompt
    }
}

function Get-ResultLabel {
    param([string]$Raw)
    switch ($Raw) {
        "pass"    { return "P" }
        "fail"    { return "F" }
        "skipped" { return "S" }
        default   { return "PENDING" }
    }
}

function Get-ScenarioResult {
    param(
        [pscustomobject]$Item,
        [switch]$UseDefaults,
        [string]$DefaultResult
    )
    if ($UseDefaults) {
        return $DefaultResult
    }

    while ($true) {
        $inputRaw = Read-Host ("[{0}] {1} (p=pass, f=fail, s=skipped)" -f $Item.Id, $Item.Prompt)
        $normalized = $inputRaw.Trim().ToLowerInvariant()
        switch ($normalized) {
            "p" { return "pass" }
            "pass" { return "pass" }
            "f" { return "fail" }
            "fail" { return "fail" }
            "s" { return "skipped" }
            "skip" { return "skipped" }
            "skipped" { return "skipped" }
            default {
                Write-Host "Enter p, f, or s." -ForegroundColor Yellow
            }
        }
    }
}

function Format-TableCell {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }
    $clean = $Text -replace "\r?\n", " "
    $clean = $clean -replace "\|", "\|"
    return $clean.Trim()
}

function Get-OutputPath {
    param([string]$RequestedPath)
    if ($RequestedPath -ne "") {
        return $RequestedPath
    }

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    $dateStamp = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $repoRoot ("docs\product\RC_SCENARIO_SUITE_LOG_{0}.md" -f $dateStamp)
}

# One-line prompts only. Full step-by-step detail (preconditions, steps,
# expected results, reset instructions) lives in
# docs/product/RC_SCENARIO_SUITE.md - that file remains the source of
# truth; this script is a guided results-log generator, not a replacement.
$scenarios = @(
    (New-ScenarioItem -Id "RC1" -Number 1 -Title "First run" -Prompt "Launch on a clean save dir: companion appears; settings/profile/world_state json files are created with schemaVersion; no crash dialog."),
    (New-ScenarioItem -Id "RC2" -Number 2 -Title "Restart" -Prompt "Quit and relaunch: companion reappears near its last position; no duplicate first-run defaults written."),
    (New-ScenarioItem -Id "RC3" -Number 3 -Title "Drag / click interaction" -Prompt "Drag the companion smoothly to a new spot and release; right-click behavior matches the V1 spec (or is absent/N/A)."),
    (New-ScenarioItem -Id "RC4" -Number 4 -Title "Idle behavior" -Prompt "Leave idle for 60s: idle animation plays, CPU stays low (<5%), no meaningful memory growth."),
    (New-ScenarioItem -Id "RC5" -Number 5 -Title "Sleep" -Prompt "Trigger sleep, observe ~30s, then wake: reduced-activity state, lower CPU, clean glitch-free wake."),
    (New-ScenarioItem -Id "RC6" -Number 6 -Title "Visits" -Prompt "Trigger a visit event and watch it play out: it returns to idle without blocking input and leaves nothing orphaned on screen."),
    (New-ScenarioItem -Id "RC7" -Number 7 -Title "Invalid content fallback" -Prompt "Point settings.json's selected pack at a nonexistent id and launch: no crash, companion still appears via core/builtin fallback, and the fallback is logged."),
    (New-ScenarioItem -Id "RC8" -Number 8 -Title "Corrupted settings recovery" -Prompt "Overwrite settings.json with invalid JSON and launch: runtime starts on defaults, writes a fresh valid settings.json, and quarantines the corrupt file."),
    (New-ScenarioItem -Id "RC9" -Number 9 -Title "Exported build launches cleanly" -Prompt "Run the exported exe on a machine with no Godot editor installed: launches with no missing-DLL errors, creates the save dir under that user's APPDATA, and responds to input.")
)

$results = @()

foreach ($scenario in $scenarios) {
    $result = Get-ScenarioResult -Item $scenario -UseDefaults:$UseDefaults -DefaultResult $DefaultResult
    $note = ""
    if ($result -eq "fail" -and -not $UseDefaults) {
        $noteRaw = Read-Host ("Issue note for {0}" -f $scenario.Id)
        $note = $noteRaw.Trim()
    }
    $results += [pscustomobject]@{
        Id     = $scenario.Id
        Number = $scenario.Number
        Title  = $scenario.Title
        Result = $result
        Note   = $note
    }
}

$passCount = ($results | Where-Object { $_.Result -eq "pass" }).Count
$failCount = ($results | Where-Object { $_.Result -eq "fail" }).Count
$skippedCount = ($results | Where-Object { $_.Result -eq "skipped" }).Count
$pendingCount = ($results | Where-Object { $_.Result -notin @("pass", "fail", "skipped") }).Count

$gateStatus = "IN_PROGRESS"
if ($failCount -eq 0 -and $pendingCount -eq 0) {
    $gateStatus = "PASS"
} elseif ($failCount -gt 0) {
    $gateStatus = "FAIL"
}

$outputFile = Get-OutputPath -RequestedPath $OutputPath
$outputDir = Split-Path -Path $outputFile -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$headerDate = Get-Date -Format "yyyy-MM-dd"
$runTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz"
$reviewerLine = if ($Reviewer.Trim() -ne "") { $Reviewer.Trim() } else { "Unspecified" }

$lines = @()
$lines += "# RC Scenario Suite Log"
$lines += ""
$lines += "Date: $headerDate  "
$lines += "Suite: RC Scenario Suite (release-candidate smoke)  "
$lines += "Scenario source: docs/product/RC_SCENARIO_SUITE.md  "
$lines += "Generated: $runTimestamp  "
$lines += "Reviewer: $reviewerLine"
$lines += ""
$lines += "## Summary"
$lines += ""
$lines += "- Result counts: PASS=$passCount FAIL=$failCount SKIPPED=$skippedCount PENDING=$pendingCount"
$lines += "- Gate status: **$gateStatus**"
$lines += ""
$lines += "## Results"
$lines += ""
$lines += "| # | Scenario | Result | Notes |"
$lines += "|---|----------|--------|-------|"
foreach ($row in $results) {
    $label = Get-ResultLabel -Raw $row.Result
    $noteCell = Format-TableCell -Text $row.Note
    $lines += ("| {0} | {1} | {2} | {3} |" -f $row.Number, $row.Title, $label, $noteCell)
}

$lines += ""
$lines += "## Follow-Up"
$lines += ""
$lines += "- If gate status is FAIL, file fix tickets, resolve, and rerun the full suite before cutting a release tag."
$lines += "- If gate status is IN_PROGRESS, complete the remaining scenarios and rerun."
$lines += "- Do not cut a release tag while gate status is FAIL or IN_PROGRESS."
$lines += "- Full step-by-step scenario detail lives in docs/product/RC_SCENARIO_SUITE.md."

Set-Content -Path $outputFile -Value $lines -Encoding UTF8

Write-Host ("RC scenario suite log written: {0}" -f $outputFile) -ForegroundColor Green
Write-Host ("Summary => PASS={0}, FAIL={1}, SKIPPED={2}, PENDING={3}, Gate={4}" -f $passCount, $failCount, $skippedCount, $pendingCount, $gateStatus)
