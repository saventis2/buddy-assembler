# Thin convenience wrapper around record_perf_baseline.py.
#
# All parsing/formatting logic lives in the Python script — it's testable
# without a Godot or pwsh toolchain (see tools/tests/test_record_perf_baseline.py)
# and is the thing that has actually been verified. This wrapper only exists
# so Windows users running tests/run_burn_in.ps1 can stay in PowerShell for
# the whole burn-in -> record-a-row workflow instead of switching shells.
#
# NOTE: unlike record_perf_baseline.py, this .ps1 file itself has NOT been
# executed/verified — pwsh is not available in the environment that produced
# it. It is a straight argument-forwarding wrapper with no logic of its own,
# but treat it as unverified until someone runs it on Windows. If it
# misbehaves, call the Python script directly:
#   python apps\runtime-godot\tools\record_perf_baseline.py <log_file> --build "..."
#
# Usage (mirrors record_perf_baseline.py's own arguments):
#   .\record_perf_baseline.ps1 <log_file> --build "exported v0.1-rc"
#   .\record_perf_baseline.ps1 <log_file> --build "exported v0.1-rc" --update-baseline

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassthroughArgs
)

$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "record_perf_baseline.py"

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Error "record_perf_baseline.ps1: no 'python' or 'py' found on PATH. Install Python 3, or call the script directly once it's available."
    exit 1
}

& $python.Source $script @PassthroughArgs
exit $LASTEXITCODE
