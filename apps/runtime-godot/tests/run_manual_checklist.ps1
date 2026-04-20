param(
    [string]$OutputPath = "",
    [switch]$UseDefaults,
    [ValidateSet("pass", "fail", "pending")]
    [string]$DefaultResult = "pending",
    [string]$Reviewer = ""
)

$ErrorActionPreference = "Stop"

function New-ChecklistItem {
    param(
        [string]$Id,
        [string]$Section,
        [string]$Prompt
    )
    return [pscustomobject]@{
        Id      = $Id
        Section = $Section
        Prompt  = $Prompt
    }
}

function Get-ResultLabel {
    param([string]$Raw)
    switch ($Raw) {
        "pass" { return "PASS" }
        "fail" { return "FAIL" }
        default { return "PENDING" }
    }
}

function Get-ChecklistResult {
    param(
        [pscustomobject]$Item,
        [switch]$UseDefaults,
        [string]$DefaultResult
    )
    if ($UseDefaults) {
        return $DefaultResult
    }

    while ($true) {
        $inputRaw = Read-Host ("[{0}] {1} (p=pass, f=fail, n=pending)" -f $Item.Id, $Item.Prompt)
        $normalized = $inputRaw.Trim().ToLowerInvariant()
        switch ($normalized) {
            "p" { return "pass" }
            "pass" { return "pass" }
            "f" { return "fail" }
            "fail" { return "fail" }
            "n" { return "pending" }
            "pending" { return "pending" }
            default {
                Write-Host "Enter p, f, or n." -ForegroundColor Yellow
            }
        }
    }
}

function Get-OutputPath {
    param([string]$RequestedPath)
    if ($RequestedPath -ne "") {
        return $RequestedPath
    }

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..")).Path
    $dateStamp = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $repoRoot ("docs\product\PLAN5_MANUAL_VERIFICATION_LOG_{0}.md" -f $dateStamp)
}

$items = @(
    (New-ChecklistItem -Id "OB1" -Section "Overlay Basics" -Prompt "Launch transparent always-on-top window."),
    (New-ChecklistItem -Id "OB2" -Section "Overlay Basics" -Prompt "Left-click drag feels smooth while held; release settles back to floor cleanly."),
    (New-ChecklistItem -Id "OB3" -Section "Overlay Basics" -Prompt "Right-click sleep toggle."),

    (New-ChecklistItem -Id "MM1" -Section "Multi-Monitor" -Prompt "Drag across monitor edges/displays."),
    (New-ChecklistItem -Id "MM2" -Section "Multi-Monitor" -Prompt "F8 moves companion to next monitor."),
    (New-ChecklistItem -Id "MM3" -Section "Multi-Monitor" -Prompt "Restart restores monitor + window position."),

    (New-ChecklistItem -Id "BE1" -Section "Behavior and Encounters" -Prompt "Idle transitions over several ticks feel correct."),
    (New-ChecklistItem -Id "BE2" -Section "Behavior and Encounters" -Prompt "Quiet-hours lowers active events."),
    (New-ChecklistItem -Id "BE3" -Section "Behavior and Encounters" -Prompt "F7 event frequency cadence feels correct."),
    (New-ChecklistItem -Id "BE4" -Section "Behavior and Encounters" -Prompt "F2 prompt frequency cadence feels correct."),
    (New-ChecklistItem -Id "BE5" -Section "Behavior and Encounters" -Prompt "Event budgets suppress repeat encounter spam."),

    (New-ChecklistItem -Id "PG1" -Section "Progression and Unlocks" -Prompt "Pet loop increases bond XP/level."),
    (New-ChecklistItem -Id "PG2" -Section "Progression and Unlocks" -Prompt "Unlock growth appears at expected levels."),
    (New-ChecklistItem -Id "PG3" -Section "Progression and Unlocks" -Prompt "Restart preserves progression state."),

    (New-ChecklistItem -Id "CP1" -Section "Content Packs" -Prompt "F9 pack cycle works in runtime (validate by pack id/chat telemetry, visuals may be subtle)."),
    (New-ChecklistItem -Id "CP2" -Section "Content Packs" -Prompt "Telemetry reflects active pack."),

    (New-ChecklistItem -Id "VS1" -Section "Vertical Slice" -Prompt "Movement left/right is smooth."),
    (New-ChecklistItem -Id "VS2" -Section "Vertical Slice" -Prompt "Jump leaves and lands correctly (vertical-slice window only)."),
    (New-ChecklistItem -Id "VS3" -Section "Vertical Slice" -Prompt "Emote keys E/R/T/Y work and recover (vertical-slice window only)."),
    (New-ChecklistItem -Id "VS4" -Section "Vertical Slice" -Prompt "Facing flip matches movement direction."),
    (New-ChecklistItem -Id "VS5" -Section "Vertical Slice" -Prompt "Floor lock remains stable under repeated jumps."),
    (New-ChecklistItem -Id "VS6" -Section "Vertical Slice" -Prompt "Top hint text wraps and stays readable."),

    (New-ChecklistItem -Id "SB1" -Section "Speech Bubble Timer" -Prompt "Idle bubble appears at expected cadence."),
    (New-ChecklistItem -Id "SB2" -Section "Speech Bubble Timer" -Prompt "Bubble duration timeout works."),
    (New-ChecklistItem -Id "SB3" -Section "Speech Bubble Timer" -Prompt "[ and ] duration controls work."),
    (New-ChecklistItem -Id "SB4" -Section "Speech Bubble Timer" -Prompt "After [ or ] and pressing M, updated duration applies to new say event.")
)

