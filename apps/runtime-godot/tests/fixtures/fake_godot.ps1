param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

if ($RemainingArgs -contains "--version") {
    Write-Output "4.2.2.stable.official.test-double"
    exit 0
}

$exitCode = 0
if ($env:BUDDY_FAKE_GODOT_EXIT_CODE) {
    $exitCode = [int]$env:BUDDY_FAKE_GODOT_EXIT_CODE
}
Write-Output "fake_godot: requested exit $exitCode"
exit $exitCode