$results = @()
$failNotes = @()

foreach ($item in $items) {
    $result = Get-ChecklistResult -Item $item -UseDefaults:$UseDefaults -DefaultResult $DefaultResult
    $results += [pscustomobject]@{
        Id      = $item.Id
        Section = $item.Section
        Prompt  = $item.Prompt
        Result  = $result
    }
    if ($result -eq "fail" -and -not $UseDefaults) {
        $note = Read-Host ("Issue note for {0}" -f $item.Id)
        if ($note.Trim() -ne "") {
            $failNotes += ("- [{0}] {1}" -f $item.Id, $note.Trim())
        }
    }
}

$passCount = ($results | Where-Object { $_.Result -eq "pass" }).Count
$failCount = ($results | Where-Object { $_.Result -eq "fail" }).Count
$pendingCount = ($results | Where-Object { $_.Result -eq "pending" }).Count

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
$lines += "# Plan 5 Manual Verification Log (Desktop Checklist)"
$lines += ""
$lines += "Date: $headerDate  "
$lines += "Plan: Plan 5: Manual Desktop Verification Gate  "
$lines += "Checklist source: apps/runtime-godot/tests/SCENARIO_CHECKLIST.md  "
$lines += "Generated: $runTimestamp  "
$lines += "Reviewer: $reviewerLine"
$lines += ""
$lines += "## Summary"
$lines += ""
$lines += "- Result counts: PASS=$passCount FAIL=$failCount PENDING=$pendingCount"
$lines += "- Gate status: **$gateStatus**"
$lines += ""
$lines += "## Automated Pre-Check"
$lines += ""
$lines += "Command: pwsh -NoLogo -File apps/runtime-godot/tests/run_headless_checks.ps1"
$lines += ""
$lines += "Status: run manually before final sign-off"

$sections = $results | Group-Object Section
foreach ($section in $sections) {
    $lines += ""
    $lines += ("## {0}" -f $section.Name)
    $lines += ""
    foreach ($row in $section.Group) {
        $label = Get-ResultLabel -Raw $row.Result
        $lines += ("- [{0}] {1} ({2})" -f $row.Id, $row.Prompt, $label)
    }
}

$lines += ""
$lines += "## Issues"
$lines += ""
if ($failNotes.Count -eq 0) {
    $lines += "- None logged."
} else {
    $lines += $failNotes
}
$lines += ""
$lines += "## Follow-Up"
$lines += ""
$lines += "- If gate status is FAIL, create fix tickets and rerun this checklist."
$lines += "- If gate status is IN_PROGRESS, complete pending checks and rerun."

Set-Content -Path $outputFile -Value $lines -Encoding UTF8

Write-Host ("Manual verification log written: {0}" -f $outputFile) -ForegroundColor Green
Write-Host ("Summary => PASS={0}, FAIL={1}, PENDING={2}, Gate={3}" -f $passCount, $failCount, $pendingCount, $gateStatus)
